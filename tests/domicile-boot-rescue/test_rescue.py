#!/usr/bin/env python3
"""Failure fixtures and filesystem-phase tests. Always run with runtime-test."""
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import rescue
import install
from preview import preview


def fixture():
    booted = "/nix/store/"+"a"*32+"-nixos-system-client"
    kernel = "/nix/store/"+"b"*32+"-linux-7.2.10/bzImage"
    initrd = "/nix/store/"+"c"*32+"-initrd-linux-7.2.10/initrd"
    params = ["root=fstab", "loglevel=4"]
    h = bytearray(0x210)
    h[:2] = b"MZ"
    h[0x202:0x206] = b"HdrS"
    def a(path, header, mode=0o444):
        return dict(path=path, magic_hex=header[:6].hex(), linux_hdrs_hex=header[0x202:0x206].hex(), mode=mode, size=4096, sha256="1"*64)
    text = "\n".join(["title NixOS", "sort-key nixos", "version Generation 9 NixOS",
                      "machine-id "+"d"*32, "linux /EFI/nixos/current-kernel.efi",
                      "initrd /EFI/nixos/current-initrd.efi", "options init=/current/init root=fstab", ""])
    return dict(schema=1, observed_at="2026-11-04T12:00:00Z", hostname="client", kernel="7.2.10",
        booted=booted, current="/nix/store/"+"e"*32+"-nixos-system-client", machine_id="d"*32, boot_id="fixture-boot",
        bootspec={"org.nixos.bootspec.v1":dict(init=booted+"/init", initrd=initrd,
                  kernel=kernel, kernelParams=params, system="x86_64-linux", toplevel=booted)},
        boot_json_sha256="2"*64,
        assets=dict(kernel=a(kernel,bytes(h)), initrd=a(initrd,b"\x28\xb5\x2f\xfd"),
                    init=a(booted+"/init",b"\x7fELF",0o555)),
        kernel_release_string="7.2.10 (fixture)", module_versions=["7.2.10"],
        kernel_params=" ".join(params), cmdline="initrd=\\EFI\\nixos\\"+"c"*32+
           "-initrd-linux-7.2.10-initrd.efi init="+booted+"/init "+" ".join(params),
        kernel_type="pe", bootctl_version="systemd 261 (261)", bootctl_status="systemd-boot 261",
        secure_boot="0600000000", esp_path="/boot", boot_path="/boot",
        mount=[dict(target="/boot",source="/dev/fixture",fstype="vfat",options="rw,relatime")],
        esp=dict(available=100000000,block_size=4096), loader_conf="timeout 5\n",
        selectors={}, selector_values={}, esp_files={}, entries={"nixos-nine.conf":text},
        boot_entries=[dict(type="type1",id="nixos-nine.conf",sortKey="nixos",
                          version="Generation 9 NixOS",isDefault=True)],
        closure=dict(count=3,sha256="3"*64,missing=[],includes_sources=True),
        installed_sources={k:dict(path="/nix/store/source",sha256="4"*64,
                                 markers={"layout":True,"cleanup":True}) for k in ("booted","current")},
        collisions=[])


