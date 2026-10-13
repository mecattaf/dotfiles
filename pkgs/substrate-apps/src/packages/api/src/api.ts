// The floor's routes as one Effect HttpApi. Nothing serves this definition directly: the floor's own router
// (apps/floor/src/link/floor-object.ts) is the implementation and apps/floor/test/openapi.test.ts holds the two to
// the same route table. What this buys is one description with two outputs: GET /openapi.json (OpenApi.fromApi)
// and the client's decoders (client.ts). /rpc is Effect RPC (Lease, Heartbeat, Complete) and is described in the
// document's info, not as REST paths.
import { Schema } from "effect"
import { HttpApi, HttpApiEndpoint, HttpApiGroup, HttpApiSchema, OpenApi } from "effect/unstable/httpapi"
import * as S from "./schema.ts"

const Id = { id: Schema.String }
const Name = { name: Schema.String }
const errors = [S.ErrorBody]
const doc = <E extends { annotate: (k: never, v: string) => unknown }>(e: E, summary: string, description?: string): E =>
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  { let r: any = (e as any).annotate(OpenApi.Summary, summary); if (description) r = r.annotate(OpenApi.Description, description); return r }

export const RunsGroup = HttpApiGroup.make("runs")
  .add(doc(HttpApiEndpoint.post("submitRun", "/runs", { payload: S.SubmitRequest, success: S.SubmitReply.pipe(HttpApiSchema.status(201)), error: errors }),
    "Submit a run", "A workflow script (JSON { script } or a text/javascript body) or a list of AgentJob. Answers 201 when created, 200 when the id already exists."))
  .add(doc(HttpApiEndpoint.get("listRuns", "/runs", { query: { limit: Schema.optionalKey(Schema.String) }, success: Schema.Struct({ runs: Schema.Array(S.RunView) }), error: errors }), "List runs, newest first"))
  .add(doc(HttpApiEndpoint.get("getRun", "/runs/:id", { params: Id, success: Schema.Struct({ run: S.RunView }), error: errors }), "One run"))
  .add(doc(HttpApiEndpoint.get("runJobs", "/runs/:id/jobs", { params: Id, success: Schema.Struct({ jobs: Schema.Array(S.JobSummary) }), error: errors }), "The jobs of a run"))
  .add(doc(HttpApiEndpoint.post("enqueueRunJobs", "/runs/:id/jobs", { params: Id, payload: Schema.Union([S.AgentJob, Schema.Array(S.AgentJob)]), success: S.Enqueued.pipe(HttpApiSchema.status(201)), error: errors }),
    "Enqueue nodes of a run", "The interpreter host's call: each agent() node as an AgentJob, idempotent by metadata.name."))
  .add(doc(HttpApiEndpoint.get("runScript", "/runs/:id/script", { params: Id, success: Schema.String.pipe(HttpApiSchema.asText({ contentType: "text/javascript" })), error: errors }), "The script of a script run"))
  .add(doc(HttpApiEndpoint.get("runEvents", "/runs/:id/events", { params: Id, query: { after: Schema.optionalKey(Schema.String) }, success: Schema.Struct({ events: Schema.Array(S.FloorEvent) }), error: errors }), "Verdict events of a run"))
  .add(doc(HttpApiEndpoint.post("cancelRun", "/runs/:id/cancel", { params: Id, success: Schema.Struct({ run: S.RunView }), error: errors }), "Cancel a run and every unfinished job in it"))

export const JobsGroup = HttpApiGroup.make("jobs")
  .add(doc(HttpApiEndpoint.get("getJob", "/jobs/:name", { params: Name, success: Schema.Struct({ job: S.JobView }), error: errors }), "One job"))
  .add(doc(HttpApiEndpoint.get("jobOutput", "/jobs/:name/output", { params: Name, success: S.JobOutput, error: errors }), "A job's verdict and output", "404 no-output while the job has no verdict."))
  .add(doc(HttpApiEndpoint.get("jobTranscripts", "/jobs/:name/transcript", { params: Name, success: S.TranscriptManifest, error: errors }), "A job's transcript parts", "The harness transcripts (session file, rollout, stdout and stderr) stored for the job."))
  .add(doc(HttpApiEndpoint.get("jobTranscriptPart", "/jobs/:name/transcript/:part", { params: { name: Schema.String, part: Schema.String }, query: { idx: Schema.optionalKey(Schema.String), partial: Schema.optionalKey(Schema.String) }, success: Schema.String.pipe(HttpApiSchema.asText({ contentType: "text/plain" })), error: errors }), "One transcript part as text", "409 transcript-uncommitted until its commit; ?idx=N reads one chunk, ?partial=1 reads an uncommitted part."))
  .add(doc(HttpApiEndpoint.put("putTranscriptChunk", "/jobs/:name/transcript/:part/:idx", { params: { name: Schema.String, part: Schema.String, idx: Schema.String }, payload: Schema.String.pipe(HttpApiSchema.asText({ contentType: "text/plain" })), success: Schema.Unknown, error: errors }), "Store one transcript chunk", "At most 1 MB per chunk and 32 MB per job (413); 409 once the part is committed."))
  .add(doc(HttpApiEndpoint.post("commitTranscript", "/jobs/:name/transcript/:part/commit", { params: { name: Schema.String, part: Schema.String }, payload: S.TranscriptCommit, success: Schema.Unknown, error: errors }), "Seal a transcript part", "422 sha-mismatch or transcript-incomplete unless bytes, chunk count and sha256 match what is stored."))
  .add(doc(HttpApiEndpoint.post("cancelJob", "/jobs/:name/cancel", { params: Name, success: Schema.Struct({ job: S.JobView }), error: errors }), "Cancel one job"))
  .add(doc(HttpApiEndpoint.get("events", "/events", { query: { after: Schema.optionalKey(Schema.String) }, success: Schema.Struct({ events: Schema.Array(S.FloorEvent) }), error: errors }), "Every verdict event after a sequence number"))

