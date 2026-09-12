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
# ## A preset may not set `packages`
#
# Not a style rule -- a hard one, and it is the scaffold's doing rather than
# devenv's. `devenv init` writes `packages = [ pkgs.git ];` into the file
# these lines are spliced into, and `lines` lands in the SAME attrset
# literal. A second `packages = ...` is therefore not a module merge that
# `lib.mkAfter` could order; it is
#
#   error: attribute 'packages' already defined at devenv.nix:8:3
#
# with no mention of a preset anywhere in it. The `ml` preset below was
# written with `packages = [ pkgs.uv ];` and died exactly this way. Reach for
# the `languages.*` option that installs the tool instead -- which is the
# better line regardless, since it is the one devenv's own documentation
# shows.
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

  # uv.enable, not uv.sync.enable: sync runs `uv sync` on entering the shell,
  # which wants a pyproject.toml a freshly scaffolded project does not have.
  # With uv.enable devenv creates the venv through uv and puts uv itself on
  # the project's PATH; `uv sync` is one documented line for a project that
  # grows a pyproject.toml. Checked against src/modules/languages/python.
  python = {
    label = "Python";
    lines = ''
      languages.python = {
        enable = true;
        venv.enable = true;
        uv.enable = true;
      };
    '';
    note = "Python with uv and a virtualenv devenv creates and enters for you, so `uv pip install` and `pip install` land in the project rather than in your home directory.";
  };

  # The two machine-learning presets, and the reason they look nothing like a
  # nixpkgs answer to the same question.
  #
  # ## `ml`: uv's own CPython, deliberately
  #
  # The wheels an ML project actually installs -- torch, jax, onnxruntime --
  # ship their own CUDA or ROCm runtime INSIDE the wheel. The one thing they
  # cannot bundle is the driver, and on NixOS `libcuda.so.1` lives in
  # /run/opengl-driver/lib, which is on no default search path. That is the
  # whole of the machine-specific problem; nixpkgs' own cudaPackages solve a
  # different one (building CUDA software from source) at the cost of an
  # unfree rebuild of the world.
  #
  # And the correction that belongs with it, because it is the most common
  # "I did what the wiki said and it still fails": **nix-ld does not help a
  # nixpkgs Python.** nix-ld works by supplying a loader at the path a foreign
  # binary expects one, and reading NIX_LD/NIX_LD_LIBRARY_PATH from the
  # environment. A python3 out of nixpkgs is patched to use Nix's own loader
  # and never consults either variable. Only an UNPATCHED interpreter -- the
  # CPython uv downloads for itself -- is in a position to read them. Hence
  # `UV_PYTHON_PREFERENCE = "only-managed"` below, and no
  # `languages.python.enable` at all: this preset is the case where uv's
  # interpreter is the point, not an implementation detail.
  #
  # Not poetry2nix. It is legacy, and its own README points at uv2nix, which
  # self-describes as experimental with breaking API changes -- fine for a
  # template somebody opts into with their eyes open, not for the preset a
  # first ML project gets scaffolded from.
  ml = {
    label = "Machine learning (uv, CUDA/ROCm)";
    lines = ''
      languages.python = {
        enable = true;
        uv.enable = true;
      };

      # The line that makes this preset different from `python`. uv will
      # otherwise reuse the nixpkgs interpreter the line above puts on PATH,
      # and a nixpkgs python3 is patched to use Nix's own loader -- it never
      # reads NIX_LD, so nix-ld cannot help a wheel it imports. uv's own
      # downloaded CPython is an ordinary Linux binary, and is the one
      # interpreter here that can.
      env.UV_PYTHON_PREFERENCE = "only-managed";

      # The driver is the one piece no wheel can ship. On NixOS it is here.
      env.LD_LIBRARY_PATH = "/run/opengl-driver/lib:" + lib.makeLibraryPath [
        pkgs.stdenv.cc.cc.lib
        pkgs.zlib
      ];
    '';
    note = "uv, with the driver on LD_LIBRARY_PATH so PyPI's CUDA and ROCm wheels load. Start with `uv venv` then `uv pip install torch` (CUDA) or `uv pip install torch --index-url https://download.pytorch.org/whl/rocm6.3` (ROCm). Deliberately uses uv's own Python: a nixpkgs python3 ignores nix-ld entirely.";
  };

  # ## `jupyter`: an ordinary devshell, which is the sharp part
  #
  # Search for Jupyter on Nix and the first answer is jupyenv (formerly
  # jupyterWith). It is unmaintained and does not track current nixpkgs, so
  # the evening goes: find it, fight its flake inputs, fail, conclude that
  # Jupyter on NixOS is hard. It is not hard. `python3.withPackages` with
  # jupyterlab in it is the entire answer, and `languages.python.package` is
  # where devenv takes one.
  #
  # `processes.jupyter` rather than an `enterShell` that launches it: devenv's
  # process manager is what upstream's own documentation reaches for, it means
  # `devenv up` starts the server and `cd` does not, and it is one more option
  # the user can read about at devenv.sh rather than here.
  jupyter = {
    label = "Jupyter";
    lines = ''
      languages.python = {
        enable = true;
        package = pkgs.python3.withPackages (ps: [
          ps.jupyterlab
          ps.ipykernel
          ps.ipywidgets
          ps.numpy
          ps.pandas
          ps.matplotlib
        ]);
      };

      processes.jupyter.exec = "jupyter lab --no-browser";
    '';
    note = "JupyterLab from nixpkgs, pinned by devenv.lock -- `devenv up` starts the server. Not jupyenv (formerly jupyterWith): that project is unmaintained and does not track current nixpkgs, and this is the working path it is usually mistaken for.";
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
