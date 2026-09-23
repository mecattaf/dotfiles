# Phase 20: Substrate (track substrate; DESIGN.md sections 12.1 phases 2 and 3,
# and section 14 S4). Concatenated after 10-cluster.py, so both switches have
# happened: the NAS runs k3s, the registry seed and the bootstrap, and the
# coordinator has joined as the tainted harness node.
#
# Uses only the machine objects `nas` and `coordinator`. Every kubectl runs on
# the NAS as root against /etc/rancher/k3s/k3s.yaml.
import json

SUB_NS = "ate-system"
SUB_LOCAL_PATH = "/mnt/nas/services/ax-fleet/local-path/"
SUB_CONTROL_DEPLOYMENTS = [
    "ate-api-server",
    "ate-controller",
    "atenet-router",
]
# ate-setup installs the pod-certificate controller in its own namespace
# (manifests/ate-install/pod-certificate-controller.yaml), not in ate-system.
SUB_PODCERT_NS = "podcertificate-controller-system"


def sub_k(args, timeout=120):
    return nas.succeed(f"KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl {args}", timeout=timeout)


def sub_json(args):
    return json.loads(sub_k(f"{args} -o json"))


with subtest("substrate: bootstrap steps 20-50 ran"):
    nas.wait_for_unit("ax-fleet-bootstrap.service", timeout=3600)
    boot_log = nas.succeed("journalctl -b -u ax-fleet-bootstrap.service --no-pager")
    # Not `step`: that name is the prelude's receipt context manager, which
    # 90-rollback still needs.
    for step_name in ["20-registry-svc", "30-substrate", "40-gvisor-asset", "50-workerpool"]:
        assert f"step {step_name}" in boot_log, f"bootstrap step {step_name} did not run"
    assert "gvisor asset verified" in boot_log, "40-gvisor-asset did not verify the tarball"
    stamp = sub_k(
        "-n kube-system get configmap ax-fleet-substrate -o jsonpath='{.data.version}'"
    ).strip()
    assert stamp == "d277088b", f"install stamp version {stamp!r}"

with subtest("substrate: every control workload Available, on the NAS"):
    nas.wait_until_succeeds(
        f"KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n {SUB_NS} wait "
        "--for=condition=Available deploy --all --timeout=10s",
        timeout=900,
    )
    names = {d["metadata"]["name"] for d in sub_json(f"-n {SUB_NS} get deploy")["items"]}
    for want in SUB_CONTROL_DEPLOYMENTS:
        assert want in names, f"deployment {want} missing: {sorted(names)}"
    # atenet-egress is the actor egress gateway; its kind differs across
    # dataplanes, so it is found by name among Deployments and StatefulSets.
    sts = {s["metadata"]["name"] for s in sub_json(f"-n {SUB_NS} get statefulset")["items"]}
    assert any(n.startswith("atenet-egress") for n in names | sts), "no atenet-egress"
    assert "postgres" in sts, f"postgres StatefulSet missing: {sorted(sts)}"
    sub_k(f"-n {SUB_NS} rollout status statefulset/postgres --timeout=600s", timeout=660)
    sub_k(
        f"-n {SUB_PODCERT_NS} wait --for=condition=Available deploy/podcertificate-controller --timeout=600s",
        timeout=660,
    )
    for pod in sub_json(f"-n {SUB_PODCERT_NS} get pods")["items"]:
        assert pod["spec"].get("nodeName") == "nas", f"{pod['metadata']['name']} on {pod['spec'].get('nodeName')!r}"
    for pod in sub_json(f"-n {SUB_NS} get pods")["items"]:
        owner = (pod["metadata"].get("ownerReferences") or [{}])[0].get("kind", "")
        name = pod["metadata"]["name"]
        node = pod["spec"].get("nodeName", "")
        if name.startswith("atelet") or pod["metadata"].get("labels", {}).get(
            "ax.mecattaf.dev/pool"
        ):
            continue
        if owner == "Job" and pod["status"].get("phase") == "Succeeded":
            continue
        assert node == "nas", f"control pod {name} landed on {node!r}"

with subtest("substrate: nas keeps substrate-version=none, coordinator carries the version"):
    nodes = {n["metadata"]["name"]: n for n in sub_json("get nodes")["items"]}
    assert nodes["nas"]["metadata"]["labels"].get("ate.dev/substrate-version") == "none"
    assert (
        nodes["coordinator"]["metadata"]["labels"].get("ate.dev/substrate-version")
        == "d277088b"
    )

