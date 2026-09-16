{ symlinkJoin, runCommand, writeShellApplication, runtimeShell, bash, python3, sway, wayvnc,
  novnc, google-chrome, bibata-cursors, mesa, gcr, systemd, util-linux, coreutils }:
let
  python = python3.withPackages (p: [ p.aiohttp p.secretstorage ]);
  runtimeInputs = [ bash sway wayvnc google-chrome systemd util-linux coreutils ];
  viewer = runCommand "browser-desktop-novnc" { } ''
    mkdir -p "$out"
    for entry in ${novnc}/share/webapps/novnc/*; do
      ln -s "$entry" "$out/$(basename "$entry")"
    done
    rm "$out/vnc.html"
    cp ${novnc}/share/webapps/novnc/vnc.html "$out/vnc.html"
    substituteInPlace "$out/vnc.html" --replace-fail '</body>' '<script type="module" src="./desktop-controls.js"></script></body>'
    substituteInPlace "$out/vnc.html" \
      --replace-fail '<title>noVNC</title>' '<title>Browser desktop</title>' \
      --replace-fail 'type="image/x-icon" href="app/images/icons/novnc.ico"' 'type="image/svg+xml" href="desktop.svg"' \
      --replace-fail '</head>' '<link rel="stylesheet" href="desktop.css"></head>' \
      --replace-fail 'mandatory: mandatory } });' 'mandatory: mandatory } }).then(() => { if (!document.getElementById("noVNC_control_bar_anchor").classList.contains("noVNC_right")) UI.toggleControlbarSide(); });'
    sed -i '/rel="apple-touch-icon"/d' "$out/vnc.html"
    cp ${./desktop.css} "$out/desktop.css"
    cp ${./desktop.svg} "$out/desktop.svg"
    # A viewer must never request an exclusive VNC connection.
    rm -f "$out/mandatory.json"
    echo '{"shared":true}' > "$out/mandatory.json"
    cp ${./desktop-controls.js} "$out/desktop-controls.js"
    cp ${google-chrome}/share/icons/hicolor/48x48/apps/google-chrome.png "$out/chrome.png"
  '';
  environment = ''
    export XCURSOR_THEME=Bibata-Modern-Amber
    export XCURSOR_SIZE=24
    export XCURSOR_PATH=${bibata-cursors}/share/icons
    export SHELL=${runtimeShell}
    export BROWSER_DESKTOP_ASSETS=${./.}
    export BROWSER_DESKTOP_PYTHON=${python}/bin/python
    export BROWSER_DESKTOP_CHROME=${google-chrome}/bin/google-chrome-stable
    export BROWSER_DESKTOP_PROMPTER=${gcr}/libexec/gcr-prompter
    export __EGL_VENDOR_LIBRARY_FILENAMES=${mesa}/share/glvnd/egl_vendor.d/50_mesa.json
    export LIBGL_DRIVERS_PATH=${mesa}/lib/dri
    export GBM_BACKENDS_PATH=${mesa}/lib/gbm
  '';
  desktop = writeShellApplication {
    name = "browser-desktop";
    inherit runtimeInputs;
    text = environment + builtins.readFile ./desktop.sh;
  };
  menu = writeShellApplication {
    name = "browser-desktop-menu";
    inherit runtimeInputs;
    text = environment + ''
      exec "$BROWSER_DESKTOP_PYTHON" "$BROWSER_DESKTOP_ASSETS/menu.py" "$@"
    '';
  };
in symlinkJoin {
  name = "browser-desktop";
  paths = [ desktop menu ];
  passthru = {
    inherit python;
    webRoot = viewer;
    assets = ./.;
    tests.contract = runCommand "browser-desktop-contract" { } ''
      ${python}/bin/python -c 'import secretstorage'
      PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=${./.} ${python}/bin/python ${./test_desktop.py}
      touch "$out"
    '';
  };
  meta.description = "Shared headless Sway and WayVNC browser desktop behind stock noVNC, with a Chrome profile menu";
}
