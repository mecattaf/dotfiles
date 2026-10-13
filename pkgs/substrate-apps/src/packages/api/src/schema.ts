// The floor's HTTP bodies, described once. The floor (apps/floor) serves them, the OpenAPI document (api.ts) is
// generated from them, and the client (client.ts) decodes every answer with them. Field names are the floor's own
// (engine.ts run(), jobView(), output(), events(); capacity.ts capacityView()).
import { AgentJob } from "@substrate/link/contract.ts"
import { Schema } from "effect"

export { AgentJob }

export const ErrorBody = Schema.Struct({
  error: Schema.Union([Schema.String, Schema.Struct({ code: Schema.String, message: Schema.String })])
}).annotate({ identifier: "ErrorBody", description: "Every refusal: { error: { code, message } }, or { error: \"Unauthorized\" } at the door." })
export type ErrorBody = typeof ErrorBody.Type

export const JobSummary = Schema.Struct({
  name: Schema.String,
  runId: Schema.NullOr(Schema.String),
  kind: Schema.String, // agent | run
  state: Schema.String, // queued | leased | orphaned | done
  attempt: Schema.Number,
  leaseId: Schema.NullOr(Schema.String),
  holder: Schema.NullOr(Schema.String),
  runsOn: Schema.Array(Schema.String),
  cancel: Schema.NullOr(Schema.String),
  result: Schema.NullOr(Schema.String),
  reason: Schema.NullOr(Schema.String),
  supersedes: Schema.Array(Schema.String),
  createdAt: Schema.Number,
  doneAt: Schema.NullOr(Schema.Number)
}).annotate({ identifier: "JobSummary" })
export type JobSummary = typeof JobSummary.Type

export const JobView = Schema.Struct({ ...JobSummary.fields, job: Schema.Unknown }).annotate({ identifier: "JobView", description: "A job with its AgentJob body." })
export type JobView = typeof JobView.Type

export const RunView = Schema.Struct({
  id: Schema.String,
  kind: Schema.String, // script | jobs
  name: Schema.NullOr(Schema.String),
  meta: Schema.Unknown,
  args: Schema.Unknown,
  scriptSha256: Schema.NullOr(Schema.String),
  state: Schema.String, // running | done
  result: Schema.NullOr(Schema.String),
  createdAt: Schema.Number,
  doneAt: Schema.NullOr(Schema.Number),
  jobs: Schema.Record(Schema.String, Schema.Number),
  interpreter: Schema.NullOr(JobView)
}).annotate({ identifier: "RunView" })
export type RunView = typeof RunView.Type

export const JobOutput = Schema.Struct({
  result: Schema.String, attempt: Schema.Number, leaseId: Schema.String,
  output: Schema.Unknown, usage: Schema.Unknown, bytes: Schema.Number
}).annotate({ identifier: "JobOutput", description: "A job's recorded verdict and output." })
export type JobOutput = typeof JobOutput.Type

export const TranscriptPart = Schema.Struct({
  part: Schema.String, sha256: Schema.NullOr(Schema.String), bytes: Schema.Number, chunks: Schema.Number,
  committed: Schema.Boolean, committedAt: Schema.NullOr(Schema.Number)
}).annotate({ identifier: "TranscriptPart", description: "One part of a job's harness transcript (AUDIT-transcripts TX2): sealed by a sha256 commit." })
export type TranscriptPart = typeof TranscriptPart.Type
export const TranscriptManifest = Schema.Struct({ name: Schema.String, parts: Schema.Array(TranscriptPart) })
  .annotate({ identifier: "TranscriptManifest", description: "A job's stored transcript parts." })
export type TranscriptManifest = typeof TranscriptManifest.Type
export const TranscriptCommit = Schema.Struct({ sha256: Schema.String, bytes: Schema.Number, chunks: Schema.Number })
  .annotate({ identifier: "TranscriptCommit", description: "What an uploader says the assembled part is; the floor checks it." })

export const FloorEvent = Schema.Struct({
  seq: Schema.Number, run_id: Schema.NullOr(Schema.String), name: Schema.String, lease_id: Schema.NullOr(Schema.String),
  attempt: Schema.Number, result: Schema.String, reason: Schema.NullOr(Schema.String), at_ms: Schema.Number
}).annotate({ identifier: "FloorEvent", description: "One row of the verdict outbox." })
export type FloorEvent = typeof FloorEvent.Type

