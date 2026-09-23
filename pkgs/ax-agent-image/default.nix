{
  lib,
  callPackage,
  dockerTools,
  runCommand,
  writeTextDir,
  buildEnv,
  bashInteractive,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  gawk,
  curl,
  jq,
  python3,
  cacert,
  gnutar,
  gzip,
  git,
  shellcheck,
  # The patched ax (sandbox-class + P1): its ax-task-runner is PID 1.
  ax,
  # pi from llm-agents. Halogen only on day one; no claude-code in this image
  # until Tom rules on Claude credentials in sandboxes (DESIGN.md section 11).
  pi,
  # Test-only variants (tests/ax-fleet): extra store paths linked into /bin and
  # a name suffix. The fleet image passes neither: pi only, no claude-code.
  extraPaths ? [ ],
  variant ? "",
}:
# The ax Task image for the fleet (DESIGN.md section 10.2): `ax-agent`.
#
# Substrate starts /usr/local/bin/ax-task-runner (ax's DefaultGuestCommand) as
# PID 1; the runner sets up /workspace and runs the Task's spec.command, here
# `ax-agent <mode>`. Output: an OCI layout plus `digest`, seeded into the NAS
# registry as ax/ax-agent and named by Tasks as
# localhost:5000/ax/ax-agent@sha256:<digest> (atelet rewrites localhost:5000).
#
# No secret is baked in: pi-models.json names Halogen, which has no auth, and
# the endpoint is filled at run time from $HALOGEN_URL (default the worker,
# http://10.42.0.5:8731), so one image digest serves every host.
let
  ociLayout = callPackage ../ax/oci-layout.nix { };

  share = runCommand "ax-agent-share" { } ''
    mkdir -p $out/share/ax-agent
    cp ${./pi-models.json} $out/share/ax-agent/pi-models.json
    cp ${./validate.py} $out/share/ax-agent/validate.py
  '';

  ax-agent = runCommand "ax-agent" { nativeBuildInputs = [ shellcheck ]; } ''
    mkdir -p $out/bin
    substitute ${./ax-agent.sh} $out/bin/ax-agent \
      --replace-fail '@share@' '${share}/share/ax-agent' \
      --replace-fail '#!/usr/bin/env bash' '#!${bashInteractive}/bin/bash'
    chmod +x $out/bin/ax-agent
    shellcheck -S warning $out/bin/ax-agent
  '';

  # The runner at the path Substrate's template names.
  # pi with its ELF program headers in the order the ELF spec asks for. pi
  # 0.85.1's bun binary lists PT_LOAD out of p_vaddr order; Linux runs it, but
  # gVisor's loader refuses it (ENOEXEC, exit 126 inside the sandbox, MEASURED
  # in the ax-fleet VM test, INTEGRATE.md). Only table entries move; segments,
  # addresses and bytes stay. The name keeps pi's, so the store path length is
  # unchanged; only the text wrapper in bin/ is repointed.
  piSandbox = runCommand pi.name { nativeBuildInputs = [ python3 ]; } ''
    cp -a ${pi} $out
    chmod -R u+w $out
    find $out -type f -print0 | while IFS= read -r -d "" f; do
      if [ "$(head -c 4 "$f" | od -An -c | tr -d ' ')" = '177ELF' ]; then
        python3 ${./elf-sort-load.py} "$f"
      fi
    done
    for f in $out/bin/*; do
      substituteInPlace "$f" --replace-quiet ${pi} $out
    done
    chmod -R a-w $out
  '';

  runner = runCommand "ax-task-runner-usr-local" { } ''
    mkdir -p $out/usr/local/bin
    ln -s ${ax}/bin/ax-task-runner $out/usr/local/bin/ax-task-runner
    ln -s ${ax-agent}/bin/ax-agent $out/usr/local/bin/ax-agent
  '';

  etc = [
    (writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/bash
      agent:x:1000:1000:agent:/workspace/.home:/bin/bash
      nobody:x:65534:65534:nobody:/var/empty:/bin/false
    '')
    (writeTextDir "etc/group" ''
      root:x:0:
      agent:x:1000:
      nobody:x:65534:
    '')
  ];

  env = buildEnv {
    name = "ax-agent-env";
    paths = [
      bashInteractive
      coreutils
      findutils
      gnugrep
      gnused
      gawk
      curl
      jq
      python3
      cacert
      gnutar
      gzip
      git
      piSandbox
      ax-agent
    ]
    ++ extraPaths;
    pathsToLink = [
      "/bin"
      "/etc/ssl"
      "/share/ax-agent"
    ];
  };

  image = dockerTools.buildLayeredImage {
    name = "ax/ax-agent${variant}";
    tag = "v${ax.version}-p1";
    contents = [
      env
      runner
      share
    ]
    ++ etc;
    extraCommands = ''
      mkdir -p tmp workspace usr/bin etc/ax-agent/pi
      chmod 1777 tmp
      ln -s ${coreutils}/bin/env usr/bin/env
      cp ${./pi-models.json} etc/ax-agent/pi/models.json
    '';
    config = {
      Cmd = [ "/usr/local/bin/ax-task-runner" ];
      WorkingDir = "/workspace";
      Env = [
        "PATH=/usr/local/bin:/bin"
        "HOME=/workspace/.home"
        "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
        "HALOGEN_URL=http://10.42.0.5:8731"
      ];
    };
  };
in
(ociLayout {
  name = "ax/ax-agent${variant}";
  tag = "v${ax.version}-p1";
  inherit image;
}).overrideAttrs
  (old: {
    passthru = old.passthru // {
      inherit ax-agent image piSandbox;
    };
    meta = {
      description = "ax Task image for the fleet: ax-task-runner, pi, and the ax-agent adapter (OCI layout)";
      platforms = [ "x86_64-linux" ];
      license = lib.licenses.asl20;
    };
  })
