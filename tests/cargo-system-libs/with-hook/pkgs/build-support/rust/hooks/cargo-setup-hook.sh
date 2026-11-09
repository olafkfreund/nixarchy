# fixture: the hook as nixpkgs ships it once it links system libraries
cargoUseSystemLibs() {
  :
}
preConfigureHooks+=(cargoUseSystemLibs)
