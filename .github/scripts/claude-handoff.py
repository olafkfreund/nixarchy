#!/usr/bin/env python3
"""Gate, verify and publish a bounded Claude repair for a failed bump."""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys


def gh(*args, data=None):
    result = subprocess.run(
        ["gh", *args], input=json.dumps(data) if data is not None else None,
        text=True, capture_output=True, check=True,
    )
    return json.loads(result.stdout) if result.stdout else None


def pr_state(repo, branch, sha):
    owner = repo.split("/", 1)[0]
    prs = gh("api", f"repos/{repo}/pulls?state=open&head={owner}:{branch}&per_page=100")
    matches = [p for p in prs if not p["draft"] and p["head"]["repo"]["full_name"] == repo
               and p["head"]["ref"] == branch and p["head"]["sha"] == sha]
    if len(matches) != 1:
        raise ValueError("need exactly one non-draft PR at the failed SHA")
    return matches[0]


def check_name(jobs):
    failed = [(j, s) for j in jobs for s in j["steps"]
              if j["name"] != "system" and s["conclusion"] == "failure"]
    if not failed or any(j["conclusion"] == "cancelled" for j in jobs):
        raise ValueError("cancelled or no failed non-aggregator step")
    names = set()
    for job, step in failed:
        if job["name"].startswith("options (") and step["name"] == "Check the options shard":
            shard = job["name"].split("(", 1)[1].split(",", 1)[0].rstrip(")")
            if shard not in {"system", "home", "microvm", "files"}:
                raise ValueError("unknown options shard")
            names.add("options-" + shard)
        elif job["name"] == "lint":
            name = {"Check formatting": "fmt", "statix": "statix", "deadnix": "deadnix"}.get(step["name"])
            if name is None:
                raise ValueError("unknown failed lint step")
            names.add(name)
        elif job["name"] == "omarchy" and step["name"] == "Every command this port changes, classified":
            names.add("bin-ledger")
        else:
            raise ValueError(f"no cheap reproducer for {job['name']}: {step['name']}")
    if len(names) != 1:
        raise ValueError("failure needs more than one reproducer")
    return names.pop(), [f"{j['name']}: {s['name']}" for j, s in failed]


