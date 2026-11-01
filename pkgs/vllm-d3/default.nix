{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  dockerTools,
  python3,
  bubblewrap,
  coreutils,
  writeShellApplication,
  runCommand,
}:
let
  provenance = import ../libstrix/provenance.nix;
  source = fetchFromGitHub {
    owner = "asf0";
    repo = "strix-vllm";
    rev = provenance.vllmRevision;
    hash = "sha256-JmVP5UmgJUi/YBgvppGF04L7tZRlhslumaYsIul6F7Y=";
  };
  referenceFormat = fetchurl {
    url = "https://huggingface.co/vllm-sr/d3-ultra/raw/52ba9e7a00402f9560c7fba8c039608e7ddee7fb/d3_format.py";
    hash = "sha256-Xz2nQwbmYiT+QUEo+oMH1z9Yr5T/Hu66y5gl9yjVByA=";
  };
  nativeReference = fetchFromGitHub {
    owner = "vllm-project";
    repo = "semantic-router";
    rev = "62c4f39e35aa2dfe929eb18223a7509ebeff6563";
    hash = "sha256-rgbPde4ilD9lglQnqVpjvt+chWnqwUYoZwwLbFASAGM=";
  };
  imageArchive = dockerTools.pullImage {
    imageName = provenance.imageName;
    imageDigest = provenance.imageDigest;
    sha256 = provenance.archiveHash;
    finalImageName = "d3-vllm-strix";
    finalImageTag = "2026-10-31";
    os = "linux";
    arch = "amd64";
  };
  patchedSource = stdenvNoCC.mkDerivation {
    pname = "d3-vllm-patched-python";
    version = "0.32.1rc0-d3-ultra";
    src = source;
    patches = [
      ./patches/0001-d3-prefix-bidir.patch
      ./patches/0002-d3-ultra-layout-temperature.patch
      ./patches/0003-d3-systemone-answer.patch
    ];
    nativeBuildInputs = [ python3 ];
    dontBuild = true;
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      ${python3.interpreter} ${./test_contract.py} "$PWD" ${referenceFormat} ${nativeReference}/src/model-runtime/vllm_srun
      ${python3.interpreter} ${./test_unpack.py} ${./unpack_image.py}
      runHook postCheck
    '';
    installPhase = ''
      mkdir -p "$out"
      ${lib.concatMapStringsSep "\n" (file: ''
        mkdir -p "$out/$(dirname ${lib.escapeShellArg file})"
        cp ${lib.escapeShellArg file} "$out/${file}"
      '') provenance.overlayFiles}
    '';
    dontFixup = true;
  };
  rootfs =
    runCommand "d3-vllm-strix-rootfs-2026-10-31"
      {
        nativeBuildInputs = [ python3 ];
        requiredSystemFeatures = [ "big-parallel" ];
        preferLocalBuild = false;
        # No binary rewriting: these binaries execute inside their own immutable
        # userspace, with exactly the Torch/ROCm ABI the publisher compiled them for.
        dontFixup = true;
      }
      ''
        ${python3.interpreter} ${./unpack_image.py} ${imageArchive} "$TMPDIR/rootfs"
        test "$(cat "$TMPDIR/rootfs/opt/strix/strix-vllm.ref")" = ${lib.escapeShellArg provenance.vllmRevision}
        test "$(cat "$TMPDIR/rootfs/opt/strix/libstrix.ref")" = ${lib.escapeShellArg provenance.libstrixRevision}
        ${lib.concatMapStringsSep "\n" (file: ''
          cmp ${source}/${file} "$TMPDIR/rootfs/opt/venv/lib/python3.14/site-packages/${file}"
        '') provenance.overlayFiles}
        mkdir -p "$TMPDIR/rootfs"/{nix/store,models/d3-ultra,cache,proc,sys,run,tmp,dev/dri}
        mv "$TMPDIR/rootfs" "$out"
      '';
  package = writeShellApplication {
    name = "d3-vllm";
    runtimeInputs = [
      bubblewrap
      coreutils
    ];
    text = ''
      if [ "''${1:-}" != serve ] || [ "$#" -lt 2 ]; then
        echo "usage: d3-vllm serve /absolute/loan/directory [vllm serve options]" >&2
        exit 2
      fi
      shift
      model=$(realpath -e -- "$1")
      shift
      if [ ! -d "$model" ] || [ ! -f "$model/decision_config.json" ]; then
        echo "d3-vllm: expected a complete local D3 loan directory" >&2
        exit 2
      fi
      cache="''${D3_CACHE_ROOT:-''${LLAMA_CACHE:-''${XDG_CACHE_HOME:-/var/cache/d3-decision}}/d3-vllm}"
      mkdir -p "$cache/home" "$cache/tmp"
      cache=$(realpath -e -- "$cache")
      case "''${D3_VLLM_LIBSTRIX:-0}" in
        0) disable=all ;;
        # The HIP attention kernels implement causal attention. Keep the
        # upstream PrefixLM-aware attention for Ultra in both A/B variants.
        1) disable=attn_prefill,attn_decode ;;
        *) echo "d3-vllm: D3_VLLM_LIBSTRIX must be 0 or 1" >&2; exit 2 ;;
      esac
      exec bwrap --die-with-parent --new-session --clearenv \
        --unshare-user --unshare-pid --unshare-ipc --unshare-uts \
        --ro-bind ${rootfs} / \
        --ro-bind /nix/store /nix/store \
        ${
          lib.concatMapStringsSep " " (
            file: "--ro-bind ${patchedSource}/${file} /opt/venv/lib/python3.14/site-packages/${file}"
          ) provenance.overlayFiles
        } \
        --proc /proc --dev /dev --ro-bind /sys /sys \
        --dev-bind /dev/kfd /dev/kfd --dev-bind /dev/dri /dev/dri \
        --tmpfs /tmp --tmpfs /run \
        --bind "$cache" /cache --ro-bind "$model" /models/d3-ultra \
        --setenv HOME /cache/home --setenv XDG_CACHE_HOME /cache \
        --setenv PATH /opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        --setenv VIRTUAL_ENV /opt/venv \
        --setenv SP /opt/venv/lib/python3.14/site-packages \
        --setenv ROCM_PATH /opt/venv/lib/python3.14/site-packages/_rocm_sdk_devel \
        --setenv ROCM_HOME /opt/venv/lib/python3.14/site-packages/_rocm_sdk_devel \
        --setenv HIP_PATH /opt/venv/lib/python3.14/site-packages/_rocm_sdk_devel \
        --setenv LD_LIBRARY_PATH /opt/venv/lib/python3.14/site-packages/torch/lib:/opt/venv/lib/python3.14/site-packages/_rocm_sdk_core/lib:/opt/venv/lib/python3.14/site-packages/_rocm_sdk_devel/lib:/opt/venv/lib/python3.14/site-packages/_rocm_sdk_libraries/lib \
        --setenv PYTHONPATH /opt/venv/lib/python3.14/site-packages/_rocm_sdk_core/share/amd_smi \
        --setenv VLLM_TARGET_DEVICE rocm --setenv PYTORCH_ROCM_ARCH gfx1151 \
        --setenv TMPDIR /tmp \
        --setenv LANG C.UTF-8 --setenv USER d3-decision \
        --setenv HF_HOME /cache/huggingface \
        --setenv HF_HUB_OFFLINE 1 --setenv TRANSFORMERS_OFFLINE 1 \
        --setenv HF_HUB_DISABLE_TELEMETRY 1 \
        --setenv VLLM_NO_USAGE_STATS 1 --setenv DO_NOT_TRACK 1 \
        --setenv VLLM_CACHE_ROOT /cache/vllm \
        --setenv TRITON_CACHE_DIR /cache/triton \
        --setenv TORCHINDUCTOR_CACHE_DIR /cache/torchinductor \
        --setenv STRIX_DISABLE "$disable" \
        --setenv STRIX_ENABLE "" \
        --setenv VLLM_USE_V2_MODEL_RUNNER 1 \
        --chdir /cache \
        /opt/venv/bin/vllm serve /models/d3-ultra "$@" \
        --no-enable-prefix-caching --no-enable-chunked-prefill \
        --attention-backend TRITON_ATTN
    '';
    passthru = {
      inherit
        imageArchive
        patchedSource
        rootfs
        provenance
        ;
      tests.contract = patchedSource;
    };
    meta = {
      description = "Pinned gfx1151 vLLM/libstrix appliance with D3-Ultra contract patches";
      platforms = [ "x86_64-linux" ];
      mainProgram = "d3-vllm";
      license = [
        lib.licenses.asl20
        lib.licenses.mit
      ];
    };
  };
in
package
