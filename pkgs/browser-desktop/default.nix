{ symlinkJoin, runCommand, writeShellApplication, runtimeShell, bash, python3, fara-cli, sway, wayvnc,
  novnc, google-chrome, mesa, gcr, jq, curl, systemd, util-linux, coreutils }:
let
  python = python3.withPackages (p: [ p.aiohttp p.playwright p.pillow p.secretstorage (p.toPythonModule fara-cli) ]);
  runtimeInputs = [ bash sway wayvnc google-chrome jq curl systemd util-linux coreutils ];
  viewer = runCommand "fara-novnc" { } ''
    mkdir -p "$out"
    for entry in ${novnc}/share/webapps/novnc/*; do
      ln -s "$entry" "$out/$(basename "$entry")"
    done
    rm "$out/vnc.html"
    cp ${novnc}/share/webapps/novnc/vnc.html "$out/vnc.html"
    substituteInPlace "$out/vnc.html" --replace-fail '</body>' '<script type="module" src="./desktop-controls.js"></script></body>'
    cp ${./desktop-controls.js} "$out/desktop-controls.js"
  '';
  environment = ''
    export SHELL=${runtimeShell}
    export FARA_BROWSER_ASSETS=${./.}
    export FARA_BROWSER_PYTHON=${python}/bin/python
    export FARA_BROWSER_CHROME=${google-chrome}/bin/google-chrome-stable
    export FARA_BROWSER_PROMPTER=${gcr}/libexec/gcr-prompter
    export __EGL_VENDOR_LIBRARY_FILENAMES=${mesa}/share/glvnd/egl_vendor.d/50_mesa.json
    export LIBGL_DRIVERS_PATH=${mesa}/lib/dri
    export GBM_BACKENDS_PATH=${mesa}/lib/gbm
  '';
  desktop = writeShellApplication {
    name = "browser-desktop";
    inherit runtimeInputs;
    text = environment + builtins.readFile ./desktop.sh;
  };
  cli = writeShellApplication {
    name = "fara-browser";
    inherit runtimeInputs;
    text = environment + ''
      exec "$FARA_BROWSER_PYTHON" "$FARA_BROWSER_ASSETS/harness.py" "$@"
    '';
  };
in symlinkJoin {
  name = "browser-desktop";
  paths = [ desktop cli ];
  passthru = {
    inherit python;
    webRoot = viewer;
    assets = ./.;
    tests.contract = runCommand "browser-desktop-contract" { } ''
      ${python}/bin/python -c 'from fara.agents.fara.fara15_agent import Fara15Agent; import secretstorage'
      PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=${./.} ${python}/bin/python ${./test_harness.py}
      touch "$out"
    '';
  };
  meta.description = "Sway and WayVNC desktop with Microsoft's FARA harness adapted to noVNC";
}