class Validation(unittest.TestCase):
    def test_booted_differs_from_installed_and_history_is_not_rescue(self):
        s=fixture()
        s["boot_entries"].append(dict(id="old-selected.conf",type="loader",isSelected=True))
        p=rescue.build_plan(s)
        self.assertIn(s["booted"]+"/init",p["entry_text"])
        self.assertNotIn(s["current"],p["entry_text"])
        self.assertFalse(p["mutations_executed"])

    def test_failure_cases(self):
        cases = [
            ("wrong host", lambda s:s.update(hostname="nas")),
            ("current used as booted",lambda s:s["bootspec"]["org.nixos.bootspec.v1"].update(toplevel=s["current"])),
            ("wrong init",lambda s:s["bootspec"]["org.nixos.bootspec.v1"].update(init=s["current"]+"/init")),
            ("wrong kernel source",lambda s:s["assets"]["kernel"].update(path="/nix/store/"+"f"*32+"-linux/bzImage")),
            ("not EFI Linux",lambda s:s["assets"]["kernel"].update(magic_hex=b"MZ".hex(), linux_hdrs_hex="")),
            ("wrong kernel version",lambda s:s.update(kernel_release_string="7.3.0 fixture")),
            ("wrong modules",lambda s:s.update(module_versions=["7.3.0"])),
            ("non executable init",lambda s:s["assets"]["init"].update(mode=0o444)),
            ("writable kernel",lambda s:s["assets"]["kernel"].update(mode=0o644)),
            ("bad initrd",lambda s:s["assets"]["initrd"].update(magic_hex="0000")),
            ("missing store path",lambda s:s["closure"].update(missing=["/nix/store/absent"])),
            ("source not referenced",lambda s:s["closure"].update(includes_sources=False)),
            ("cmdline changed",lambda s:s.update(cmdline=s["cmdline"]+" debug")),
            ("wrong EFI initrd",lambda s:s.update(cmdline=s["cmdline"].replace("-initrd.efi","-other.efi"))),
            ("duplicate EFI initrd",lambda s:s.update(cmdline=s["cmdline"]+" initrd=/extra")),
            ("kernel params changed",lambda s:s.update(kernel_params="root=wrong")),
            ("initrd secrets",lambda s:s["bootspec"]["org.nixos.bootspec.v1"].update(initrdSecrets="/secret")),
            ("extra initrd",lambda s:s["bootspec"].update({"org.nixos.extra-initrd.v1":{"paths":["/extra"]}})),
            ("different cleanup",lambda s:s["installed_sources"]["current"]["markers"].update(cleanup=False)),
            ("XBOOTLDR",lambda s:s.update(boot_path="/efi")),
            ("Secure Boot",lambda s:s.update(secure_boot="0600000001")),
            ("ESP read only",lambda s:s["mount"][0].update(options="ro")),
            ("ESP low space",lambda s:s["esp"].update(available=1024)),
            ("destination collision",lambda s:s.update(collisions=["/boot/existing"])),
            ("default only history",lambda s:s["boot_entries"][0].update(id="old-absent.conf")),
            ("default broad glob",lambda s:s.update(loader_conf="default *\n")),
            ("oneshot may select rescue",lambda s:s["selector_values"].update(LoaderEntryOneShot="domicile-*")),
            ("saved selector",lambda s:s["selector_values"].update(LoaderEntryDefault="@saved")),
            ("unexpected version",lambda s:s["boot_entries"][0].update(version="0")),
            ("injected option",lambda s:s["bootspec"]["org.nixos.bootspec.v1"]["kernelParams"].append("x\nlinux /evil")),
        ]
        for label, mutate in cases:
            with self.subTest(label=label):
                s=fixture()
                mutate(s)
                with self.assertRaises(rescue.Refusal):
                    rescue.build_plan(s)

    def test_stale_state_and_plan_tampering(self):
        s=fixture()
        p=rescue.build_plan(s)
        install.preflight(p,copy.deepcopy(s))
        for key in ("boot_id","selectors","entries","current","boot_json_sha256"):
            with self.subTest(key=key):
                changed=copy.deepcopy(s)
                if isinstance(changed[key],dict):
                    changed[key]["unexpected"]="changed"
                else:
                    changed[key]="changed"
                with self.assertRaises((rescue.Refusal,TypeError)):
                    install.preflight(p,changed)
        p["target"]["gcroot"]="/unreviewed"
        with self.assertRaises(rescue.Refusal):
            install.preflight(p,s)

    def test_real_systemd_boot_order_and_numeric_version_regression(self):
        p=rescue.build_plan(fixture())
        result=preview(p)
        self.assertEqual(result["status"],"PASS_VISIBLE_NOT_DEFAULT_IN_STRIX_FIXTURE")
        p["entry_text"]=p["entry_text"].replace("version Generation 0 rescue","version 0")
        with self.assertRaisesRegex(rescue.Refusal,"default"):
            preview(p)

    def test_rendered_installer_is_standalone_and_requires_authorization(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest=Path(tmp)/"artifacts"
            rescue.render(fixture(),dest)
            script=dest/"install-reviewed.py"
            compile(script.read_text(),str(script),"exec")
            p=subprocess.run(["python3",str(script)],capture_output=True,text=True)
            self.assertEqual(p.returncode,2)
            self.assertIn("--authorize-install",p.stderr)
            self.assertNotIn("from rescue import",script.read_text())


class InstallPhases(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.esp=self.root/"boot"
        self.roots=self.root/"gcroots"
        self.roots.mkdir()
        (self.esp/"loader/entries").mkdir(parents=True)
        (self.esp/"EFI").mkdir()
        self.p=rescue.build_plan(fixture())
        self.p["target"]["entry"]=str(self.esp/"loader/entries"/self.p["target"]["entry_id"])
        self.p["target"]["gcroot"]=str(self.roots/"rescue")
        self.src=self.root/"source"
        self.src.mkdir()
        for k in ("kernel","initrd"):
            f=self.src/k
            f.write_bytes((k*100).encode())
            a=self.p["snapshot"]["assets"][k]
            a.update(path=str(f),sha256=rescue.hash_file(f),size=f.stat().st_size)
        (self.esp/"loader/loader.conf").write_text(self.p["snapshot"]["loader_conf"])
        for name,text in self.p["snapshot"]["entries"].items():
            (self.esp/"loader/entries"/name).write_text(text)
        self.menu=copy.deepcopy(self.p["snapshot"]["boot_entries"])
        self.menu.append(dict(type="type1",id=self.p["target"]["entry_id"],
            path=self.p["target"]["entry"],isDefault=False,isSelected=False,
            linux=self.p["target"]["kernel"],initrd=[self.p["target"]["initrd"]],
            options="init="+self.p["snapshot"]["booted"]+"/init root=fstab loglevel=4"))
        for target,value in (("ESP",self.esp),("GCROOTS",self.roots)):
            patcher=patch.object(install,target,value)
            patcher.start()
            self.addCleanup(patcher.stop)
        for target,value in (("observe",lambda:self.p["snapshot"]),("preflight",lambda p,s:None),
                             ("selectors",lambda:{}),("run",lambda *args:json.dumps(self.menu))):
            patcher=patch.object(install,target,value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_full_fixture_install_preserves_default_and_existing_files(self):
        receipt=install.apply(self.p)
        self.assertEqual(receipt["status"],"INSTALLED_VERIFIED_NOT_DEFAULT")
        self.assertEqual(Path(self.p["target"]["entry"]).read_text(),self.p["entry_text"])
        self.assertEqual(os.readlink(self.p["target"]["gcroot"]),self.p["snapshot"]["booted"])

    def test_preflight_refusal_does_not_write(self):
        with patch.object(install,"preflight",side_effect=rescue.Refusal("stale")):
            with self.assertRaises(rescue.Refusal):
                install.apply(self.p)
        self.assertEqual(list(self.roots.iterdir()),[])
        self.assertFalse((self.esp/"EFI/domicile-rescue").exists())

    def test_bad_copy_keeps_gc_protection_without_publishing(self):
        self.p["snapshot"]["assets"]["initrd"]["sha256"]="0"*64
        with self.assertRaisesRegex(rescue.Refusal,"verification"):
            install.apply(self.p)
        self.assertTrue(Path(self.p["target"]["gcroot"]).is_symlink())
        self.assertFalse(Path(self.p["target"]["entry"]).exists())
        self.assertGreater(len(list((self.esp/"EFI/domicile-rescue").iterdir())),0)

    def test_postverification_failure_withdraws_only_new_entry(self):
        self.menu[-1]["isDefault"]=True
        with self.assertRaisesRegex(rescue.Refusal,"default"):
            install.apply(self.p)
        self.assertFalse(Path(self.p["target"]["entry"]).exists())
        self.assertTrue(Path(self.p["target"]["gcroot"]).is_symlink())
        self.assertTrue((self.esp/"EFI/domicile-rescue"/Path(self.p["target"]["kernel"]).name).exists())
        self.assertTrue((self.esp/"loader/entries/nixos-nine.conf").exists())

    def test_entry_fsync_failure_after_rename_withdraws_entry(self):
        original=install.fsync_dir
        def fail_once(path):
            if Path(path)==self.esp/"loader/entries" and Path(self.p["target"]["entry"]).exists():
                raise OSError("injected directory fsync failure")
            original(path)
        with patch.object(install,"fsync_dir",side_effect=fail_once):
            with self.assertRaisesRegex(OSError,"injected"):
                install.apply(self.p)
        self.assertFalse(Path(self.p["target"]["entry"]).exists())

    def test_atomic_publish_never_overwrites(self):
        src=self.root/"stage"
        dst=self.root/"occupied"
        src.write_text("new")
        dst.write_text("original")
        with self.assertRaises(FileExistsError):
            install.publish_noreplace(src,dst)
        self.assertEqual(dst.read_text(),"original")
        self.assertEqual(src.read_text(),"new")


if __name__=="__main__":
    unittest.main(verbosity=2)
