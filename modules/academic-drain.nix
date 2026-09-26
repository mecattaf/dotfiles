{
  config,
  lib,
  pkgs,
  ...
}:
# services.academicDrain.standing: lane B of the academic OCR drain, standing on the substrate (conwip) floor.
# Declared ON on the coordinator since 2026-09-25.
#
# RULING. Tom, 2026-09-25 17:51Z: "it would be better to have the changes made durable, in dotfiles through
# PR's. that way the academic ocr task drain is "permamnently" registered on the factory floor". Registered here
# means: every night at `onCalendar` a user timer submits ~/mecattaf/academic-drain/ocr.substrate.workflow.js to
# the floor under the per-night run id acadlb<YYYYMMDD>, with `args` plus day = today. The shared receipt root
# (<out>/ledger.jsonl on the worker) makes each night resume where the last stopped, and the run id is an
# idempotency key: the same id with the same script sha256 and args answers created:false, the same id with other
# work answers 409 (apps/floor/src/link/floor-object.ts:317-329), so a second fire on one day is harmless.
#
# CONTRACT: ~/mecattaf/academic-drain/tools/standing-submit.md (academic-drain 6f48c46, written in parallel on
# 2026-09-25). This module follows it except where noted: the script is read from the checkout at fire time, not
# a pinned store path (that repo has no remote, so it cannot be a flake input); an unreachable floor or worker is
# a unit failure (exit 1, nothing submitted) rather than a logged skip; /runs is read with limit=500, not 50.
#
# THE SKIP RULES (standing-submit logs `skip: <rule>: <evidence>` and exits 0 when any holds; it exits non-zero
# only on a real error: no credential, no workflow file, the floor or the worker unreachable, a 409 or another
# refusal; it never submits without evaluating every rule):
#   1. the kill-switch file exists on this box (killSwitchFile; `touch` it to park the drain, `rm` to resume);
#   2. substrate-puller is not active in this user manager (a switch or a stop in progress), or the RUNNING puller
#      does not permit args.runtime: its runtimes file (named by [puller].runtimes of the SUBSTRATE_CLIENT_CONFIG
#      in its /proc environ, else AX_CONWIP_RUNTIMES) lacks it on allow. The contract's "must not enable the timer
#      before the runtime is live": a switch that renders ssh:worker does not by itself restart the puller;
#   3. GET <floorUrl>/runs?limit=500 lists a run named academic-drain-lane-b (its meta.name) whose state is not
#      done, failed or cancelled (RunView, packages/api/src/schema.ts:35-48; the floor's states are running and
#      done);
#   4. the sticky STOP file exists on the worker (<out>/STOP or args.stop_file): a person reads it and clears it
#      with `lane_b_batch.py clear-stop`; the timer never does;
#   5. <out>/.lane-b.lock is held on the worker (a lane_b_batch.py run is in progress: lane_b_batch.py:361-365);
#   6. the newest of <out>/batches/*.json and <out>/NIGHT-*.md says lane B is exhausted: a batch summary with
#      stopped = "exhausted" or pending_after = 0 (lane_b_batch.py:517-518) or a night receipt whose "deferred
#      pages still pending" row is 0. pending() skips failure rows and keeps a pdf-missing page out until its PDF
#      resolves (lane_b_batch.py:302-313), so exhausted means only such pages are left. Sticky by design: a
#      person resubmits by hand (or runs one batch) once PDFs resolve.
# The floor is read before the worker, and the lock is probed last, so while a drain run is in flight the probe
# never touches the lock. The probe opens the lock read-only (no O_CREAT) and holds it for the life of one
# flock(1) process; a lane_b_batch.py starting in that same instant would stop on 'locked' (LOCK_NB, INFERRED
# negligible outside a hand run, since rule 3 already excludes a floor run).
#
# RUN IT NOW: `systemctl --user start academic-drain-standing.service` (then `journalctl --user -u
# academic-drain-standing`). DRY RUN (prints the decision and the would-be POST body with the script elided to its
# sha256, sends nothing; still reads the floor and ssh-probes the worker):
#   "$(systemctl --user cat academic-drain-standing.service | sed -n 's/^ExecStart=//p')" --dry-run \
#     --token-file ~/.local/state/substrate/floor-token
#
# ARGS go out in the contract's fixed key order (day, deferred, out, max_pages, batch_size, runtime, any other key
# sorted, stop_before last): the floor's idempotency check compares JSON.stringify of the args, which is key-order
# sensitive (floor-object.ts:321-328), so a hand submit in that order and the timer agree.
#
# THE TOKEN IS A PATH, NEVER A VALUE: the floor's operator bearer (the agenix secret modules/substrate.nix
# declares for services.substrate.tokenSecret) reaches the unit by LoadCredential, as for the puller; the script
# reads it into a curl header through a process substitution, so it is never in argv, on disk or in the journal.
#
# RUNTIME. args.runtime = "ssh:worker" puts lane B's pi on the worker through the ssh runner
# (services.substrate.puller.sshRuntimes, hosts/coordinator); an assertion requires the runtime on the puller's
# allow list. NOT HERE: a puller on the worker (a puller leases runs, and runs cannot be targeted:
# apps/floor/src/link/intake.ts:94, engine.ts:479-485) and the k3s/ax path (ax Tasks carry no volumes).
let
  cfg = config.services.academicDrain.standing;
  sub = config.services.substrate;
  inherit (lib) mkEnableOption mkOption types;
  home = config.users.users.${cfg.user}.home;
  # ocr.substrate.workflow.js refuses anything else in a path (it is quoted into a remote shell).
  pathRe = "[A-Za-z0-9_./~@:+-]+";
  out = cfg.args.out or "";
  stopFile = cfg.args.stop_file or "${out}/STOP";
  argsOrder = [
    "deferred"
    "out"
    "max_pages"
    "batch_size"
    "runtime"
  ];
  argKeys =
    builtins.filter (k: cfg.args ? ${k}) argsOrder
    ++ lib.subtractLists (argsOrder ++ [ "stop_before" ]) (builtins.attrNames cfg.args)
    ++ lib.optional (cfg.args ? stop_before) "stop_before";
  # day is prepended at fire time ({day} + this, in jq, which keeps key order).
  argsJson = pkgs.writeText "academic-drain-standing-args.json" (
    "{"
    + lib.concatMapStringsSep "," (k: "${builtins.toJSON k}:${builtins.toJSON cfg.args.${k}}") argKeys
    + "}"
  );

  standingSubmit = pkgs.writeShellApplication {
    name = "academic-drain-standing-submit";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.openssh
      pkgs.python3
      pkgs.systemd
    ];
    text = ''
      floor=${lib.escapeShellArg cfg.floorUrl}
      workflow=${lib.escapeShellArg cfg.workflowFile}
      worker=${lib.escapeShellArg cfg.worker}
      kill_switch=${lib.escapeShellArg cfg.killSwitchFile}
      # Paths ON THE WORKER, kept as written: a leading ~ is expanded there, by the probe below.
      # shellcheck disable=SC2088
      out=${lib.escapeShellArg out}
      # shellcheck disable=SC2088
      stop_file=${lib.escapeShellArg stopFile}
      run_name=${lib.escapeShellArg cfg.runName}
      args_file=${argsJson}

      dry=0
      token_file="''${CREDENTIALS_DIRECTORY:-}/floor-token"
      while [ $# -gt 0 ]; do
        case "$1" in
          --dry-run) dry=1; shift ;;
          --token-file) token_file="$2"; shift 2 ;;
          *) echo "usage: academic-drain-standing-submit [--dry-run] [--token-file PATH]" >&2; exit 64 ;;
        esac
      done

      log() { printf 'academic-drain-standing: %s\n' "$*"; }
      skip() { log "skip: $*"; exit 0; }
      fail() { log "ERROR: $*" >&2; exit 1; }
      auth() { printf 'authorization: Bearer %s\n' "$(<"$token_file")"; }

      day="$(date +%F)"
      id="acadlb''${day//-/}"
      mode=""
      if [ "$dry" = 1 ]; then mode=" (dry run: nothing is sent)"; fi
      log "day $day, run id $id, floor $floor, worker $worker$mode"

      # 1. The kill switch on this box.
      [ -e "$kill_switch" ] && skip "kill-switch: $kill_switch exists"

      # 2. The puller that would run the drain.
      systemctl --user is-active --quiet substrate-puller.service ||
        skip "puller-inactive: substrate-puller.service is not active in this user manager"
      runtime="$(jq -r '.runtime // empty' "$args_file")"
      if [ -n "$runtime" ]; then
        pid="$(systemctl --user show -P MainPID substrate-puller.service)"
        rc=0
        live="$(python3 - "$pid" "$runtime" <<'PY'
      import sys, tomllib
      pid, want = sys.argv[1], sys.argv[2]
      env = dict(kv.split("=", 1) for kv in open(f"/proc/{pid}/environ", "rb").read().decode().split("\0") if "=" in kv)
      path = None
      if env.get("SUBSTRATE_CLIENT_CONFIG"):
          try:
              path = tomllib.load(open(env["SUBSTRATE_CLIENT_CONFIG"], "rb")).get("puller", {}).get("runtimes")
          except OSError:
              path = None
      path = path or env.get("AX_CONWIP_RUNTIMES")
      if not path:
          print(f"puller pid {pid} names no runtimes file")
          sys.exit(2)
      rt = tomllib.load(open(path, "rb"))
      ok = want in rt["allow"] if "allow" in rt else want in rt.get("runtime", {})
      print(f"the running puller (pid {pid}) reads {path}, which {'permits' if ok else 'does not permit'} {want}")
      sys.exit(0 if ok else 3)
      PY
      )" || rc=$?
        case "$rc" in
          0) log "puller: $live" ;;
          3) skip "runtime-not-live: $live (live only once the puller restarts on a generation that declares it)" ;;
          *) fail "cannot read the running puller's runtimes (rc $rc): $live" ;;
        esac
      fi

      # 3. A lane B run already on the floor.
      [ -r "$token_file" ] || fail "no floor token at $token_file (LoadCredential floor-token, or --token-file)"
      runs="$(curl -fsS -m 30 -H @<(auth) "$floor/runs?limit=500")" || fail "GET $floor/runs failed"
      inflight="$(jq -r --arg n "$run_name" \
        '[.runs[] | select(.name == $n and ((.state | IN("done", "failed", "cancelled")) | not)) | "\(.id) (\(.state))"] | join(" ")' \
        <<<"$runs")" || fail "GET /runs answered an unparseable body"
      [ -n "$inflight" ] && skip "run-in-flight: $run_name not finished on the floor: $inflight"

      # 4-6. The worker: sticky STOP, the lane-b lock, exhaustion. One ssh; exit 10/11/13 = skip, 0 = go.
      rc=0
      probe="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$worker" bash -s -- "$(printf %q "$out")" "$(printf %q "$stop_file")" <<'REMOTE'
      set -u
      out=''${1/#\~/$HOME}
      stop=''${2/#\~/$HOME}
      if [ -e "$stop" ]; then
        echo "stop-file: sticky STOP file $stop exists (a person clears it: lane_b_batch.py clear-stop): $(head -c 300 "$stop" | tr '\n' ' ')"
        exit 10
      fi
      lock=$out/.lane-b.lock
      if [ -e "$lock" ]; then
        # Read-only open through the shell: flock(1) given a path would create a missing file.
        flock -n -E 75 9 9<"$lock"
        rc=$?
        if [ "$rc" = 75 ]; then echo "lane-b-lock: $lock is held: a lane_b_batch.py run is in progress"; exit 11; fi
        if [ "$rc" != 0 ]; then echo "flock on $lock failed with rc $rc"; exit 12; fi
      fi
      newest=$(ls -1t "$out"/batches/*.json "$out"/NIGHT-*.md 2>/dev/null | head -n 1)
      case "$newest" in
        "") echo "no batch summary or night receipt under $out yet"; exit 0 ;;
        *.json)
          if ! stopped=$(python3 -c 'import json, sys; j = json.load(open(sys.argv[1])); print(j.get("stopped"), j.get("pending_after"))' "$newest"); then
            echo "unparseable batch summary $newest"; exit 12
          fi
          case "$stopped" in
            "exhausted "* | *" 0") echo "exhausted: lane B is exhausted: $newest says stopped pending_after = $stopped"; exit 13 ;;
          esac
          echo "newest $newest: stopped pending_after = $stopped"; exit 0 ;;
        *.md)
          if grep -q '^| deferred pages still pending | 0 |$' "$newest"; then
            echo "exhausted: lane B is exhausted: $newest has 0 deferred pages pending"; exit 13
          fi
          echo "newest $newest: pages still pending"; exit 0 ;;
      esac
      REMOTE
      )" || rc=$?
      case "$rc" in
        0) log "worker: $probe" ;;
        10 | 11 | 13) skip "$probe" ;;
        255) fail "ssh $worker failed (unreachable or refused): $probe" ;;
        *) fail "worker probe rc $rc: $probe" ;;
      esac

      # Submit: {id, script, args + day}. The floor keys idempotency on id + script sha256 + args.
      [ -r "$workflow" ] || fail "no workflow file at $workflow"
      body="$(jq -n --rawfile script "$workflow" --slurpfile args "$args_file" --arg day "$day" --arg id "$id" \
        '{id: $id, script: $script, args: ({day: $day} + $args[0])}')"
      if [ "$dry" = 1 ]; then
        sha="$(sha256sum "$workflow" | cut -d' ' -f1)"
        log "DRY RUN: would POST $floor/runs with:"
        jq -c --arg sha "$sha" '.script |= "<\(length) chars, sha256 \($sha)>"' <<<"$body"
        exit 0
      fi
      reply="$(curl -sS -m 60 -X POST -H @<(auth) -H 'content-type: application/json' --data-binary @- \
        -w '\n%{http_code}' "$floor/runs" <<<"$body")" || fail "POST $floor/runs: curl failed"
      code="''${reply##*$'\n'}"
      reply="''${reply%$'\n'*}"
      case "$code" in
        2??) log "submitted: $(jq -c '{id: .run.id, created, name: .run.name, state: .run.state, scriptSha256: .run.scriptSha256}' <<<"$reply" 2>/dev/null || printf '%s' "''${reply:0:500}")" ;;
        409) fail "409: run $id exists with other work (the workflow file or args changed since today's submit): ''${reply:0:500}" ;;
        *) fail "POST /runs answered $code: ''${reply:0:500}" ;;
      esac
    '';
  };
in
{
  options.services.academicDrain.standing = {
    enable = mkEnableOption "the standing academic OCR drain: a nightly, idempotent lane B submit to the substrate floor (see this file's header)";

    user = mkOption {
      type = types.str;
      default = config.services.substrate.user;
      defaultText = lib.literalExpression "config.services.substrate.user";
      description = "The login whose user manager runs the timer (the puller's).";
    };

    workflowFile = mkOption {
      type = types.str;
      default = "/home/tom/mecattaf/academic-drain/ocr.substrate.workflow.js";
      description = "The workflow script submitted each night, read at fire time (the academic-drain repo has no remote, so it is not a flake input). An edit changes its sha256, so a same-day resubmit answers 409.";
    };

    floorUrl = mkOption {
      type = types.str;
      default = sub.floorUrl;
      defaultText = lib.literalExpression "config.services.substrate.floorUrl";
      description = "The floor's base URL (HTTPS).";
    };

    onCalendar = mkOption {
      type = types.str;
      default = "*-*-* 01:30:00";
      description = "When the timer fires (systemd.time OnCalendar). Persistent = false: a missed night is not caught up.";
    };

    runName = mkOption {
      type = types.str;
      default = "academic-drain-lane-b";
      description = "The workflow's meta.name, which the floor records as the run's name: an unfinished run of this name means skip.";
    };

    args = mkOption {
      type = types.attrsOf (
        types.oneOf [
          types.str
          types.int
          types.bool
        ]
      );
      default = {
        deferred = "~/.local/state/academic-drain/lane-a/deferred.jsonl";
        out = "~/.local/state/academic-drain/lane-b/main";
        max_pages = 1500;
        batch_size = 25;
        runtime = "ssh:worker";
      };
      description = "The workflow's args (ocr.substrate.workflow.js: paths are paths ON THE WORKER), without day, which the script sets to today. Setting this replaces the whole default.";
    };

    worker = mkOption {
      type = types.str;
      default = "worker";
      description = "The ssh destination holding <out> (the skip probes run there).";
    };

    killSwitchFile = mkOption {
      type = types.str;
      default = "${home}/.local/state/academic-drain/STANDING-OFF";
      defaultText = lib.literalExpression ''"''${home}/.local/state/academic-drain/STANDING-OFF"'';
      description = "While this file exists on this box, the timer submits nothing.";
    };

    submitScript = mkOption {
      type = types.package;
      readOnly = true;
      default = standingSubmit;
      description = "The rendered standing-submit script (read-only; for tests and dry runs).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = sub.puller.enable;
        message = "services.academicDrain.standing needs services.substrate.puller on this host: the puller runs the drain and its module declares the floor-token secret.";
      }
      {
        assertion = lib.hasPrefix "https://" cfg.floorUrl;
        message = "services.academicDrain.standing.floorUrl must be https:// (the bearer never travels in clear).";
      }
      {
        assertion = cfg.args ? out && cfg.args ? deferred && !(cfg.args ? day);
        message = "services.academicDrain.standing.args needs out and deferred, and no day (the script sets it).";
      }
      {
        assertion =
          builtins.all (k: !(cfg.args ? ${k}) || builtins.match pathRe (toString cfg.args.${k}) != null)
            [
              "out"
              "deferred"
              "stop_file"
              "bin"
              "pdf_stage"
              "adopt_from"
            ];
        message = "services.academicDrain.standing.args: a path may carry only ${pathRe} (ocr.substrate.workflow.js quotes it into a remote shell).";
      }
      {
        assertion =
          !(cfg.args ? runtime) || builtins.elem cfg.args.runtime (sub.puller.runtimes.allow or [ ]);
        message = "services.academicDrain.standing.args.runtime = ${
          toString (cfg.args.runtime or "")
        } is not on services.substrate.puller.runtimes.allow: the puller would refuse every node.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.killSwitchFile;
        message = "services.academicDrain.standing.killSwitchFile must be an absolute path.";
      }
    ];

    systemd.user.services.academic-drain-standing = {
      description = "academic-drain-standing: submit tonight's lane B run to the substrate floor unless a skip rule holds";
      unitConfig.ConditionUser = cfg.user;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe standingSubmit;
        LoadCredential = [ "floor-token:${config.age.secrets.${sub.tokenSecret}.path}" ];
        UMask = "0077";
        NoNewPrivileges = true;
        TimeoutStartSec = "5min";
      };
    };

    systemd.user.timers.academic-drain-standing = {
      description = "academic-drain-standing: the nightly lane B submit";
      wantedBy = [ "timers.target" ];
      unitConfig.ConditionUser = cfg.user;
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = false;
      };
    };
  };
}