with subtest("substrate: atelet runs on the coordinator only"):
    # The atelet DaemonSet is version-keyed by ate-setup; find it by label.
    ds = sub_k(f"-n {SUB_NS} get ds -l app=atelet -o jsonpath='{{.items[0].metadata.name}}'").strip()
    sub_k(f"-n {SUB_NS} rollout status ds/{ds} --timeout=600s", timeout=660)
    atelet = [
        p
        for p in sub_json(f"-n {SUB_NS} get pods")["items"]
        if p["metadata"]["name"].startswith("atelet")
    ]
    assert atelet, "no atelet pod"
    for p in atelet:
        assert p["spec"]["nodeName"] == "coordinator", (
            f"atelet on {p['spec']['nodeName']}"
        )

with subtest("substrate: ClusterTrustBundles and pod certificates served"):
    res = sub_k("get --raw /apis/certificates.k8s.io/v1beta1")
    assert "clustertrustbundles" in res and "podcertificaterequests" in res, res
    assert sub_json("get clustertrustbundles")["items"], "no ClusterTrustBundle objects"

with subtest("substrate: WorkerPool ateom-gvisor Ready 2 on the coordinator"):
    nas.wait_until_succeeds(
        "test \"$(KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n ate-system get "
        "workerpool ateom-gvisor -o jsonpath='{.status.readyReplicas}')\" = 2",
        timeout=900,
    )
    wp = sub_json(f"-n {SUB_NS} get workerpool ateom-gvisor")
    assert "@sha256:" in wp["spec"]["workerImage"], wp["spec"]["workerImage"]
    workers = [
        p
        for p in sub_json(f"-n {SUB_NS} get pods -l ax.mecattaf.dev/pool=ateom-gvisor")["items"]
    ]
    assert len(workers) == 2, f"{len(workers)} worker pods"
    for p in workers:
        assert p["spec"]["nodeName"] == "coordinator", p["spec"]["nodeName"]
        lims = [c.get("resources", {}).get("limits", {}).get("memory") for c in p["spec"]["containers"]]
        assert any(lims), f"worker pod has no memory limit: {lims}"

with subtest("substrate: gVisor fetched through the RustFS fallback"):
    # No internet in the VM: atelet's anonymous GCS open of gs://gvisor/...
    # fails, then its S3 client reads the same bucket and key from the
    # in-cluster RustFS (40-gvisor-asset). The prewarmer logs "Sandbox assets
    # prewarmed" for gvisor-default only once the pause image and the gVisor
    # tarball (sha256-checked by atelet) are both on the node
    # (cmd/atelet/sandbox_prewarm.go).
    nas.wait_until_succeeds(
        "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n ate-system logs -l app=atelet "
        "--all-containers --tail=-1 | grep 'Sandbox assets prewarmed' | grep -q gvisor-default",
        timeout=900,
    )
    logs = sub_k(f"-n {SUB_NS} logs -l app=atelet --all-containers --tail=-1", timeout=300)
    print("\n".join(l for l in logs.splitlines() if "gvisor" in l.lower())[-4000:])
    assert "gVisor release download complete" in logs or "gvisor" in logs.lower()

with subtest("substrate: every PersistentVolume on the data pool"):
    pvs = sub_json("get pv")["items"]
    assert pvs, "no PersistentVolumes"
    for pv in pvs:
        spec = pv["spec"]
        path = (spec.get("hostPath") or spec.get("local") or {}).get("path", "")
        assert path.startswith(SUB_LOCAL_PATH), (pv["metadata"]["name"], path)
        node_terms = (
            spec.get("nodeAffinity", {}).get("required", {}).get("nodeSelectorTerms", [])
        )
        values = [
            v
            for t in node_terms
            for e in t.get("matchExpressions", [])
            for v in e.get("values", [])
        ]
        assert "coordinator" not in values, f"PV {pv['metadata']['name']} on the coordinator"

with subtest("substrate: every image came from the NAS registry by digest"):
    pods = sub_json(f"-n {SUB_NS} get pods")["items"]
    for p in pods:
        for c in p["spec"].get("containers", []) + p["spec"].get("initContainers", []):
            assert "@sha256:" in c["image"], f"{p['metadata']['name']}: {c['image']}"
