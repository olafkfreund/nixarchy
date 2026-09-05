{
  pkgs,
  tryScript,
  tryApp,
}:
# The `try` front door's preflight, driven with an environment that lies.
#
# `nix run .#try` is the first thing a stranger types, on a machine nobody
# here has seen: no /dev/kvm, or /dev/kvm without the group; too little RAM;
# a dry-run that says "source build" because a cache prompt was declined; a
# qcow2 left behind by a ctrl-C. Each of those must produce a sentence naming
# the number measured and the way out -- and a preflight nobody has seen fail
# is a preflight nobody knows works, so every refusal below is exercised
# here, cheaply, with the same stub idiom tests/installer-store-space.nix
# uses against a lying df.
#
# No VM is booted and no network is touched: every asserted path exits before
# the script would reach nix or qemu. What this deliberately cannot prove --
# that the qemu invocation itself brings up a bootable UEFI window -- is the
# same class of gap microvm-template documents: the happy path needs a
# machine with KVM and a display, which a sandboxed derivation is not.
#
# Two layers:
#   1. the probe functions, sourced from installer/try.sh raw
#      (NIXARCHY_TRY_SOURCED=1 stops main) and fed stubbed TRY_* paths and a
#      lying df;
#   2. the BUILT app end to end -- which also makes the check depend on the
#      package, so "the app evaluates and its script passes shellcheck"
#      (writeShellApplication's own checkPhase) is asserted by construction.
pkgs.runCommand "nixarchy-try-preflight" { } ''
  test -x ${tryApp}/bin/nixarchy-try

  cp ${tryScript} try.sh
  cat > t.sh <<'EOF'
  set -u
  NIXARCHY_TRY_SOURCED=1
  . ./try.sh

  fails=0
  ok() { echo "  ok      $1"; }
  no() { echo "  FAILED  $1"; [ -s msg ] && sed 's/^/            /' msg; fails=$((fails + 1)); }

  # ---- KVM: existence is not the answer; openability is -------------------
  [ "$(TRY_KVM_DEV=/does/not/exist detect_kvm)" = none ] \
    && ok "no /dev/kvm -> none" || no "no /dev/kvm -> none"
  touch kvmfile && chmod 000 kvmfile
  [ "$(TRY_KVM_DEV=$PWD/kvmfile detect_kvm)" = nogroup ] \
    && ok "unopenable /dev/kvm -> nogroup" || no "unopenable /dev/kvm -> nogroup"
  chmod 600 kvmfile
  [ "$(TRY_KVM_DEV=$PWD/kvmfile detect_kvm)" = kvm ] \
    && ok "openable /dev/kvm -> kvm" || no "openable /dev/kvm -> kvm"

  explain_kvm none 2>msg
  grep -q 'SLOWER' msg && grep -q 'real hardware is not' msg \
    && ok "TCG fallback is loud, and blames the VM not nixarchy" \
    || no "TCG fallback is loud, and blames the VM not nixarchy"
  explain_kvm nogroup 2>msg
  grep -q "kvm' group" msg && grep -q 'usermod -aG kvm' msg \
    && ok "group refusal names the group and the command" \
    || no "group refusal names the group and the command"

  # ---- RAM: refuse with numbers, never OOM mid-boot -----------------------
  printf 'MemTotal: 4096 kB\nMemAvailable: %s kB\n' $((2048 * 1024)) > meminfo
  if TRY_MEMINFO=$PWD/meminfo check_ram 8192 2>msg; then
    no "2 GB free vs 8 GB wanted refuses"
  else
    grep -q '2048 MB' msg && grep -q '8192 MB' msg && grep -q -- '--memory' msg \
      && ok "RAM refusal carries both numbers and the way out" \
      || no "RAM refusal carries both numbers and the way out"
  fi
  if TRY_MEMINFO=$PWD/meminfo check_ram 1024 2>msg; then
    ok "2 GB free vs 1 GB wanted proceeds"
  else
    no "2 GB free vs 1 GB wanted proceeds"
  fi
  # Tolerance: a meminfo it cannot read must not invent a refusal.
  : > meminfo
  if TRY_MEMINFO=$PWD/meminfo check_ram 8192 2>msg; then
    ok "unreadable meminfo proceeds"
  else
    no "unreadable meminfo proceeds"
  fi

  # ---- disk: a lying df, exactly as installer-store-space does ------------
  df() { printf 'Type Avail\n%s %sM\n' "$FS" "$AVAIL"; }
  FS=tmpfs AVAIL=999999
  if check_disk /somewhere 100 "the target disk" 2>msg; then
    no "tmpfs refuses however much df claims"
  else
    grep -q 'RAM, not disk' msg \
      && ok "tmpfs refusal says RAM, not disk" \
      || no "tmpfs refusal says RAM, not disk"
  fi
  FS=ext4 AVAIL=100
  if check_disk /somewhere 24576 "the target disk" 2>msg; then
    no "100 MB free vs 24576 MB needed refuses"
  else
    grep -q '24576 MB' msg && grep -q '100 MB' msg \
      && ok "disk refusal carries both numbers" \
      || no "disk refusal carries both numbers"
  fi
  FS=ext4 AVAIL=999999
  if check_disk /somewhere 24576 "the target disk" 2>msg; then
    ok "room on a real filesystem proceeds"
  else
    no "room on a real filesystem proceeds"
  fi
  unset -f df

  # ---- the flakeref the image comes from ----------------------------------
  [ "$(resolve_ref abc123)" = "github:olafkfreund/nixarchy/abc123" ] \
    && ok "a committed rev resolves to a pinned github ref" \
    || no "a committed rev resolves to a pinned github ref"
  if resolve_ref "" 2>msg; then
    no "a dirty build refuses to guess an image"
  else
    grep -q 'uncommitted' msg && grep -q 'github:olafkfreund/nixarchy#try' msg \
      && ok "a dirty build refuses, naming the published front door" \
      || no "a dirty build refuses, naming the published front door"
  fi

  # ---- the release fallback's parse, on a JSON shaped like the real one ---
  # Including what v4.0.2-4 really looks like: SHA256SUMS names a -net.iso
  # and the release does not attach one. `iso-net` must come back empty
  # there, not grab an offline part.
  cat > rel.json <<'P'
  { "tag_name": "v9.9.9-9",
    "assets": [
      { "name": "nixarchy-v9.9.9-9.iso.part-ab",
        "browser_download_url": "https://example.invalid/nixarchy-v9.9.9-9.iso.part-ab" },
      { "name": "nixarchy-v9.9.9-9.iso.part-aa",
        "browser_download_url": "https://example.invalid/nixarchy-v9.9.9-9.iso.part-aa" },
      { "name": "SHA256SUMS",
        "browser_download_url": "https://example.invalid/SHA256SUMS" } ] }
  P
  [ "$(release_tag rel.json)" = "v9.9.9-9" ] \
    && ok "the release tag parses" || no "the release tag parses"
  [ "$(release_urls rel.json iso | head -n1)" = "https://example.invalid/nixarchy-v9.9.9-9.iso.part-aa" ] \
    && ok "offline parts come back sorted, aa first" \
    || no "offline parts come back sorted, aa first"
  [ "$(release_urls rel.json iso | wc -l)" = 2 ] \
    && ok "offline parts exclude SHA256SUMS" || no "offline parts exclude SHA256SUMS"
  [ -z "$(release_urls rel.json iso-net)" ] \
    && ok "a release with no net image says so, not a wrong URL" \
    || no "a release with no net image says so, not a wrong URL"
  [ "$(release_urls rel.json sums)" = "https://example.invalid/SHA256SUMS" ] \
    && ok "the checksum file is found" || no "the checksum file is found"

  # ---- the download-or-build decision, on plans nix really prints ---------
  cat > plan.build <<'P'
  these 431 derivations will be built:
    /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixarchy-v4.0.2.iso.drv
    /nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-squashfs.img.drv
  P
  [ "$(classify_plan plan.build)" = build ] \
    && ok "an image in the build list -> build" || no "an image in the build list -> build"

  cat > plan.fetch <<'P'
  these 12 paths will be fetched (1.87 GiB download, 5.61 GiB unpacked):
    /nix/store/cccccccccccccccccccccccccccccccc-nixarchy-v4.0.2.iso
  P
  [ "$(classify_plan plan.fetch)" = "fetch (1.87 GiB download, 5.61 GiB unpacked)" ] \
    && ok "a fetch plan -> fetch, with nix's sizes" || no "a fetch plan -> fetch, with nix's sizes"

  : > plan.ready
  [ "$(classify_plan plan.ready)" = ready ] \
    && ok "an empty plan -> ready" || no "an empty plan -> ready"
  echo 'some other nix message entirely' > plan.noise
  [ "$(classify_plan plan.noise)" = ready ] \
    && ok "an unparseable plan -> ready, never a refusal" \
    || no "an unparseable plan -> ready, never a refusal"
  cat > plan.small <<'P'
  these 2 derivations will be built:
    /nix/store/dddddddddddddddddddddddddddddddd-something-tiny.drv
  P
  [ "$(classify_plan plan.small)" = ready ] \
    && ok "two stray drvs are not a source build" || no "two stray drvs are not a source build"

  [ "$(plan_unpacked_mb '(1.87 GiB download, 5.61 GiB unpacked)')" -ge 5744 ] \
    && ok "unpacked GiB parses into MB" || no "unpacked GiB parses into MB"

  exit $fails
  EOF
  echo "--- probe functions, against a stubbed environment"
  bash t.sh

  # ---- the built app end to end, on its refusal paths ---------------------
  # Each exits before nix or qemu would run, so no network and no KVM are
  # needed here -- which is the point: these are the paths a sandbox CAN see.
  echo "--- the built app"
  app=${tryApp}/bin/nixarchy-try

  $app --help > help.out
  grep -q -- '--net' help.out && grep -q 'nix run github:olafkfreund/nixarchy#try' help.out
  echo "  ok      --help reads as instructions, not as a stack trace"

  if $app --frobnicate 2>msg; then exit 1; fi
  grep -q 'unknown option' msg && grep -q -- '--help' msg
  echo "  ok      an unknown flag refuses and points at --help"

  if $app --memory 2048 2>msg; then exit 1; fi
  grep -q '4096' msg
  echo "  ok      --memory below the floor refuses with the floor"

  if $app --boot 2>msg; then exit 1; fi
  grep -q 'no nixarchy-try.qcow2' msg
  echo "  ok      --boot with nothing installed says so"

  # A leftover disk -- a ctrl-C'd install, or simply a second run -- is
  # never silently reused as fresh, and never silently destroyed.
  mkdir leftover && cd leftover && touch nixarchy-try.qcow2
  if $app 2>msg; then exit 1; fi
  grep -q -- '--fresh' msg && grep -q -- '--boot' msg
  echo "  ok      a leftover disk refuses with both ways out"
  cd ..

  # No KVM plus a meminfo claiming 1 GB: the warning and the refusal both
  # fire from the real script, in order, before anything heavier runs. The
  # KVM device is stubbed away explicitly -- nix's sandbox passes the host's
  # real /dev/kvm through when it has one, so "the sandbox has no KVM" is
  # not a fact this check may lean on.
  mkdir starved && cd starved
  printf 'MemAvailable: %s kB\n' $((1024 * 1024)) > meminfo
  if TRY_KVM_DEV=/does/not/exist TRY_MEMINFO=$PWD/meminfo $app 2>msg; then exit 1; fi
  grep -q 'SLOWER' msg
  grep -q -- '--memory' msg
  echo "  ok      no KVM warns, 1 GB of RAM refuses, in one run"
  cd ..

  echo "the front door refuses in sentences, on every machine it was shown"
  touch $out
''
