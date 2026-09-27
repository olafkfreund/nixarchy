# Adds one host's creation rule to an existing .sops.yaml, and nothing else.
#
# Its own package for the reason pkgs/ai-mirror-mcp-remove.nix is: the check
# has to run THIS code against fixtures rather than a copy of it. `nixarchy
# secret enroll` cannot be driven in a sandbox at all -- it reads the hostname
# from /proc/sys/kernel/hostname and the recipient from
# /etc/ssh/ssh_host_ed25519_key.pub, and a nix build sandbox has no /etc/ssh
# and reports `localhost`. Measured, not assumed. So the part worth checking
# is lifted out and handed its inputs.
#
# STRUCTURAL, via yq. The refusal in pkgs/secret.nix exists because a creation
# rule edited by pattern-matching is one that can silently stop matching, and
# that failure surfaces as a secret which will not decrypt long afterwards.
# Nothing here matches a pattern to decide where a rule goes.
#
# The recipient is written INLINE rather than as a YAML anchor. A policy's
# first host is usually hand-written with `- &host age1...` / `- *host`, and
# that pair is left exactly as it is -- rewriting it would be churn in a file
# whose parse decides whether anything on any machine decrypts. Anchors are
# the part of YAML that round-trips worst, so hosts added here do not gain
# one. yq resolves an alias when reading, so the already-present check below
# sees the first host's real recipient either way.
#
# Exit codes, because the caller prints the prose:
#
#   0   the rule was appended
#   2   this host is already in the policy, with this same recipient: no-op
#   3   this host is in the policy with a DIFFERENT recipient. Appending would
#       leave two rules claiming one path, and sops takes the first -- so the
#       machine would encrypt to a key it cannot read back. Reported, never
#       guessed at. The realistic cause is a reinstall that kept the hostname.
#   1   anything else
{
  writeShellApplication,
  yq-go,
  coreutils,
}:
writeShellApplication {
  name = "nixarchy-sops-policy-add";
  runtimeInputs = [
    yq-go
    coreutils
  ];
  text = ''
    if [ "$#" -ne 3 ]; then
      echo "usage: nixarchy-sops-policy-add <policy> <host> <recipient>" >&2
      exit 1
    fi

    policy="$1"
    host="$2"
    recipient="$3"

    if [ ! -e "$policy" ]; then
      echo "nixarchy-sops-policy-add: $policy does not exist." >&2
      exit 1
    fi

    # The spelling the hand-written rules use, so a policy stays readable as
    # one file rather than as two conventions.
    rule="hosts/$host/secrets\.yaml\$"

    # Read the file rather than remember having run. A second run has to know
    # it is a second run from the policy itself.
    existing=$(RULE="$rule" yq -r \
      '.creation_rules[]? | select(.path_regex == strenv(RULE)) | .key_groups[0].age[0] // ""' \
      "$policy" 2>/dev/null | head -1)

    if [ -n "$existing" ]; then
      if [ "$existing" = "$recipient" ]; then
        echo "already: $host is in $policy with this recipient"
        exit 2
      fi
      echo "mismatch: $policy has a rule for $host with a different recipient" >&2
      echo "  in the policy  $existing" >&2
      echo "  this machine   $recipient" >&2
      exit 3
    fi

    RECIPIENT="$recipient" RULE="$rule" yq -i \
      '.creation_rules += [{"path_regex": strenv(RULE), "key_groups": [{"age": [strenv(RECIPIENT)]}]}]' \
      "$policy"

    echo "added: $host to $policy"
  '';

  meta = {
    description = "Append one host's creation rule to an existing .sops.yaml";
    mainProgram = "nixarchy-sops-policy-add";
  };
}
