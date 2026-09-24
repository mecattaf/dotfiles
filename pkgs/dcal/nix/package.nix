{
  lib,
  buildGoModule,
  systemd,
}:

buildGoModule rec {
  pname = "dcal";
  version = "0.3.0";

  src = lib.cleanSource ../.;
  vendorHash = "sha256-ROvf5F6tkAr+QXVHaIaezizFWqYdP1aGyS7Jjb8r5TE=";

  subPackages = [ "cmd/dcal" ];
  env.CGO_ENABLED = 0;
  nativeCheckInputs = [ systemd ];

  # The vendored CLI has a `version` command but does not wire its version into
  # Cobra's standard flag. Keep that build metadata local to this derivation.
  postPatch = ''
    substituteInPlace cmd/dcal/commands.go \
      --replace-fail \
        'var rootCmd = &cobra.Command{' \
        $'var rootCmd = &cobra.Command{\n\tVersion: Version,'
  '';

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    actual="$($out/bin/dcal --version)"
    if [ "$actual" != "dcal version ${version}" ]; then
      echo "dcal --version returned '$actual'; expected 'dcal version ${version}'" >&2
      exit 1
    fi

    runHook postInstallCheck
  '';

  # systemd-analyze, call-diarize, and crm are intentionally resolved from PATH
  # at runtime so dcal does not pull those optional workflows into its closure.
  # crm is optional: dotfiles no longer ships it (issue #452, pull request #456).
  # dcal takes it from DCAL_CRM_BIN or from PATH, and refuses by name when
  # neither resolves. The successor is github.com/mecattaf/crm, whose
  # scripts/crm-cli.sh wrapper is what DCAL_CRM_BIN should point at.
  meta = {
    description = "Headless CLI for local and synced calendars";
    homepage = "https://github.com/AvengeMedia/dankcalendar";
    license = lib.licenses.mit;
    mainProgram = "dcal";
    platforms = lib.platforms.linux;
  };
}
