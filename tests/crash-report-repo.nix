{ pkgs, omarchy }:
# Where a crash report actually goes, checked against the built tree.
#
# `omarchy-crash-watch` announces every core dump and offers an AI diagnosis;
# clicking runs `omarchy-agent-crash`, which points the agent at the
# diagnose-crash skill, whose `reporting.md` decides the destination. This port
# rewrites that file so the destination can be Nixarchy.
#
# It rewrote the prose and not the commands. `reporting.md` said "When unsure,
# file against Nixarchy" three lines above five `gh` invocations that all
# carried `--repo basecamp/omarchy`. An agent read the rule, concluded
# correctly, and then copied a command that filed the issue at Basecamp. The
# narrative was ported; the executable part was not.
#
# Prose cannot be asserted, so this asserts the executable part: no `gh` line
# may name a repo the surrounding text did not choose. It is a grep over an
# already-built derivation -- no VM, no network, under a second -- and it fails
# naming the line, which is the whole point of writing it at all.
pkgs.runCommand "nixarchy-crash-report-repo"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
  }
  ''
    skills=${omarchy}/share/omarchy/default/agents/skills
    report=$skills/diagnose-crash/reporting.md
    test -f "$report" || { echo "no diagnose-crash/reporting.md in the built tree" >&2; exit 1; }

    fail=0

    # 1. Every `gh` command must target this port's repository. A `gh` line is
    #    something a reader copies; a sentence is something they interpret.
    if bad=$(grep -n '^gh .*--repo basecamp/omarchy' "$report"); then
      echo "" >&2
      echo "reporting.md still files against Basecamp from a gh command:" >&2
      echo "$bad" >&2
      echo "" >&2
      echo "Line 3 of that file tells the agent to file against Nixarchy when" >&2
      echo "unsure. A command that contradicts it is the one that gets run." >&2
      fail=1
    fi

    # 2. ...and they must actually name Nixarchy, so this cannot be satisfied
    #    by deleting the commands.
    for verb in 'gh search issues' 'gh issue list' 'gh issue view' 'gh issue comment' 'gh issue create'; do
      if ! grep -q "^$verb .*--repo olafkfreund/nixarchy" "$report"; then
        echo "no '$verb' line targeting olafkfreund/nixarchy in reporting.md" >&2
        fail=1
      fi
    done

    # 3. Omarchy must still be reachable as a destination: this port routes the
    #    Arch-identical half there, and a check that forbade the name outright
    #    would quietly delete that half of the rule.
    grep -q 'basecamp/omarchy' "$report" || {
      echo "reporting.md no longer mentions basecamp/omarchy at all." >&2
      echo "Crashes that would happen identically on Arch belong upstream;" >&2
      echo "dropping the destination loses that routing." >&2
      fail=1
    }

    # 4. The agent-room search (#271), executable in the same way as the gh
    #    lines: the search command must name the room the prose chose...
    grep -q 'search(query=.*room="#nixarchy-agents")' "$report" || {
      echo "reporting.md has no agent-room search naming #nixarchy-agents" >&2
      fail=1
    }
    #    ...and no other room. An agent copies the command, not the sentence
    #    above it -- the exact failure section 1 exists for.
    if bad=$(grep -n 'room="#' "$report" | grep -v 'nixarchy-agents'); then
      echo "reporting.md searches a room the prose did not choose:" >&2
      echo "$bad" >&2
      fail=1
    fi

    # 5. The step is gated on the bus existing. A machine without the bus is
    #    the majority; a step that nags or blocks there gets the whole
    #    section deleted, taking the useful half with it.
    grep -q 'No bus means no step' "$report" || {
      echo "the room search is no longer gated on the bus being configured" >&2
      fail=1
    }

    # 6. Posting back restates redaction AT THE POINT OF PASTING. Crash
    #    output is the likeliest content on the whole bus to carry paths,
    #    hostnames and tokens; a rule that lives only in a skill the agent
    #    may not have read is #303's lesson unlearned.
    grep -q '^## Close the loop in the agent room' "$report" || {
      echo "reporting.md never closes the loop in the room after filing" >&2
      fail=1
    }
    grep -q 'paste nothing you have not read in full' "$report" || {
      echo "the post-back section does not restate redaction where the paste happens" >&2
      fail=1
    }

    # 4. The prompt that runs before the skill is read. It set the destination
    #    first, so porting reporting.md alone left the agent already pointed at
    #    Basecamp when it arrived.
    crash=${omarchy}/share/omarchy/bin/omarchy-agent-crash
    if grep -q 'reporting upstream to Omarchy' "$crash"; then
      echo "" >&2
      echo "omarchy-agent-crash still primes the agent with 'reporting upstream" >&2
      echo "to Omarchy' before the skill is read." >&2
      fail=1
    fi

    [ "$fail" -eq 0 ] || exit 1
    echo "crash reports route to Nixarchy, with Omarchy still reachable"
    touch $out
  ''
