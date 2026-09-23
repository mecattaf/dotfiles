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

export const FloorEvent = Schema.Struct({
  seq: Schema.Number, run_id: Schema.NullOr(Schema.String), name: Schema.String, lease_id: Schema.NullOr(Schema.String),
  attempt: Schema.Number, result: Schema.String, reason: Schema.NullOr(Schema.String), at_ms: Schema.Number
}).annotate({ identifier: "FloorEvent", description: "One row of the verdict outbox." })
export type FloorEvent = typeof FloorEvent.Type

export const ScriptSubmit = Schema.Struct({
  script: Schema.String.annotate({ description: "An ultracode workflow script whose `export const meta` is a pure literal." }),
  args: Schema.optionalKey(Schema.Unknown),
  id: Schema.optionalKey(Schema.String.annotate({ description: "6 to 40 lowercase letters or digits; makes the submit idempotent." }))
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

export const FloorState = Schema.Struct({ stats: Schema.Unknown, runWip: Schema.Unknown, alarm: Schema.Unknown, config: Schema.Unknown })
export type FloorState = typeof FloorState.Type
