{ pkgs, ... }:
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-chrome-policy"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    package = "${shipped}/share/omarchy";
    policy = builtins.toJSON (shipped.passthru.chromeExtensionsPolicy or null);
  }
  ''
        case "$policy" in
          false)
            echo 'not edge: nothing to check'
            ;;
          true)
            python3 -I - "$package" <<'PY' || exit 1
    import json
    import sys
    import xml.etree.ElementTree as ET
    from pathlib import Path


    def require(condition, reason):
        if not condition:
            raise ValueError(reason)


    try:
        root = Path(sys.argv[1]) / "default/chromium"
        policy = root / "policies/omarchy.json"
        extensions = root / "policies/chrome-extensions.json"
        updates = root / "crx/updates.xml"
        for path in (policy, extensions, updates):
            require("/usr/share" not in path.read_text(), f"{path.name} contains /usr/share")
        json.loads(policy.read_text())
        settings = json.loads(extensions.read_text()).get("ExtensionSettings")
        require(isinstance(settings, dict) and settings, "ExtensionSettings is empty or invalid")
        apps = ET.parse(updates).getroot().findall(".//{*}app")
        require(apps, "updates.xml has no apps")
        appids = set()
        for app in apps:
            appid = app.get("appid")
            require(appid, "updates.xml app has no appid")
            appids.add(appid)
            updatecheck = app.find("{*}updatecheck")
            require(updatecheck is not None, f"{appid} has no updatecheck")
            codebase = updatecheck.get("codebase", "")
            require(codebase.startswith("file:///"), f"{appid} codebase is not a local file URL")
            require(Path(codebase[7:]).is_file(), f"{appid} codebase file is missing")
        for appid, setting in settings.items():
            require(appid in appids, f"{appid} is missing from updates.xml")
            require(isinstance(setting, dict), f"{appid} settings are invalid")
            require(setting.get("update_url") == updates.as_uri(), f"{appid} update_url is not this package's updates.xml")
        print(f"chrome policy: {len(settings)} extensions, {len(apps)} apps")
    except Exception as error:
        print(f"FAILED {error}", file=sys.stderr)
        sys.exit(1)
    PY
            ;;
          *)
            echo 'FAILED chromeExtensionsPolicy must be a boolean' >&2
            exit 1
            ;;
        esac
        touch "$out"
  ''
