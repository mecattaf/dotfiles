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
  expectedLabel,
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
  text =
    builtins.replaceStrings
      [ "@expectedDisk@" "@expectedSerial@" "@expectedLabel@" "@hddUuid@" "@excludes@" ]
      (map lib.escapeShellArg [
        expectedDisk
        expectedSerial
        expectedLabel
        hddUuid
        "${./home-excludes}"
      ])
      (builtins.readFile ./migrate.sh);
}
