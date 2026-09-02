# What `nixarchy dev init <preset>` writes into a fresh project's devenv.nix.
#
# The fourth catalogue, and the only one whose output is not a NixOS module:
# data/apps.nix installs, data/services.nix turns on, data/flatpaks.nix reaches
# what nixpkgs cannot. This one seeds a file in somebody's project directory,
# which is a file this repo will never see again -- it gets committed, shared
# with a team, and read by people who have never heard of nixarchy.
#
# That is the whole reason for the bar below.
#
# ## The bar: a preset is exactly a set of devenv option lines
#
# `lines` is pasted verbatim into the user's devenv.nix. What lands there has
# to be the same text devenv's own documentation and every forum answer shows,
# with no nixarchy vocabulary in it at all -- not a helper, not a `let`, not an
# import of anything we ship. Two things follow from that, and both are the
# point:
#
#   * The user can grow the file from devenv.sh's reference alone. They are not
#     reading our docs to edit their own project.
#   * Ecosystem drift is devenv's to absorb. When Node moves, `languages.javascript`
#     moves with it upstream and this file does not change. A template of
#     mkShell boilerplate would be ours to keep green forever; that is exactly
#     the trade #148 rejected plain `nix flake init -t` over.
#
# Anything that needs custom Nix does not qualify. That is what devenv's
# examples repository is for, and `nixarchy dev init` says so on the way out.
#
# ## What is checked, and what is not
#
# Nothing here validates itself: `lines` is a string, so a typo in an option
# name is a string with a typo in it and Nix will never say a word. What
# catches that is `nix run .#devenv-presets`, which scaffolds every preset and
# evaluates it against a real devenv. Read the header of that package in
# flake.nix before assuming this file is self-checking -- it is not, on
# purpose, because the checking half cannot be pure.
#
# ## Fields
#   label   Shown by `nixarchy dev init` with no argument.
#   lines   The devenv options, written flush left. Verbatim upstream syntax;
#           see the bar. pkgs/dev-init.nix indents them on the way in -- do not
#           indent them here, because Nix's '' strings strip the common leading
#           whitespace and the indentation would not survive to the file.
#   note    What the user gets and what it costs. Same job as the `note` in
#           data/services.nix: say the thing they would otherwise find out the
#           hard way, not what the language is.
#
# Option names below were read out of devenv's own src/modules/languages at
# df5c75a, not from memory -- `languages.javascript.npm.enable` and
# `languages.python.venv.enable` are both a level deeper than the guess.
{
  # react and node are the same three lines under two names, and that is
  # deliberate rather than an oversight waiting to be deduplicated. The name a
  # person types is the whole interface here: somebody starting a React app
  # types `react`, and answering "no such preset, did you mean node?" would be
  # a worse command for no gain. If the JavaScript lines ever diverge, they
  # diverge here without a caller changing.
  react = {
    label = "React";
    lines = ''
      languages.javascript = {
        enable = true;
        npm.enable = true;
      };
    '';
    note = "Node and npm, pinned to the project. Vite, Next and every other React toolchain install through npm from here.";
  };

  node = {
    label = "Node.js";
    lines = ''
      languages.javascript = {
        enable = true;
        npm.enable = true;
      };
    '';
    note = "Node and npm and nothing else. The starting point for anything JavaScript that is not React.";
  };

  # typescript on top of javascript, not instead of it: devenv's typescript
  # module adds the compiler and the language server and no runtime at all, so
  # a project with only `languages.typescript.enable` has tsc and no node to
  # run the output with. Checked against src/modules/languages/typescript.nix.
  typescript = {
    label = "TypeScript";
    lines = ''
      languages.javascript = {
        enable = true;
        npm.enable = true;
      };
      languages.typescript.enable = true;
    '';
    note = "Node, npm, tsc and the TypeScript language server. The javascript lines come too -- devenv's typescript module is the compiler, not a runtime.";
  };

  python = {
    label = "Python";
    lines = ''
      languages.python = {
        enable = true;
        venv.enable = true;
      };
    '';
    note = "Python with a virtualenv devenv creates and enters for you, so `pip install` lands in the project rather than in your home directory.";
  };

  go = {
    label = "Go";
    lines = ''
      languages.go.enable = true;
    '';
    note = "The Go toolchain plus gopls and delve, which devenv turns on with it.";
  };

  # No `channel` line. devenv defaults languages.rust.channel to "nixpkgs",
  # which is the toolchain the project's own nixpkgs already carries -- setting
  # it to "stable" instead would pull rust-overlay into every Rust project for
  # a version most people do not need, and it is one documented line for
  # someone who does.
  rust = {
    label = "Rust";
    lines = ''
      languages.rust.enable = true;
    '';
    note = "cargo, rustc, clippy and rust-analyzer from the project's nixpkgs. Add `languages.rust.channel = \"stable\";` for a rust-overlay toolchain instead.";
  };
}
