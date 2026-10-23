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
  expectedPartition ? "2",
  expectedPartLabel ? "disk-primary-home",
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
      [
        "@expectedDisk@"
        "@expectedSerial@"
        "@expectedLabel@"
        "@expectedPartition@"
        "@expectedPartLabel@"
        "@hddUuid@"
        "@excludes@"
      ]
      (map lib.escapeShellArg [
        expectedDisk
        expectedSerial
        expectedLabel
        expectedPartition
        expectedPartLabel
        hddUuid
        "${./home-excludes}"
      ])
      (builtins.readFile ./migrate.sh);
}
