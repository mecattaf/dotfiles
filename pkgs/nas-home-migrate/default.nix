{
  writeShellApplication,
  lib,
  coreutils,
  util-linux,
  rsync,
  openssh,
  postgresql,
  sqlite,
  gnutar,
  expectedDisk,
  expectedSerial,
  hddUuid,
}:
writeShellApplication {
  name = "nas-home-migrate";
  runtimeInputs = [
    coreutils
    util-linux
    rsync
    openssh
    postgresql
    sqlite
    gnutar
  ];
  text = builtins.replaceStrings [ "@expectedDisk@" "@expectedSerial@" "@hddUuid@" "@excludes@" ] (map
    lib.escapeShellArg
    [
      expectedDisk
      expectedSerial
      hddUuid
      "${./home-excludes}"
    ]
  ) (builtins.readFile ./migrate.sh);
}
