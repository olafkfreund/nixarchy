{ pkgs, ... }:
# #1856: both report paths keep a large digest within GitHub's issue body limit.
pkgs.runCommand "nixarchy-nightly-report-fit"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gawk
      gnugrep
      python3
      yq-go
    ];
  }
  ''
        failures=()
        fail() { failures+=("$*"); }
        yq -r '.jobs.report.steps[] | select(.name == "Open or update an issue") | .run' \
          ${../.github/workflows/nightly.yml} > step.sh
        python3 -c '
    import pathlib
    import re

    pattern = re.compile(r"\$\{\{\s*(.*?)\s*\}\}")
    source = pathlib.Path("step.sh").read_text()
    fixed = {"github.server_url": "https://github.test", "github.repository": "o/r", "github.run_id": "123"}

    def replace(match):
        expr = match.group(1)
        if expr == "contains(needs.*.result, " + chr(39) + "cancelled" + chr(39) + ")":
            return "true"
        if re.fullmatch(r"needs\.[A-Za-z0-9_-]+\.result", expr):
            return "cancelled" if expr == "needs.keyboard-boot.result" else "success"
        if expr in fixed:
            return fixed[expr]
        raise ValueError("unhandled GitHub expression: " + expr)

    rendered = pattern.sub(replace, source)
    if pattern.search(rendered):
        raise ValueError("unreplaced GitHub expression")
    pathlib.Path("rendered.sh").write_text(rendered)
    ' 
        mkdir bin
        printf '%s\n' \
          '#!${pkgs.bash}/bin/bash' \
          'set -euo pipefail' \
          'command=$1; shift' \
          'if [ "$command" = issue ] && [ "$1" = list ]; then printf "%s" "''${STUB_EXISTING:-}"; exit 0; fi' \
          'if [ "$command" = issue ] && [ "$1" = edit ]; then exit 0; fi' \
          'if [ "$command" != issue ] || { [ "$1" != create ] && [ "$1" != comment ]; }; then exit 2; fi' \
          'kind=$1; shift' \
          'body=' \
          'while [ "$#" -gt 0 ]; do' \
          '  if [ "$1" = --body ]; then body=$2; break; fi' \
          '  shift' \
          'done' \
          'printf "%s\n" "$kind" >> "$STUB_RECORD/calls"' \
          'printf "%s" "$body" > "$STUB_RECORD/body"' \
          > bin/gh
        chmod +x bin/gh
        export PATH="$PWD/bin:$PATH"
        export GH_REPO=o/r RUN=https://github.test/o/r/actions/runs/123 DIGEST_RESULT=success
    DIGEST=$(awk 'BEGIN { for (i = 0; i < 4999; i++) print "1234567890123456789"; printf "12345678901234567890" }')
        export DIGEST
        note="(cut to fit GitHub's limit; the run log has the rest)"
        for kind in create comment; do
          mkdir "$kind"
          if [ "$kind" = comment ]; then existing=7; else existing=; fi
          if ! STUB_RECORD="$PWD/$kind" STUB_EXISTING="$existing" bash -euo pipefail rendered.sh; then
            fail "$kind: report step exited non-zero"
          fi
          calls=$(wc -l < "$kind/calls" 2>/dev/null || echo 0)
          if [ "$calls" -ne 1 ] || [ "$(cat "$kind/calls" 2>/dev/null)" != "$kind" ]; then
            fail "$kind: expected exactly one $kind call, got $calls"
            continue
          fi
          size=$(wc -c < "$kind/body")
          [ "$size" -le 60000 ] || fail "$kind: body is $size bytes, over 60000"
          [ "$(tail -n 1 "$kind/body")" = "$note" ] || fail "$kind: body lacks the cut note at the end"
        done
        if [ "''${#failures[@]}" -gt 0 ]; then
          printf 'FAIL: %s\n' "''${failures[@]}" >&2
          exit 1
        fi
        touch $out
  ''
