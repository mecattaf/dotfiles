{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  libdrm,
}:

rustPlatform.buildRustPackage rec {
  pname = "amdtop";
  version = "0.2.5";

  src = fetchFromGitHub {
    owner = "lhl";
    repo = "amdtop";
    rev = "v${version}";
    hash = "sha256-31J4RC3npANffLXKQg7gjFe/XLVfM2NpV+t9+x7CpAU=";
  };

  cargoHash = "sha256-fgFiUmo4aRky91DHM7iR5UTL6tTcGAb5fBYGa8TpAMI=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libdrm ];

  meta = {
    description = "System monitor for AMD GPUs, CPUs, and XDNA NPUs";
    homepage = "https://github.com/lhl/amdtop";
    changelog = "https://github.com/lhl/amdtop/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "amdtop";
    platforms = lib.platforms.linux;
  };
}
