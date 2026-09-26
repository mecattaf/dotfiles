{
  config,
  lib,
  pkgs,
  ...
}:
# services.academicIngest.arxivFetch: lane R of the academic ingest. Pulls a PINNED revision of the
# secemp9/arxiv-complete dataset (Hugging Face) onto the NAS data pool, sha-verified, resumable, never deleting.
#
# RULING. Tom, 2026-09-26: "re arxiv-complete: let's get that in on NAS. i m happy to start searching through."
# Scope (ARXIV-COMPLETE-CORPUS.md, 2026-09-26, MEASURED from the Hub tree API): the text layer `paper_text/` is
# 50 Parquet shards, 70.27 GB, 2,856,227 papers of resolved TeX; the indexes `metadata/` (1.64 GB), `versions/`
# (0.27 GB) and `files/` (2.43 GB) carry categories, DOI, title, authors, abstract, dates, licence and sha256.
# A category-selective remote read saves almost nothing (the cs.IT slice touches 63.6 of the 69.0 GB text column),
# so the unit fetches whole configs. The `pdf` (8.65 TB), `source` (6.51 TB) and `latex` (160 GB) configs are
# never included.
#
# WHO WRITES /mnt/nas: this unit, as User=tom, on the NAS. Agents never write there (standing rule); a person
# starts the unit (`systemctl start arxiv-fetch`) or the timer fires when `onCalendar` is set. The same pattern
# as library-fetch (hosts/nas/models.nix): the only things that talk to Hugging Face are declared units.
#
# THE TOKEN: /run/agenix/huggingface-token is delivered to tom 0400 on this host (modules/secrets.nix). The
# dataset is not gated, so the token is only the anonymous rate limit's escape (3,000 resolver requests per
# 300 s, MEASURED); the script exports it as HF_TOKEN for `hf` when readable and runs anonymously otherwise.
#
# LAYOUT: <root>/<dataset-slug>/<revision>/{README.md,LICENSE,SHA256SUMS,metadata,versions,files,sample,paper_text}
# plus RECEIPT-<UTC stamp>.txt after each run and COMPLETE once every included file verifies against SHA256SUMS.
# `hf download` skips files already present at the right size and resumes partials, so re-running converges.
# Kill switch: `touch <root>/FETCH-OFF` parks the unit (it exits 0 with a logged skip); `rm` it to resume.
#
# LICENCE (REPORTED, dataset card + arXiv terms): 20% of papers are CC, 60% arXiv non-exclusive. Personal and
# research use on the house LAN only; nothing under <root> is ever served or re-published.
let
  cfg = config.services.academicIngest.arxivFetch;
  inherit (lib) mkOption mkEnableOption types;
  slug = builtins.replaceStrings [ "/" ] [ "-" ] cfg.dataset;
  dest = "${cfg.root}/${slug}/${cfg.revision}";
  includeArgs = lib.concatMapStringsSep " " (p: "--include ${lib.escapeShellArg p}") cfg.includes;
  textArgs = lib.concatMapStringsSep " " (p: "--include ${lib.escapeShellArg p}") cfg.textIncludes;
  script = pkgs.writeShellApplication {
    name = "arxiv-fetch";
    runtimeInputs = [
      pkgs.huggingface-cli
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      root=${lib.escapeShellArg cfg.root}
      dest=${lib.escapeShellArg dest}
      off=${lib.escapeShellArg cfg.killSwitchFile}
      if [ -e "$off" ]; then
        echo "arxiv-fetch: skip: kill switch $off exists"
        exit 0
      fi
      mkdir -p "$dest"
      # hf's own cache and lock files live beside the data, on the pool, never in $HOME.
      export HF_HOME="$root/.hf-home"
      export HF_HUB_DISABLE_TELEMETRY=1
      export HF_HUB_ENABLE_HF_TRANSFER=0
      mkdir -p "$HF_HOME"
      token_file=${lib.escapeShellArg cfg.tokenFile}
      if [ -r "$token_file" ]; then
        HF_TOKEN="$(cat "$token_file")"
        export HF_TOKEN
        echo "arxiv-fetch: authenticated to Hugging Face (rate limit only; the dataset is not gated)"
      else
        echo "arxiv-fetch: no token readable at $token_file; anonymous fetch"
      fi
      stamp="$(date -u +%Y%m%dT%H%M%SZ)"
      receipt="$dest/RECEIPT-$stamp.txt"
      {
        echo "arxiv-fetch $stamp dataset=${cfg.dataset} revision=${cfg.revision} host=$(hostname)"
        echo "phase 1: indexes ${lib.concatStringsSep " " cfg.includes}"
      } > "$receipt"
      # Phase 1: the card, the checksums and the index configs (about 4.4 GB). Small and first, so a
      # search over metadata can start while the text layer is still landing.
      hf download ${lib.escapeShellArg cfg.dataset} --repo-type dataset --revision ${lib.escapeShellArg cfg.revision} \
        ${includeArgs} --local-dir "$dest" 2>&1 | tail -n 20 | tee -a "$receipt"
      # Phase 2: the text layer (50 shards, 70.27 GB). Four workers: the pool is one disk.
      echo "phase 2: text ${lib.concatStringsSep " " cfg.textIncludes}" >> "$receipt"
      hf download ${lib.escapeShellArg cfg.dataset} --repo-type dataset --revision ${lib.escapeShellArg cfg.revision} \
        ${textArgs} --local-dir "$dest" --max-workers ${toString cfg.maxWorkers} 2>&1 | tail -n 20 | tee -a "$receipt"
      # Verify what is present against the dataset's own SHA256SUMS (only files present are checked).
      echo "verify:" >> "$receipt"
      if (cd "$dest" && sha256sum --ignore-missing --quiet -c SHA256SUMS) >> "$receipt" 2>&1; then
        n=$(cd "$dest" && find . -name '*.parquet' | wc -l)
        bytes=$(du -sb "$dest" | cut -f1)
        echo "verified: $n parquet files, $bytes bytes" | tee -a "$receipt"
        echo "$stamp $n $bytes" > "$dest/COMPLETE"
      else
        echo "arxiv-fetch: sha256 verification FAILED; see $receipt" >&2
        rm -f "$dest/COMPLETE"
        exit 1
      fi
    '';
  };
in
{
  options.services.academicIngest.arxivFetch = {
    enable = mkEnableOption "arxiv-fetch: pull a pinned revision of the arXiv-complete text corpus onto the NAS pool";
    dataset = mkOption {
      type = types.str;
      default = "secemp9/arxiv-complete";
    };
    revision = mkOption {
      type = types.strMatching "[0-9a-f]{40}";
      description = "The Hub revision sha to pin. main can move (an open PR proposes deleting a shard), so never a branch name.";
    };
    root = mkOption {
      type = types.str;
      default = "/mnt/nas/documents/academic-papers/arxiv";
      description = "On the data pool, under documents, so the worker sees it read-only through the existing NFS export.";
    };
    includes = mkOption {
      type = types.listOf types.str;
      default = [
        "README.md"
        "LICENSE"
        "SHA256SUMS"
        ".gitattributes"
        "metadata/*"
        "versions/*"
        "files/*"
        "sample/*"
      ];
      description = "Phase 1 include globs (the card, checksums and index configs, about 4.4 GB).";
    };
    textIncludes = mkOption {
      type = types.listOf types.str;
      default = [ "paper_text/*" ];
      description = "Phase 2 include globs (the text layer, 70.27 GB). Never pdf/*, source/* or latex/*.";
    };
    maxWorkers = mkOption {
      type = types.ints.positive;
      default = 4;
    };
    tokenFile = mkOption {
      type = types.str;
      default = "/run/agenix/huggingface-token";
    };
    user = mkOption {
      type = types.str;
      default = "tom";
      description = "Owner of the destination tree (the pool's documents tree is tom:users).";
    };
    killSwitchFile = mkOption {
      type = types.str;
      default = "/mnt/nas/documents/academic-papers/arxiv/FETCH-OFF";
    };
    onCalendar = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "null: hand-started only (`systemctl start arxiv-fetch`). A systemd calendar spec adds a timer.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.arxiv-fetch = {
      description = "Fetch the pinned arXiv-complete text corpus from Hugging Face onto the NAS pool";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ cfg.root ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = "users";
        ExecStart = lib.getExe script;
        # 75 GB at the measured 13-63 MB/s is 20-95 min; a stuck fetch becomes a failure, not a zombie.
        TimeoutStartSec = "24h";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };
    systemd.timers.arxiv-fetch = lib.mkIf (cfg.onCalendar != null) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = false;
        AccuracySec = "15min";
      };
    };
  };
}
