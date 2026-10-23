{
  lib,
  rdma-core,
  donnerkeule,
}:
let
  patchRoot = donnerkeule + "/packaging/rdma-core-patches";
  series = lib.filter (name: name != "" && !(lib.hasPrefix "#" name)) (
    lib.splitString "\n" (builtins.readFile (patchRoot + "/series"))
  );
in
rdma-core.overrideAttrs (old: {
  pname = "rdma-core-usb4";
  patches = (old.patches or [ ]) ++ map (name: patchRoot + "/${name}") series;
  # Keep the driver's kernel names if these udev rules are ever installed.
  postPatch = (old.postPatch or "") + ''
    substituteInPlace kernel-boot/rdma-persistent-naming.rules \
      --replace-fail 'SUBSYSTEM=="infiniband", PROGRAM="rdma_rename' \
        'SUBSYSTEM=="infiniband", KERNEL!="usb4_rdma*", PROGRAM="rdma_rename'
  '';
  passthru = (old.passthru or { }) // {
    donnerkeuleRevision = donnerkeule.rev;
  };
})
