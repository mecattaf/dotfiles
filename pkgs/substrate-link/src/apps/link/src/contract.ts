// The floor <-> link wire contract (LINK-DESIGN.md section 3). Starting point: the option-A prototype
// (/home/tom/today/evals-2026-09-23/arc/proto/contract.ts, decision L1). Every L1 name is kept as it was.
// Five keys are ADDED, each optional so an L1-only peer ignores them, each named after its source:
//   Grant.supersedes   L3 (two-stage expiry): the old attempt the link must DeleteTask first
//   Grant.leaseToken   L7 (completion before ax P1): a per-lease token for the guest (Buildkite job token)
//   Grant.deadline     Temporal start-to-close, as an absolute epoch ms the link can hold across a restart
//   Lease.endpoint     Buildkite ping `endpoint`: move the link to a new floor URL after a test call
//   Complete.withdrew  round 2: the leaseId of attempt n+1 that rule 4b withdrew when it accepted attempt n's verdict.
//                      The link releases n+1 only when it is named here; it never infers a withdrawal (a duplicate
//                      answer or a delivered retryable failure withdrew nothing)
//   Complete.withdrewTransitions  round 3: the leaseTransitions of the generation rule 4b withdrew. A floor that
//                      requeues the withdrawn attempt under the same leaseId grants it again with a higher value; the
//                      link treats a grant as withdrawn only when its generation matches
// Nothing here is GitHub-hosted at runtime.
import { Schema } from "effect"
import { Rpc, RpcGroup } from "effect/unstable/rpc"

// Actions job result values (GitHub/Gitea job `result`).
export const Result = Schema.Literals(["success", "failure", "cancelled", "skipped"])
export type Result = typeof Result.Type

// ---- AgentJob: an ultracode agent() node as an Actions-style job in a Kubernetes object envelope (unchanged) ----
const Labels = Schema.Record(Schema.String, Schema.String)
export const PromptRef = Schema.Struct({
  sha256: Schema.String, // content address; the guest refuses on mismatch (FIELD-MAP 5a AX_CONWIP_PROMPT_SHA256)
  bytes: Schema.Int,
  uri: Schema.String // journal://<runId>/<index>/prompt.md
})
export const AgentJob = Schema.Struct({
  apiVersion: Schema.Literal("ultracode.mecattaf.dev/v1alpha1"),
  kind: Schema.Literal("AgentJob"),
  metadata: Schema.Struct({ name: Schema.String, labels: Schema.optionalKey(Labels), annotations: Schema.optionalKey(Labels) }),
  spec: Schema.Struct({
    // CONWIP admission key, e.g. ["seat:halogen","runtime:gvisor"]. B7 asked for Schema.NonEmptyArray here; it stays
    // Array on the wire because one malformed job would then fail the decode of a whole Lease reply and strand every
    // grant in it (INFERRED). The link refuses it per job instead (`validRunsOn`, jobs.ts), and the floor at enqueue.
    "runs-on": Schema.Array(Schema.String),
    "timeout-minutes": Schema.optionalKey(Schema.Int), // Temporal start-to-close, enforced by the floor
    "continue-on-error": Schema.optionalKey(Schema.Boolean),
    environment: Schema.optionalKey(Schema.NullOr(Schema.String)), // Tom's ack gate
    with: Schema.Struct({
      prompt: Schema.optionalKey(Schema.String),
      prompt_ref: PromptRef,
      model: Schema.String,
      effort: Schema.optionalKey(Schema.String),
      schema: Schema.optionalKey(Schema.Unknown),
      isolation: Schema.optionalKey(Schema.String),
      "agent-type": Schema.optionalKey(Schema.String)
    }),
    needs: Schema.optionalKey(Schema.Record(Schema.String, Schema.Struct({ result: Result, outputs_ref: Schema.String }))),
    outputs: Schema.optionalKey(Schema.Array(Schema.String))
  })
})
export type AgentJob = typeof AgentJob.Type