export const ScriptSubmit = Schema.Struct({
  script: Schema.String.annotate({ description: "An ultracode workflow script whose `export const meta` is a pure literal." }),
  args: Schema.optionalKey(Schema.Unknown),
  id: Schema.optionalKey(Schema.String.annotate({ description: "6 to 40 lowercase letters or digits; makes the submit idempotent." })),
  priority: Schema.optionalKey(Schema.Number.annotate({ description: "0 build, 1 normal (the default), 2 routine; runs and their jobs lease in (priority, seq) order." })),
  project: Schema.optionalKey(Schema.String.annotate({ description: "With thread: the project whose thread the run's end is reported to." })),
  thread: Schema.optionalKey(Schema.String.annotate({ description: "With project: the thread the run's end is reported to (\"\" for the project's top level)." }))
}).annotate({ identifier: "ScriptSubmit" })
export const JobsSubmit = Schema.Struct({
  jobs: Schema.Array(AgentJob),
  name: Schema.optionalKey(Schema.String),
  id: Schema.optionalKey(Schema.String)
}).annotate({ identifier: "JobsSubmit" })
export const SubmitRequest = Schema.Union([ScriptSubmit, JobsSubmit]).annotate({ identifier: "SubmitRequest" })
export type SubmitRequest = typeof SubmitRequest.Type
export const SubmitReply = Schema.Struct({ run: RunView, created: Schema.Boolean }).annotate({ identifier: "SubmitReply" })
export type SubmitReply = typeof SubmitReply.Type

export const Enqueued = Schema.Struct({ enqueued: Schema.Array(Schema.Struct({ enqueued: Schema.Boolean, name: Schema.String })) })
export type Enqueued = typeof Enqueued.Type

export const SeatView = Schema.Struct({
  seat: Schema.String, host: Schema.String, published_at: Schema.String, received_at: Schema.String,
  provider: Schema.Unknown, dispatchable: Schema.Unknown, dispatchable_reason: Schema.Unknown,
  grade: Schema.String, staleness: Schema.String, age_seconds: Schema.NullOr(Schema.Number),
  headroom_pct: Schema.NullOr(Schema.Number), next_reset_at: Schema.NullOr(Schema.String), wip: Schema.Number,
  reading: Schema.Unknown, lapses: Schema.Unknown, plan_lapses_at: Schema.Unknown, admit: Schema.Unknown
}).annotate({ identifier: "SeatView" })
export type SeatView = typeof SeatView.Type
export const CapacityView = Schema.Struct({
  as_of: Schema.String,
  job: Schema.Struct({ model: Schema.NullOr(Schema.String), min_headroom_pct: Schema.Number }),
  seats: Schema.Array(SeatView),
  next_transition_at: Schema.NullOr(Schema.String)
}).annotate({ identifier: "CapacityView" })
export type CapacityView = typeof CapacityView.Type
export const AdmitAnswer = Schema.Record(Schema.String, Schema.Unknown).annotate({ identifier: "AdmitAnswer" })

export const Holder = Schema.Struct({
  holder: Schema.String,
  paused: Schema.Boolean,
  live: Schema.Boolean.annotate({ description: "A session renewed within three heartbeat intervals." }),
  sessionUntil: Schema.NullOr(Schema.Number),
  leased: Schema.Number,
  labels: Schema.Array(Schema.String).annotate({ description: "The runs-on labels of the jobs it holds now." }),
  lastLeaseAt: Schema.NullOr(Schema.Number)
}).annotate({ identifier: "Holder", description: "A puller or link: anything that leases over /rpc." })
export type Holder = typeof Holder.Type

export const FloorState = Schema.Struct({ stats: Schema.Unknown, runWip: Schema.Unknown, alarm: Schema.Unknown, config: Schema.Unknown,
  schema_version: Schema.optionalKey(Schema.Number.annotate({ description: "The last FLOOR_MIGRATIONS version applied to the floor's SQLite." })) })
export type FloorState = typeof FloorState.Type

