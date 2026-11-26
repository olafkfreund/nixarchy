{ pkgs, ... }:
let
  guard = pkgs.writeText "claude-handoff-guard.py" ''
    import copy
    import pathlib
    import sys
    import yaml

    path = pathlib.Path(sys.argv[1]) / "claude-handoff.yml"
    if not path.exists():
        sys.exit("missing claude-handoff.yml")
    workflow = yaml.safe_load(path.read_text())

    def check(doc):
        event = doc.get("on", doc.get(True))
        run = event["workflow_run"]
        assert run["workflows"] == ["build"] and run["types"] == ["completed"]
        assert doc["permissions"] == {}
        jobs = doc["jobs"]
        gate, propose, validate, publish = (jobs[name] for name in ("gate", "propose", "validate", "publish"))
        condition = gate["if"]
        assert "conclusion == 'failure'" in condition
        assert "startsWith(github.event.workflow_run.head_branch, 'update/')" in condition
        assert "github.event.workflow_run.head_repository.full_name == github.repository" in condition
        assert "gate" in propose["needs"] and "gate" in validate["needs"]
        assert "validate" in publish["needs"]
        for job in (gate, propose):
            checkout = [s for s in job["steps"] if str(s.get("uses", "")).startswith("actions/checkout@")]
            assert checkout and all(s.get("with", {}).get("persist-credentials") is False for s in checkout)
            assert all(s.get("with", {}).get("ref") == "''${{ github.sha }}" for s in checkout)
            assert not any("checkout@" in str(s.get("uses", "")) and s.get("with", {}).get("ref") != "''${{ github.sha }}" for s in propose["steps"])
        assert "secrets." not in str(validate) and "write" not in str(validate.get("permissions", {}))
        assert "secrets.CLAUDE_CODE_OAUTH_TOKEN" in str(propose)
        assert "secrets.BUMP_TOKEN" in str(publish)

    check(workflow)
    for name, mutate in (
        ("same repository", lambda d: d["jobs"]["gate"].update({"if": d["jobs"]["gate"]["if"].replace("github.event.workflow_run.head_repository.full_name == github.repository", "true")})),
        ("bump checkout in OAuth job", lambda d: d["jobs"]["propose"]["steps"].append({"uses": "actions/checkout@v5", "with": {"ref": "bump"}})),
    ):
        broken = copy.deepcopy(workflow)
        mutate(broken)
        try:
            check(broken)
        except (AssertionError, KeyError):
            print(f"control fails: {name}")
        else:
            sys.exit(f"control passed: {name}")
    print("claude handoff guard passes")
  '';
in
pkgs.runCommand "nixarchy-claude-handoff"
  {
    workflows = ../.github/workflows;
    HANDOFF_SCRIPT = ../.github/scripts/claude-handoff.py;
    nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
  }
  ''
    python ${guard} "$workflows"
    python ${./claude-handoff-fixtures.py}
    touch "$out"
  ''