// ---- ax Task JSON (protojson camelCase of ax.proto v0.3.0 d8ed0fe). The link emits it; it never rides the wire ----
// apiVersion is ax's own constant `ax.io/v1alpha1` (ax pkg/apis/v1alpha1/types.go:31); the prototype's
// `ax/v1alpha1` passed only because ax stores what it is given.
export const AxTask = Schema.Struct({
  apiVersion: Schema.Literal("ax.io/v1alpha1"),
  kind: Schema.Literal("Task"),
  metadata: Schema.Struct({ name: Schema.String, atespace: Schema.String }),
  spec: Schema.Struct({
    image: Schema.String,
    command: Schema.Array(Schema.String),
    env: Schema.Array(Schema.Struct({ name: Schema.String, value: Schema.String })),
    gateway: Schema.optionalKey(Schema.Struct({ name: Schema.String }))
  })
})
export type AxTask = typeof AxTask.Type

// ---- the link contract ----
// Kubernetes coordination.k8s.io/v1 LeaseSpec field names.
export const LeaseSpec = Schema.Struct({
  holderIdentity: Schema.String, leaseDurationSeconds: Schema.Int,
  acquireTime: Schema.Number, renewTime: Schema.Number, leaseTransitions: Schema.Int
})
// Absolute counts on every response plus an increasing seq (ARC scaleset statistics).
export const Stats = Schema.Struct({ seq: Schema.Int, cap: Schema.Int, wip: Schema.Int, queued: Schema.Int, done: Schema.Int })
export const Grant = Schema.Struct({
  leaseId: Schema.String, // `<metadata.name>-a<attempt>`; it is also the ax Task name (the idempotency key on ax)
  attempt: Schema.Int,
  job: AgentJob,
  lease: LeaseSpec,
  supersedes: Schema.optionalKey(Schema.Array(Schema.String)), // L3
  leaseToken: Schema.optionalKey(Schema.String), // L7, only while the guest completes (pre-P1)
  deadline: Schema.optionalKey(Schema.Number) // epoch ms; acquireTime + timeout-minutes
})
export type Grant = typeof Grant.Type
export const Usage = Schema.Struct({ prompt_tokens: Schema.Int, completion_tokens: Schema.Int, tool_calls: Schema.Int })
export type Usage = typeof Usage.Type

// Temporal PollActivityTaskQueue + ARC free capacity on every poll + Forgejo request key + Buildkite intervals.
export const Lease = Rpc.make("Lease", {
  payload: { holderIdentity: Schema.String, capacity: Schema.Int, requestKey: Schema.String },
  success: Schema.Struct({
    grants: Schema.Array(Grant), stats: Stats, nextPollSeconds: Schema.Int, heartbeatSeconds: Schema.Int,
    endpoint: Schema.optionalKey(Schema.String) // Buildkite ping endpoint switch
  })
})
// Temporal RecordActivityTaskHeartbeat with cancel_requested, batched per session. `leaseIds` is the COMPLETE set
// the holder believes it holds (level-triggered, ARC): an orphaned lease it omits is requeued (L3 a).
// Round 4: `pendingRequestKey` (Forgejo request key, B8) is the Lease requestKey the holder journaled and has not
// seen answered. The holder cannot list leaseIds it never received, so it vouches for the key instead: the floor
// renews every lease granted under that key and never releases one as an omitted orphan (L3 a) while it is named.
export const Heartbeat = Rpc.make("Heartbeat", {
  payload: { holderIdentity: Schema.String, leaseIds: Schema.Array(Schema.String), pendingRequestKey: Schema.optionalKey(Schema.String) },
  success: Schema.Struct({
    renewed: Schema.Array(Schema.String), lost: Schema.Array(Schema.String),
    cancelRequested: Schema.Array(Schema.String), stats: Stats
  })
})
// Temporal RespondActivityTask{Completed,Failed,Canceled}. The verdict travels here, never as an exit code (ARC).
// The two errors are terminal: stop retrying (Buildkite 422).
export const CompleteError = Schema.Struct({ code: Schema.Literals(["unknown-lease", "stale-attempt"]) })
export const Complete = Rpc.make("Complete", {
  payload: {
    leaseId: Schema.String, attempt: Schema.Int, result: Result,
    output: Schema.optionalKey(Schema.Unknown), usage: Schema.optionalKey(Usage)
  },
  success: Schema.Struct({ duplicate: Schema.Boolean, stats: Stats, withdrew: Schema.optionalKey(Schema.String),
    withdrewTransitions: Schema.optionalKey(Schema.Int) }),
  error: CompleteError
})
export class FloorLink extends RpcGroup.make(Lease, Heartbeat, Complete) {}

