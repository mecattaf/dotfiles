# Blueprint Jupyter Implementation Guide

## Files Created

All files are ready to deploy to your chezmoi dotfiles repository.

### 1. Dockerfile.tmpl
**Location:** `home/dot_config/containers/systemd/jupyter/Dockerfile.tmpl`
- Base: `scipy-notebook:latest` (scientific Python stack)
- Adds: `nb_conda_kernels` (multi-environment support)
- Adds: `notebook-intelligence` (AI code completion)
- Creates: `/home/jovyan/blueprint-workspace`

### 2. jupyter.container.tmpl
**Location:** `home/dot_config/containers/systemd/jupyter/jupyter.container.tmpl`
- Quadlet container definition
- Auto-builds custom image on first start
- Configures notebook-intelligence with LiteLLM
- OpenWebUI-compatible settings
- WebSocket support enabled

### 3. jupyter.caddy.tmpl
**Location:** `home/dot_config/caddy/jupyter.caddy.tmpl`
- Reverse proxy for external access
- WebSocket support for interactive features
- Tailscale HTTPS endpoint

### 4. jupyter.volume
**Location:** `home/dot_config/containers/systemd/jupyter/jupyter.volume`
- Persistent storage for notebooks and data

---

## Required Updates to Existing Files

### Update 1: .chezmoi.yaml.tmpl

Add this to `infrastructure.services` section:

```yaml
      jupyter:
        hostname: "jupyter"
        container_name: "jupyter"
        port: 8888                          # Internal container port
        published_port: 8889                # Published to host
        bind: "127.0.0.1"
        image: "localhost/blueprint-jupyter:latest"  # Custom built image
        external_subdomain: "jupyter"
        enabled_by: ["openwebui.features.code_execution"]
        requires: ["litellm"]               # Needs LiteLLM for AI features
        websocket: true
        description: "Blueprint Jupyter Lab - AI Code Interpreter"
        volume: "jupyter.volume"
        workspace: "/home/jovyan/blueprint-workspace"
```

**Location in file:** Add after the `edgetts` service definition, before `cockpit`.

---

### Update 2: openwebui.env.tmpl

Add this to the **Code Execution** section:

```bash
# ═════════════════════════════════════════════════════════════════════════════
# 💻 CODE EXECUTION (Decision 6-7: Enable? + Decision 26-27: Which engine?)
# ═════════════════════════════════════════════════════════════════════════════

{{- if .openwebui.features.code_execution }}
# Code Execution Enabled
ENABLE_CODE_EXECUTION=true
CODE_EXECUTION_ENGINE=jupyter

# Code Interpreter Enabled (more powerful than Pyodide)
ENABLE_CODE_INTERPRETER=true
CODE_INTERPRETER_ENGINE=jupyter

# Jupyter Configuration
JUPYTER_URL=http://{{ .infrastructure.services.jupyter.hostname }}:{{ .infrastructure.services.jupyter.port }}
JUPYTER_AUTH_TYPE=none
JUPYTER_TIMEOUT=60

{{- else }}
# Code Execution Disabled
ENABLE_CODE_EXECUTION=false
ENABLE_CODE_INTERPRETER=false

{{- end }}
```

**Replace the existing code execution section** (around line 260-280).

---

## Deployment Steps

### 1. Add Files to Chezmoi

```bash
# Navigate to your dotfiles directory
cd ~/dotfiles

# Create jupyter directory structure
mkdir -p home/dot_config/containers/systemd/jupyter

# Copy files (adjust paths as needed)
cp Dockerfile.tmpl home/dot_config/containers/systemd/jupyter/
cp jupyter.container.tmpl home/dot_config/containers/systemd/jupyter/
cp jupyter.volume home/dot_config/containers/systemd/jupyter/
cp jupyter.caddy.tmpl home/dot_config/caddy/

# Apply changes
chezmoi apply -v
```

### 2. Update Configuration Files

```bash
# Edit .chezmoi.yaml.tmpl to add jupyter service definition
vim home/.chezmoi.yaml.tmpl

# Edit openwebui.env.tmpl to add Jupyter integration
vim home/dot_config/containers/systemd/openwebui/openwebui.env.tmpl

# Apply templates
chezmoi apply -v
```

### 3. Reload Systemd and Start Services

