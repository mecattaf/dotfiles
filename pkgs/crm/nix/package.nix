{ lib, buildGoModule }:

buildGoModule rec {
  pname = "crm";
  version = "0.1.0";

  src = lib.cleanSource ../.;
  vendorHash = "sha256-uVwnNXmFo5euunwH0ULVMTeW5H/rn8TiKaHVPle9x0o=";

  subPackages = [ "cmd/crm" ];
  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    actual="$($out/bin/crm --version)"
    if [ "$actual" != "${version}" ]; then
      echo "crm --version returned '$actual'; expected '${version}'" >&2
      exit 1
    fi

    runHook postInstallCheck
  '';

  meta = {
    description = "Personal git-backed CRM for the command line";
    homepage = "https://github.com/mecattaf/crm";
    mainProgram = "crm";
    platforms = lib.platforms.linux;
  };
}