// The link's own view of the same wire (round 1, finding "poison grant"): identical tags, payloads and JSON, but each
// grant is decoded by the link one at a time, so one malformed job fails only its own lease (pre-start/invalid-spec)
// instead of turning the whole Lease reply into a decode defect that the journaled requestKey would replay for ever.
// Round 3: the whole envelope is lenient too. A drifted interval (the prototype floor sends leaseMs / 3000, e.g.
// 3.333), a null endpoint or a changed stats shape would otherwise fail the decode of every replay of the journaled
// requestKey and strand the grants in it. The link bounds the intervals itself (link.ts `boundedSeconds`).
export const LeaseLenient = Rpc.make("Lease", {
  payload: { holderIdentity: Schema.String, capacity: Schema.Int, requestKey: Schema.String },
  success: Schema.Struct({
    grants: Schema.Array(Schema.Unknown), stats: Schema.optionalKey(Schema.Unknown),
    nextPollSeconds: Schema.optionalKey(Schema.Unknown), heartbeatSeconds: Schema.optionalKey(Schema.Unknown),
    endpoint: Schema.optionalKey(Schema.Unknown)
  })
})
// Round 2: the link decodes Complete's error code as any string, so a code the floor adds later is a permanent refusal
// (dropped, logged with the code), never a decode defect retried for ever at the head of the outbox.
// Round 3: its success is lenient as well. Any 2xx Exit Success means the floor applied the verdict; a drifted key
// (`withdrew: null`, a missing stats) must not keep an applied verdict at the head of the outbox.
export const CompleteLenient = Rpc.make("Complete", {
  payload: Complete.payloadSchema.fields,
  success: Schema.Struct({ duplicate: Schema.optionalKey(Schema.Unknown), stats: Schema.optionalKey(Schema.Unknown),
    withdrew: Schema.optionalKey(Schema.Unknown), withdrewTransitions: Schema.optionalKey(Schema.Unknown) }),
  error: Schema.Struct({ code: Schema.String })
})
// Round 4: Heartbeat is lenient as well. The strict reply schema turned a drifted `stats` into a heartbeat-error on
// every call, so `cancelRequested`, `lost` and `renewed` were never read while the floor kept renewing (a cancel was
// never carried out, a journaled grant never resumed). Every key is optional Unknown; floor.ts keeps the strings.
export const HeartbeatLenient = Rpc.make("Heartbeat", {
  payload: Heartbeat.payloadSchema.fields,
  success: Schema.Struct({ renewed: Schema.optionalKey(Schema.Unknown), lost: Schema.optionalKey(Schema.Unknown),
    cancelRequested: Schema.optionalKey(Schema.Unknown), stats: Schema.optionalKey(Schema.Unknown) })
})
export class FloorLinkClient extends RpcGroup.make(LeaseLenient, HeartbeatLenient, CompleteLenient) {}

// On result "failure" the link's `output` is this shape (Buildkite finish signal_reason, ARC failure reason).
// The reasons in RETRYABLE are the floor's to retry as attempt+1 (Temporal retry policy, Buildkite finish -1 on a
// pre-start failure); every other reason is final: a deterministic refusal, or the agent's own failure, which goes
// to the interpreter (null-on-failure).
export const FailureOutput = Schema.Struct({
  reason: Schema.String, // pre-start/env-over-budget, pre-start/name-conflict, infra/task-lost, deadline-exceeded, ...
  message: Schema.optionalKey(Schema.String),
  phase: Schema.optionalKey(Schema.String),
  exitCode: Schema.optionalKey(Schema.Int)
})
export type FailureOutput = typeof FailureOutput.Type
export const RETRYABLE = new Set([
  "pre-start/ax-unavailable", "pre-start/pending-timeout", "pre-start/resource-exhausted",
  "infra/task-lost", "infra/actor-crashed", "infra/result-unreadable",
  "pre-start/superseded-verdict-pending", // round 1: n+1 refused while attempt n's verdict could not be delivered
  "infra/link-defect" // round 4: a dispatch fiber died on a defect before the Task was created; the floor requeues
])
// Round 2, final (not in RETRYABLE): `infra/verdict-undeliverable` (the floor answered every delivery of the real
// verdict with a server error; a rerun would most likely produce the same bytes) and `agent/output-too-large` (the
// result is over the link's cap, below the floor's 2 MB row limit).
export const isRetryableReason = (reason: string) => RETRYABLE.has(reason)