```bash
# Reload systemd to pick up new units
systemctl --user daemon-reload

# Build and start Jupyter (will auto-build image first)
systemctl --user start jupyter

# Check status
systemctl --user status jupyter

# View logs
journalctl --user -u jupyter -f
```

### 4. Reload Caddy (if exposing externally)

```bash
# Reload Caddy to pick up new route
systemctl --user reload caddy
```

### 5. Restart OpenWebUI (to apply new environment variables)

```bash
systemctl --user restart openwebui
```

---

## Verification Steps

### 1. Check Jupyter is Running

```bash
# Service status
systemctl --user status jupyter

# Access via published port (from host)
curl http://localhost:8889

# Access via llm.network (from another container)
podman exec openwebui curl http://jupyter:8888/api
```

### 2. Check Caddy Route

```bash
# Should show jupyter route
systemctl --user status caddy

# Access externally (if on Tailscale)
curl https://jupyter.blueprint.tail8dd1.ts.net
```

### 3. Test OpenWebUI Integration

1. Open OpenWebUI: `https://ai.blueprint.tail8dd1.ts.net`
2. Go to Admin Panel → Settings → Code Execution
3. Verify settings:
   - Code Interpreter: **Enabled** ✅
   - Engine: **Jupyter** ✅
   - Jupyter URL: `http://jupyter:8888` ✅
   - Auth: **None** ✅
4. Start a new chat
5. Test code execution:
   ```
   User: Can you generate a plot of y = x^2 from -10 to 10?
   
   AI: [Generates matplotlib code and executes it in Jupyter]
   ```

### 4. Test Notebook Intelligence

1. Access Jupyter directly: `https://jupyter.blueprint.tail8dd1.ts.net`
2. Create a new notebook
3. Go to Settings → Notebook Intelligence Settings
4. Verify LiteLLM connection:
   - Provider: **LiteLLM** ✅
   - Base URL: `http://litellm:4000` ✅
   - API Key: `sk-litellm-local` ✅
5. Test code completion:
   ```python
   import pandas as pd
   df = pd.read_csv('data.csv')
   df.# [AI should suggest completions]
   ```

---

## Configuration Options

### Notebook Intelligence Settings

After deployment, you can configure AI code completion:

1. Access Jupyter: `https://jupyter.blueprint.tail8dd1.ts.net`
2. Go to: Settings → Notebook Intelligence Settings
3. Configure:
   - **Provider:** LiteLLM compatible
   - **Model Name:** `openai/gpt-4o-mini` (or any model from your LiteLLM)
   - **Base URL:** `http://litellm:4000`
   - **API Key:** `sk-litellm-local`

Settings are stored at `~/.jupyter/nbi/config.json` inside the container (persisted via volume).

### Creating Additional Conda Environments

```bash
# Enter container
podman exec -it jupyter bash

# Create new environment
conda create -n myproject python=3.11 ipykernel pandas numpy

# Register as kernel
conda activate myproject
python -m ipykernel install --user --name=myproject --display-name="Python (myproject)"

# Now available in Jupyter notebook kernel selector
```

### Installing Packages On-Demand

In any notebook:

```python
# Via conda
%conda install scikit-learn

# Via pip
%pip install requests beautifulsoup4
```

Packages persist in the workspace volume.

---

## Troubleshooting

### Issue: Image Build Fails

```bash
# Check build logs
systemctl --user status jupyter

# Manually build to see errors
podman build -t localhost/blueprint-jupyter:latest \
  -f ~/.config/containers/systemd/jupyter/Dockerfile \
  ~/.config/containers/systemd/jupyter
```

### Issue: OpenWebUI Can't Connect

```bash
# Check Jupyter is running
systemctl --user status jupyter

# Test network connectivity from OpenWebUI
podman exec openwebui curl http://jupyter:8888/api

# Check OpenWebUI logs
journalctl --user -u openwebui -f | grep -i jupyter
```

### Issue: Notebook Intelligence Not Working

```bash
# Check LiteLLM is accessible from Jupyter
podman exec jupyter curl http://litellm:4000/health

# Check environment variables are set
podman exec jupyter env | grep LITELLM

# Check notebook-intelligence is installed
podman exec jupyter pip list | grep notebook-intelligence
podman exec jupyter jupyter labextension list | grep notebook-intelligence
```

### Issue: Code Execution Fails

```bash
# Check OpenWebUI environment variables
podman exec openwebui env | grep JUPYTER

# Restart both services
systemctl --user restart jupyter openwebui
```

