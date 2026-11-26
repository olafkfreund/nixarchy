{ pkgs }:

let
  check =
    pkgs.writers.writePython3 "edge-promotion-check" { libraries = [ pkgs.python3Packages.pyyaml ]; }
      ''
        import pathlib
        import sys
        import yaml

        jobs = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())["jobs"]
        publish = jobs.get("publish-promotion")
        if not publish:
            sys.exit("FAILED: promotion artifact job is missing")

        required_needs = {"prepare", "verify", "report"}
        if not required_needs.issubset(set(publish.get("needs", []))):
            sys.exit("FAILED: publication must wait for prepare, verify and report")

        required_guard = {
            "needs.report.result == 'success'",
            "needs.verify.outputs.promoted == 'true'",
            "needs.prepare.outputs.skip != 'true'",
            "inputs.dry_run != true",
            "github.ref == 'refs/heads/main'",
        }
        guard = publish.get("if", "").strip().lstrip("$").strip("{} ")
        conditions = [part.strip() for part in guard.split("&&")]
        if set(conditions) != required_guard or len(conditions) != len(required_guard):
            sys.exit("FAILED: publication guard permits an unverified promotion")

        steps = publish.get("steps", [])
        uploads = [
            step for step in steps
            if step.get("uses", "").startswith("actions/upload-artifact@")
        ]
        if len(uploads) != 1 or uploads[0]["with"].get("name") != "edge-promotion":
            sys.exit("FAILED: expected one edge-promotion artifact upload")
        if not any(
            "candidate_sha" in step.get("run", "")
            and "run_attempt" in step.get("run", "")
            for step in steps
        ):
            sys.exit("FAILED: artifact must contain the candidate SHA and run attempt")
        print("edge-promotion: guard and artifact pass")
      '';
in
pkgs.runCommand "nixarchy-edge-promotion" { } ''
  ${check} ${../.github/workflows/omarchy-edge.yml}
  touch "$out"
''