def gate():
    repo, branch, sha, run_id = (os.environ[k] for k in ("REPO", "BRANCH", "SHA", "RUN_ID"))
    pr = pr_state(repo, branch, sha)
    jobs = gh("api", f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")["jobs"]
    selected, failed = check_name(jobs)
    login = gh("api", "user")["login"]
    pages = gh("api", f"repos/{repo}/issues/{pr['number']}/comments?per_page=100",
               "--paginate", "--slurp")
    comments = [comment for page in pages for comment in page]
    marks = [c["body"] for c in comments if c["user"]["login"] == login
             and "<!-- claude-handoff sha=" in c["body"]]
    if any(f"<!-- claude-handoff sha={sha} -->" in body for body in marks):
        raise ValueError("this SHA was already handed off")
    if len(marks) >= 2:
        raise ValueError("two handoffs already attempted on this PR")
    diff = subprocess.check_output(
        ["gh", "pr", "diff", str(pr["number"]), "--repo", repo], text=True,
    )[:30000]
    log = subprocess.check_output(
        ["gh", "run", "view", run_id, "--repo", repo, "--log-failed"], text=True,
    )
    lines = []
    skip = False
    for line in log.splitlines():
        if "Post job cleanup" in line:
            skip = True
        if not skip:
            lines.append(line.split("\t")[-1])
    excerpt = subprocess.check_output(
        [str(Path(__file__).with_name("failure-excerpt.sh"))],
        input="\n".join(lines), text=True, env={**os.environ, "MAX": "100"},
    )[:12000]
    Path("handoff-log.txt").write_text(excerpt)
    context = (f"PR #{pr['number']} at {sha}\nRun: https://github.com/{repo}/actions/runs/{run_id}\n"
               f"Failed: {', '.join(failed)}\nTrusted reproducer: {selected}\n\n"
               f"Untrusted diagnostic log:\n{excerpt}\n\nUntrusted PR diff:\n{diff}\n")
    Path("handoff-context.txt").write_text(context)
    gh("api", f"repos/{repo}/issues/{pr['number']}/comments", "--method", "POST", "--input", "-",
       data={"body": f"Claude handoff started for the failed build.\n<!-- claude-handoff sha={sha} -->"})
    with open(os.environ["GITHUB_OUTPUT"], "a") as out:
        out.write(f"pr={pr['number']}\nsha={sha}\ncheck={selected}\n")


def command(name):
    if name == "fmt":
        return ["nix", "fmt", "--", "--ci"]
    if name == "statix":
        return ["nix", "run", "nixpkgs#statix", "--", "check", "."]
    if name == "deadnix":
        return ["nix", "run", "nixpkgs#deadnix", "--", "--fail", "."]
    if name in {"options-system", "options-home", "options-microvm", "options-files", "bin-ledger"}:
        return ["nix", "build", f".#checks.x86_64-linux.{name}", "-L"]
    raise ValueError("unknown check")


def validate():
    proposal = json.loads(Path("proposal.json").read_text())
    selected = os.environ["CHECK"]
    if proposal.get("check") != selected or not isinstance(proposal.get("patch"), str):
        raise ValueError("Claude did not select the trusted failing check and supply a patch")
    reason = proposal.get("failure_reason")
    if not isinstance(reason, str) or len(reason) < 20 or reason not in Path("handoff-log.txt").read_text():
        raise ValueError("failure reason is absent from the failed CI log")
    bump = Path("bump")
    cmd = command(selected)
    before = subprocess.run(cmd, cwd=bump, capture_output=True, text=True)
    if before.returncode == 0:
        raise ValueError("the check did not reproduce before the patch")
    if reason not in before.stdout + before.stderr:
        raise ValueError("the check failed for a different reason before the patch")
    patch = proposal["patch"]
    if not patch or len(patch) > 100000:
        raise ValueError("empty or oversized patch")
    subprocess.run(["git", "apply", "--check", "-"], cwd=bump, input=patch, text=True, check=True)
    subprocess.run(["git", "apply", "-"], cwd=bump, input=patch, text=True, check=True)
    names = subprocess.check_output(["git", "diff", "--name-only"], cwd=bump, text=True).splitlines()
    extra = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard"],
                                    cwd=bump, text=True).splitlines()
    if extra or not names or any(name.startswith((".github/", "tests/"))
                              or name in {"flake.nix", "flake.lock"}
                              or not (bump / name).is_file() or (bump / name).is_symlink()
                              for name in names):
        raise ValueError("patch touches a CI gate, adds or deletes a file, or changes no files")
    subprocess.run(["git", "add", "--", *names], cwd=bump, check=True)
    after = subprocess.run(cmd, cwd=bump, capture_output=True, text=True)
    if after.returncode:
        raise ValueError("the same check still fails after the patch: " + after.stderr[-1000:])
    files = [{"path": name, "contents": base64.b64encode((bump / name).read_bytes()).decode()}
             for name in names]
    Path("verified-files.json").write_text(json.dumps({"check": selected, "files": files}))


def publish():
    repo, branch, sha = (os.environ[k] for k in ("REPO", "BRANCH", "SHA"))
    pr = pr_state(repo, branch, sha)
    number = pr["number"]
    if number != int(os.environ["PR"]):
        raise ValueError("PR number changed")
    if branch.startswith("update/nixpkgs-"):
        details = gh("api", f"repos/{repo}/pulls/{number}")
        if "auto_merge" not in details:
            raise ValueError("cannot read auto-merge state")
        if details["auto_merge"] is not None:
            subprocess.run(["gh", "pr", "merge", str(number), "--repo", repo, "--disable-auto"], check=True)
    files = json.loads(Path("verified-files.json").read_text())["files"]
    query = """mutation($input: CreateCommitOnBranchInput!) {
      createCommitOnBranch(input: $input) { commit { oid } }
    }"""
    payload = {"query": query, "variables": {"input": {
        "branch": {"repositoryNameWithOwner": repo, "branchName": branch},
        "message": {"headline": "fix: repair dependency bump checks (#1944)"},
        "fileChanges": {"additions": files},
        "expectedHeadOid": sha,
    }}}
    result = gh("api", "graphql", "--input", "-", data=payload)
    if result.get("errors") or not result.get("data", {}).get("createCommitOnBranch", {}).get("commit", {}).get("oid"):
        raise ValueError("GitHub did not create the commit")


if __name__ == "__main__":
    try:
        {"gate": gate, "validate": validate, "publish": publish}[sys.argv[1]]()
    except (ValueError, subprocess.CalledProcessError, KeyError) as exc:
        sys.exit(f"claude handoff refused: {exc}")