---

## Advanced Features

### Security: Enable Notebook Execute Tool (Optional)

By default, the notebook execute tool is disabled for security. To enable:

```bash
# Edit jupyter.container.tmpl, change:
Environment=NBI_NOTEBOOK_EXECUTE_TOOL=disabled
# To:
Environment=NBI_NOTEBOOK_EXECUTE_TOOL=enabled

# Apply and restart
chezmoi apply
systemctl --user restart jupyter
```

This allows AI to execute code in notebooks directly (powerful but requires trust).

### Performance: Pre-install Common Packages

Edit `Dockerfile.tmpl` to add commonly used packages:

```dockerfile
# After the nb_conda_kernels installation, add:
RUN pip install \
    scikit-learn \
    seaborn \
    plotly \
    requests \
    beautifulsoup4 \
    transformers
```

Then rebuild:

```bash
systemctl --user restart jupyter
```

---

## Architecture Summary

```
External User
    ↓ (https://jupyter.blueprint.tail8dd1.ts.net)
Caddy (Tailscale HTTPS + reverse proxy)
    ↓
llm.network (10.89.0.0/24)
    ↓
Jupyter Container (localhost/blueprint-jupyter:latest)
    ├─ Base: scipy-notebook (NumPy, Pandas, Matplotlib, SciPy, scikit-learn)
    ├─ Added: nb_conda_kernels (multi-environment support)
    ├─ Added: notebook-intelligence (AI code completion)
    ├─ Config: LiteLLM integration
    ├─ Workspace: /home/jovyan/blueprint-workspace (persisted)
    └─ Port: 8888 (internal), 8889 (published)

OpenWebUI (Code Interpreter)
    ↓ (http://jupyter:8888)
Jupyter (Execute AI-generated code)
    ↓
Results returned to OpenWebUI

Jupyter (Notebook Intelligence)
    ↓ (http://litellm:4000)
LiteLLM
    ↓
Local LLMs (via llama-swap) or Cloud APIs
```

---

## What You Get

### 1. **Professional Jupyter Setup** (Ansible-style)
- ✅ Scientific Python stack (scipy-notebook)
- ✅ Multi-environment support (nb_conda_kernels)
- ✅ AI code completion (notebook-intelligence + LiteLLM)
- ✅ Persistent workspace
- ✅ Production-grade configuration

### 2. **OpenWebUI Integration**
- ✅ Code Interpreter: AI executes code with persistent kernel context
- ✅ Code Execution: More powerful than Pyodide (full Python + packages)
- ✅ Automatic connection via llm.network
- ✅ Zero-config setup

### 3. **AI-Enhanced Development**
- ✅ Real-time code completion via local LLMs
- ✅ GitHub Copilot-like experience but local
- ✅ Powered by your own models (via LiteLLM)
- ✅ No cloud API calls needed (privacy preserved)

### 4. **External Access**
- ✅ Secure access via Tailscale
- ✅ HTTPS via Caddy
- ✅ WebSocket support for interactive features
- ✅ URL: `https://jupyter.blueprint.tail8dd1.ts.net`

### 5. **Containerized but Feature-Rich**
- ✅ Quadlet-based (consistent with your architecture)
- ✅ Auto-builds custom image
- ✅ All Ansible features preserved
- ✅ Minimal host pollution

---

## Next Steps

1. **Deploy:** Copy files to chezmoi and apply
2. **Test:** Verify Jupyter starts and OpenWebUI connects
3. **Configure:** Set up notebook-intelligence with your preferred model
4. **Use:** Start creating notebooks with AI assistance!
5. **Explore:** Create conda environments for different projects

---

## Files Ready for Deployment

All files are in `/home/claude/jupyter-implementation/`:

```
jupyter-implementation/
├── Dockerfile.tmpl           → home/dot_config/containers/systemd/jupyter/
├── jupyter.container.tmpl    → home/dot_config/containers/systemd/jupyter/
├── jupyter.volume            → home/dot_config/containers/systemd/jupyter/
├── jupyter.caddy.tmpl        → home/dot_config/caddy/
└── IMPLEMENTATION.md         → This file (reference)
```

**Modifications needed:**
- `.chezmoi.yaml.tmpl`: Add jupyter service definition
- `openwebui.env.tmpl`: Update code execution section

Ready to deploy! 🚀
