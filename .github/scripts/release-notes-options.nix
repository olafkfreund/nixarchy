# The option walk .github/scripts/release-notes.sh applies to
# options.programs.nixarchy. Its own file so checks.release-notes can run it
# against the real option set, which the script's fixture cannot.
o:
let
  isOpt = v: (v._type or "") == "option";
  go =
    path: v:
    if isOpt v then
      # defaultText first, and not only for display: tryEval catches throw
      # and assert but NOT a missing attribute, so a default that reads
      # pkgs.config.<key> aborts the whole walk (v4.0.3-2 shipped no notes).
      (
        let
          d = builtins.tryEval (if v ? default then builtins.toJSON v.default else "");
        in
        {
          "${path}" =
            if v ? defaultText then
              (v.defaultText.text or (builtins.toString v.defaultText))
            else if !(v ? default) then
              "(no default)"
            else if d.success then
              d.value
            else
              "(not representable)";
        }
      )
    else if builtins.isAttrs v then
      builtins.foldl' (a: n: a // go (path + "." + n) v.${n}) { } (
        builtins.filter (n: builtins.substring 0 1 n != "_") (builtins.attrNames v)
      )
    else
      { };
in
go "programs.nixarchy" o