export const HoldersGroup = HttpApiGroup.make("holders")
  .add(doc(HttpApiEndpoint.get("listHolders", "/holders", { success: Schema.Struct({ holders: Schema.Array(S.Holder) }), error: errors }), "Pullers and links known to the floor"))
  .add(doc(HttpApiEndpoint.post("pauseHolder", "/holders/:holder/pause", { params: { holder: Schema.String }, success: Schema.Struct({ holder: Schema.String, paused: Schema.Boolean }), error: errors }), "Stop granting to a holder"))
  .add(doc(HttpApiEndpoint.post("resumeHolder", "/holders/:holder/resume", { params: { holder: Schema.String }, success: Schema.Struct({ holder: Schema.String, paused: Schema.Boolean }), error: errors }), "Grant to a holder again"))

export const CapacityGroup = HttpApiGroup.make("capacity")
  .add(doc(HttpApiEndpoint.get("capacity", "/capacity", { query: { model: Schema.optionalKey(Schema.String), min_headroom_pct: Schema.optionalKey(Schema.String), asOf: Schema.optionalKey(Schema.String) }, success: S.CapacityView, error: errors }),
    "Every seat's projected capacity", "Grade, staleness, headroom, resets, the floor's WIP per seat and admit for ?model."))
  .add(doc(HttpApiEndpoint.get("capacityAdmit", "/capacity/admit", { query: { seat: Schema.String, model: Schema.optionalKey(Schema.String), min_headroom_pct: Schema.optionalKey(Schema.String) }, success: S.AdmitAnswer, error: errors }), "Would one seat admit a job now"))
  .add(doc(HttpApiEndpoint.post("capacitySnapshot", "/capacity/snapshots", { payload: Schema.Unknown.annotate({ description: "A seat-capacity/2 snapshot." }), success: Schema.Record(Schema.String, Schema.Unknown), error: errors }), "Push a seat-capacity/2 snapshot (the pusher)"))

export const FloorGroup = HttpApiGroup.make("floor")
  .add(doc(HttpApiEndpoint.get("floorState", "/floor/state", { success: S.FloorState, error: errors }), "Floor statistics, run WIP, alarm, config and schema version"))
  .add(doc(HttpApiEndpoint.get("health", "/health", { success: S.Health, error: errors }), "The deployed commit", "Answered by the Worker entry under the operator or read bearer."))
  .add(doc(HttpApiEndpoint.get("openapi", "/openapi.json", { success: Schema.Record(Schema.String, Schema.Unknown) }), "This document", "Served without a credential: it carries no data."))

export const SessionsGroup = HttpApiGroup.make("sessions")
  .add(doc(HttpApiEndpoint.get("listSessions", "/sessions", { query: { project: Schema.optionalKey(Schema.String), thread: Schema.optionalKey(Schema.String) }, success: Schema.Struct({ sessions: Schema.Array(S.SessionView) }), error: errors }),
    "Agent sessions", "Every session the floor holds, oldest first: its harness, model, worker status, latest post-turn summary, cumulative usage and transcript path. ?project and ?thread filter."))
  .add(doc(HttpApiEndpoint.get("getSession", "/sessions/:id", { params: Id, success: S.SessionView, error: errors }), "One session"))
  .add(doc(HttpApiEndpoint.patch("patchSession", "/sessions/:id", { params: Id, payload: S.SessionPatch, success: S.SessionView, error: errors }),
    "Change a session's model or effort", "The next turn uses them; the harness never changes. 400 bad-request for any other field or a value that is not a string."))
  .add(doc(HttpApiEndpoint.post("stopSession", "/sessions/:id/stop", { params: Id, success: S.SessionView, error: errors }),
    "Stop a session", "Cancels its current turn run; no turn starts again. The project tool learns it from the session report."))
  .add(doc(HttpApiEndpoint.post("nudge", "/nudge", { success: Schema.Struct({ ok: Schema.Boolean }).pipe(HttpApiSchema.status(202)), error: errors }),
    "Pull the feed now", "The project tool's call after a write that produced a feed row: the alarm fires now, pulls the feed and sends every unacked report."))

