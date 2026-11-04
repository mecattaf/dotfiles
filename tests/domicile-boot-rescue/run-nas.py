#!/usr/bin/env python3
"""NAS orchestration only. Stream Strix reader to client; generate/preview on Strix.
Never copies a checkout, credentials, kernel or initrd. Never calls the installer.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid

WORKTREE="/home/tom/compute/dotfiles-domicile-boot-rescue"
REL="tests/domicile-boot-rescue"
FLEET=["fleet-exec","strix-coordinator","--cwd",WORKTREE,"--"]
SSH=["ssh","-o","BatchMode=yes","-o","StrictHostKeyChecking=yes","client"]
ARTIFACTS=["plan.json","PLAN.txt","rescue-entry.conf","install-reviewed.py","preview.json"]
IDENTITY=("hostname","kernel","booted","current","boot_id","machine_id","assets","bootspec",
          "boot_json_sha256","module_versions","kernel_params","cmdline","kernel_type",
          "bootctl_version","secure_boot","esp_path","boot_path","mount","loader_conf",
          "selectors","entries","boot_entries","closure","installed_sources","collisions","selector_values","esp_files")


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out",required=True,help="new local NAS directory for bounded evidence")
    args=ap.parse_args()
    out=Path(args.out).resolve()
    out.mkdir(parents=True,exist_ok=False)
    receipt=dict(status="RUNNING",install_executed=False,steps=[])
    def execute(label,argv,data=None):
        p=subprocess.run(argv,input=data,capture_output=True,timeout=180)
        receipt["steps"].append(dict(label=label,argv=argv,returncode=p.returncode,
                                    stderr=p.stderr.decode(errors="replace")))
        if p.returncode or len(p.stdout)>1024*1024:
            raise RuntimeError(f"{label} failed; see receipt")
        return p.stdout
    def save_json(name,data):
        (out/name).write_text(json.dumps(data,indent=2)+"\n")
    try:
        commit=execute("worktree commit",FLEET+["git","rev-parse","HEAD"]).decode().strip()
        dirty=execute("worktree status",FLEET+["git","status","--porcelain"]).decode()
        if dirty:
            raise RuntimeError("Strix worktree has uncommitted changes; review and commit before measured run")
        receipt["commit"]=commit
        reader=execute("load read-only observer",FLEET+["cat",REL+"/rescue.py"])
        before_bytes=execute("read-only client before",SSH+["sudo -n python3 - observe"],reader)
        before=json.loads(before_bytes)
        save_json("client-before.json",before)
        run_id=time.strftime("%Y%m%dT%H%M%SZ",time.gmtime())+"-"+uuid.uuid4().hex[:8]
        remote_out="/home/tom/compute/domicile-boot-rescue-runs/"+run_id
        receipt["remote_artifacts"]=remote_out
        rendered=execute("validate and render on Strix",FLEET+["python3",REL+"/rescue.py",
                         "render","--snapshot","-","--out",remote_out],before_bytes)
        receipt["render"]=json.loads(rendered)
        preview=execute("isolated real bootctl preview on Strix",
                        FLEET+["/home/tom/.local/bin/runtime-test","--","python3",
                               REL+"/preview.py","--plan",remote_out+"/plan.json",
                               "--out",remote_out+"/preview.json"])
        receipt["preview"]=json.loads(preview)
        for name in ARTIFACTS:
            data=execute("fetch review artifact "+name,FLEET+["cat",remote_out+"/"+name])
            (out/name).write_bytes(data)
        after=json.loads(execute("read-only client after",SSH+["sudo -n python3 - observe"],reader))
        save_json("client-after.json",after)
        changed=[k for k in IDENTITY if before[k]!=after[k]]
        receipt["changed_identity_fields"]=changed
        if changed:
            raise RuntimeError("Client state changed during dry-run: "+", ".join(changed))
        receipt.update(status="VALIDATED_READ_ONLY_DRY_RUN",client_unchanged=True,
                       rescue_installed=False,rescue_boot_tested=False,
                       no_client_roots_query=True,
                       manifest={name:dict(bytes=(out/name).stat().st_size,
                           sha256=hashlib.sha256((out/name).read_bytes()).hexdigest())
                           for name in ARTIFACTS})
        print(json.dumps(dict(status=receipt["status"],out=str(out),commit=commit,
                              entry=receipt["render"]["entry_id"],
                              script_sha256=receipt["render"]["script_sha256"]),indent=2))
    except (OSError,ValueError,RuntimeError,subprocess.TimeoutExpired) as e:
        receipt.update(status="FAILED",error=str(e))
        print(f"FAILED: {e}; retained evidence in {out}",file=sys.stderr)
        return 1
    finally:
        save_json("receipt.json",receipt)
    return 0


if __name__=="__main__":
    sys.exit(main())
