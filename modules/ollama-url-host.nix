{ lib }:
host:
let
  normalized =
    if
      builtins.elem host [
        "0.0.0.0"
        "[::]"
        "::"
      ]
    then
      "127.0.0.1"
    else
      host;
in
if lib.hasInfix ":" normalized && !(lib.hasPrefix "[" normalized) then
  "[${normalized}]"
else
  normalized