// ---------------------------------------------------------------- sessions chapter (2026-10-12): agent sessions and the clock
// Field names are the floor's own and Claude's (EXCHANGE section 7): times are ISO 8601 UTC strings.
export const PostTurnSummary = Schema.Struct({
  title: Schema.String, description: Schema.optionalKey(Schema.String),
  status_category: Schema.String.annotate({ description: "need_input, in_progress or completed; failed is written by the floor only, for a turn that ended with no valid summary." }),
  status_detail: Schema.String, needs_action: Schema.String, recent_action: Schema.String, is_noteworthy: Schema.Boolean
}).annotate({ identifier: "PostTurnSummary", description: "What a session answers at the end of each turn." })
export type PostTurnSummary = typeof PostTurnSummary.Type
export const SessionUsage = Schema.Struct({
  input_tokens: Schema.Number, output_tokens: Schema.Number, cache_read_tokens: Schema.Number, cache_write_tokens: Schema.Number, cost_usd: Schema.Number
}).annotate({ identifier: "SessionUsage", description: "Cumulative over the session's completed turns; a count the harness does not report counts 0." })
export type SessionUsage = typeof SessionUsage.Type
export const SessionView = Schema.Struct({
  id: Schema.String, project: Schema.String,
  thread: Schema.String.annotate({ description: "T-<n>, or \"\" for the project's coordinator." }),
  harness: Schema.NullOr(Schema.String).annotate({ description: "Pinned by the first turn from the model's catalog entry; null before." }),
  harness_session_id: Schema.String.annotate({ description: "The harness's own session id, resumed on every turn." }),
  model: Schema.String, effort: Schema.NullOr(Schema.String), cwd: Schema.NullOr(Schema.String),
  worker_status: Schema.String.annotate({ description: "idle, queued (a turn run waits for a slot) or running." }),
  post_turn_summary: Schema.NullOr(PostTurnSummary), usage: Schema.NullOr(SessionUsage),
  transcript: Schema.NullOr(Schema.String).annotate({ description: "The harness session file's path on the host that ran the turns." }),
  turn: Schema.Number.annotate({ description: "Completed turns; a failed turn does not advance it." }),
  stopped: Schema.Boolean, created_at: Schema.String, last_event_at: Schema.String
}).annotate({ identifier: "SessionView", description: "One agent session: a project's coordinator, a thread's session or a routine's." })
export type SessionView = typeof SessionView.Type
export const SessionPatch = Schema.Struct({ model: Schema.optionalKey(Schema.String), effort: Schema.optionalKey(Schema.String) })
  .annotate({ identifier: "SessionPatch", description: "The next turn uses them; the harness never changes." })
export type SessionPatch = typeof SessionPatch.Type

export const TriggerView = Schema.Struct({
  id: Schema.String.annotate({ description: "trig_ and 16 hex characters." }),
  name: Schema.NullOr(Schema.String), project: Schema.String,
  kind: Schema.String.annotate({ description: "routine or send_later." }),
  thread: Schema.String, persistent_session_id: Schema.NullOr(Schema.String), prompt: Schema.NullOr(Schema.String),
  cron_expression: Schema.NullOr(Schema.String), timezone: Schema.NullOr(Schema.String), message: Schema.NullOr(Schema.String),
  run_at: Schema.NullOr(Schema.String), enabled: Schema.Boolean, suspension_reason: Schema.NullOr(Schema.String),
  next_run_at: Schema.NullOr(Schema.String), last_run_at: Schema.NullOr(Schema.String), creator: Schema.NullOr(Schema.String), created_at: Schema.String
}).annotate({ identifier: "TriggerView", description: "A routine (cron_expression in timezone, firing prompt into persistent_session_id) or a send_later (message at run_at)." })
export type TriggerView = typeof TriggerView.Type
export const RoutineCreate = Schema.Struct({
  kind: Schema.Literal("routine"), project: Schema.String, thread: Schema.String, persistent_session_id: Schema.String, prompt: Schema.String,
  cron_expression: Schema.String.annotate({ description: "Five fields: minute hour day-of-month month day-of-week." }),
  timezone: Schema.optionalKey(Schema.String.annotate({ description: "An IANA zone; Europe/Paris by default." })),
  enabled: Schema.optionalKey(Schema.Boolean), creator: Schema.String, name: Schema.optionalKey(Schema.String)
}).annotate({ identifier: "RoutineCreate" })
export const SendLaterCreate = Schema.Struct({
  kind: Schema.Literal("send_later"), project: Schema.String, thread: Schema.String, message: Schema.String,
  run_at: Schema.String.annotate({ description: "ISO 8601 with an offset or Z." }), creator: Schema.String
}).annotate({ identifier: "SendLaterCreate" })
export const TriggerCreate = Schema.Union([RoutineCreate, SendLaterCreate]).annotate({ identifier: "TriggerCreate" })
export type TriggerCreate = typeof TriggerCreate.Type
export const TriggerPatch = Schema.Struct({
  enabled: Schema.optionalKey(Schema.Boolean), prompt: Schema.optionalKey(Schema.String), cron_expression: Schema.optionalKey(Schema.String),
  timezone: Schema.optionalKey(Schema.String), name: Schema.optionalKey(Schema.String)
}).annotate({ identifier: "TriggerPatch" })
export type TriggerPatch = typeof TriggerPatch.Type
export const Health = Schema.Struct({ ok: Schema.Boolean, commit: Schema.NullOr(Schema.String) })
  .annotate({ identifier: "Health", description: "The deployed git sha (var BUILD_COMMIT), null when the deploy set none." })
export type Health = typeof Health.Type