export const TriggersGroup = HttpApiGroup.make("triggers")
  .add(doc(HttpApiEndpoint.get("listTriggers", "/triggers", { query: { project: Schema.optionalKey(Schema.String) }, success: Schema.Struct({ triggers: Schema.Array(S.TriggerView) }), error: errors }),
    "Routines and send_later triggers", "Both kinds; ?project filters."))
  .add(doc(HttpApiEndpoint.post("createTrigger", "/triggers", { payload: S.TriggerCreate, success: S.TriggerView.pipe(HttpApiSchema.status(201)), error: errors }),
    "Create a trigger", "A routine fires its prompt into its persistent session at each time its cron expression names in its zone; a send_later is reported to the project tool once at run_at. 400 bad-request for an expression the floor cannot parse."))
  .add(doc(HttpApiEndpoint.get("getTrigger", "/triggers/:id", { params: Id, success: S.TriggerView, error: errors }), "One trigger"))
  .add(doc(HttpApiEndpoint.patch("updateTrigger", "/triggers/:id", { params: Id, payload: S.TriggerPatch, success: S.TriggerView, error: errors }), "Change a trigger", "enabled, prompt, cron_expression, timezone, name."))
  .add(doc(HttpApiEndpoint.delete("deleteTrigger", "/triggers/:id", { params: Id, success: Schema.Struct({ deleted: Schema.Boolean }), error: errors }), "Delete a trigger"))

export const SubstrateApi = HttpApi.make("substrate")
  .add(RunsGroup).add(JobsGroup).add(HoldersGroup).add(CapacityGroup).add(FloorGroup).add(SessionsGroup).add(TriggersGroup)
  .annotate(OpenApi.Title, "substrate floor")
  .annotate(OpenApi.Description, "The job-of-record floor. Operator routes take `Authorization: Bearer <FLOOR_TOKEN>` or a Cloudflare Access service token pair. " +
    "Pullers and links use POST /rpc (Effect RPC over HTTP, JSON serialization) with a per-link token: Lease, Heartbeat, Complete (see apps/link/src/contract.ts).")

/** Operator routes as (method, path template) pairs; the floor test holds the router to this list. */
export const ROUTES: ReadonlyArray<{ readonly method: string; readonly path: string; readonly id: string; readonly public: boolean }> =
  Object.values(SubstrateApi.groups).flatMap((g) => Object.values(g.endpoints).map((e) => ({ method: e.method, path: e.path, id: e.name, public: e.path === "/openapi.json" })))

let cached: Record<string, unknown> | undefined
/** The OpenAPI 3.1 document, with the two credential schemes the door accepts. */
export const openApiDocument = (): Record<string, unknown> => {
  if (cached) return cached
  const spec = OpenApi.fromApi(SubstrateApi) as unknown as Record<string, unknown> & { components?: Record<string, unknown>; paths: Record<string, Record<string, Record<string, unknown>>> }
  const components = (spec.components ?? {}) as Record<string, unknown>
  components.securitySchemes = {
    bearer: { type: "http", scheme: "bearer", description: "FLOOR_TOKEN (operator); PROJECT_TOKEN (the project tool) on /nudge, /sessions and /triggers; FLOOR_READ_TOKEN on GET routes." },
    accessClientId: { type: "apiKey", in: "header", name: "CF-Access-Client-Id" },
    accessClientSecret: { type: "apiKey", in: "header", name: "CF-Access-Client-Secret" }
  }
  spec.components = components
  for (const [path, ops] of Object.entries(spec.paths)) for (const op of Object.values(ops))
    op.security = path === "/openapi.json" ? [] : [{ bearer: [] }, { accessClientId: [], accessClientSecret: [] }]
  spec.servers = [{ url: "/" }]
  // Refusals are the floor's 4xx (400, 401, 403, 404, 409, 413, 422), not the generator's default 500.
  for (const ops of Object.values(spec.paths)) for (const op of Object.values(ops)) {
    const r = op.responses as Record<string, unknown> | undefined
    if (r && r["500"] !== undefined) { r["4XX"] = r["500"]; delete r["500"] }
  }
  cached = spec
  return spec
}
