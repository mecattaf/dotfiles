
on cloud they have e2b which provides firecracker to run code. we want the same but for local fedora atomic. this is "stackblitz versus gitpod"; the latter focused on running code


Skip to content
Chat history


You said:
Firecracker vm on local fedora linux? Fedora atomic has deep quadlet support amongst other things
- **Adoption:** This technology is the foundation for many major platforms:
  - [**e2b** ↓](https://github.com/restyler/awesome-sandbox?tab=readme-ov-file#41-e2b-the-ai-agent-sandbox-runtime) - leverages Firecracker for secure, fast-starting sandboxes for AI agents
  - [**Fly.io** ↓](https://github.com/restyler/awesome-sandbox?tab=readme-ov-file#47-flyio-modern-application-hosting-with-microvms) - uses Firecracker microVMs for modern application hosting
  - **AWS Lambda** - Amazon's serverless computing service runs on Firecracker
  - **AWS Fargate** - Amazon's container hosting service uses Firecracker for isolation
ChatGPT said:
Here’s a clear, practical guide to running Firecracker microVMs on local Fedora Linux (including Fedora Atomic with Quadlet) — along with context for how other platforms use it (like Fly.io, AWS Lambda, etc.).

🔥 Firecracker on Local Fedora (including Fedora Atomic)
Firecracker runs perfectly on Fedora because Fedora ships a modern kernel with KVM support and all required virtualization modules.

Below is a minimal, modern setup path, then optional systemd/Quadlet integration.

✅ 1. Install Firecracker + Tools
sudo dnf install firecracker jq curl
If your Fedora release doesn’t package a new enough Firecracker, download directly:

VERSION=v1.10.0
curl -LO https://github.com/firecracker-microvm/firecracker/releases/download/$VERSION/firecracker-$VERSION-x86_64
sudo mv firecracker-$VERSION-x86_64 /usr/local/bin/firecracker
sudo chmod +x /usr/local/bin/firecracker
Also install firectl, a minimal wrapper:

sudo dnf install firectl
✅ 2. Prepare a Kernel + RootFS
Most people use the Amazon Linux rootfs for quick starts, but you can use Fedora CoreOS minimal images too.

Example (Amazon-provided demo rootfs):

curl -LO https://s3.amazonaws.com/spec.ccfc.min/img/hello/fsfiles/x86_64/kernel.bin
curl -LO https://s3.amazonaws.com/spec.ccfc.min/img/hello/fsfiles/x86_64/rootfs.ext4
✅ 3. Run a Simple MicroVM
firecracker --api-sock /tmp/firecracker.socket
In another terminal:

curl --unix-socket /tmp/firecracker.socket -i \
  -X PUT "http://localhost/machine-config" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "vcpu_count": 1,
    "mem_size_mib": 256,
    "ht_enabled": false
  }'
Attach kernel:

curl --unix-socket /tmp/firecracker.socket -i \
  -X PUT "http://localhost/boot-source" \
  -H "Content-Type: application/json" \
  -d '{
    "kernel_image_path": "./kernel.bin",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
  }'
Attach rootfs:

curl --unix-socket /tmp/firecracker.socket -i \
  -X PUT "http://localhost/drives/rootfs" \
  -H "Content-Type: application/json" \
  -d '{
    "drive_id": "rootfs",
    "path_on_host": "./rootfs.ext4",
    "is_root_device": true,
    "is_read_only": false
  }'
Start VM:

curl --unix-socket /tmp/firecracker.socket -i \
  -X PUT "http://localhost/actions" \
  -d '{"action_type": "InstanceStart"}'
You should now see a Linux boot log in the Firecracker terminal.

🧱 4. Firecracker on Fedora Atomic with Quadlet
Fedora Atomic has first-class support for systemd Quadlet → you can treat Firecracker like a service and run microVMs declaratively.

Example: /etc/containers/systemd/firecracker.vm
[Unit]
Description=Firecracker microVM (simple)

[Service]
ExecStart=/usr/local/bin/firecracker --api-sock /run/firecracker.sock
Restart=always

[Install]
WantedBy=default.target
Enable:

sudo systemctl daemon-reload
sudo systemctl enable --now firecracker.vm
To make this truly declarative, you can integrate Ignition-fed images or Fedora CoreOS rootfs and generate drives at boot via Quadlet's Volume= features.

If you want, I can provide a fully working Quadlet spec for:

automatic kernel injection

rootfs provisioning

cloud-init/ignition-style user data

network tap device creation

🌐 Who Uses Firecracker? (Context You Included)
Firecracker’s adoption is huge because of its boot speed (<5ms) and process-like VM isolation.

✔ e2b (AI Agent Runtime)
Runs each agent in a microVM for secure ephemeral execution.

✔ Fly.io
Each “fly machine” is a Firecracker microVM, giving per-app isolation at container-level density.

✔ AWS Lambda
Each Lambda cold-start spins a microVM with snapshot restore.

✔ AWS Fargate
Tasks run inside microVMs instead of Docker-in-Docker.

This makes Firecracker ideal for:

AI agent sandboxes

multi-tenant PaaS

serverless platforms

secure ephemeral CI workloads

replacing Docker with stronger isolation

🚀 Want a Full Local Stack?
I can generate for you:

A complete Quadlet-managed Firecracker VM (with storage + networking)

A Fedora CoreOS microVM image pipeline

A wrapper CLI similar to flyctl or firectl

A developer-friendly hot-reload microVM setup

Just tell me what workflow you want:
➡️ “Run containers inside microVMs?”
➡️ “Use Fedora CoreOS as the guest OS?”
➡️ “Manage microVMs via systemd declaratively?”
➡️ “Attach an OCI image as a rootfs?”

Happy to build the exact configuration.



No file chosenNo file chosen
ChatGPT can make mistakes. Check important info. See Cookie Preferences.
