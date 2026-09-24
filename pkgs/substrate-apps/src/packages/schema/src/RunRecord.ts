/**
 * @substrate/schema RunRecord: the fields every released item carries on the
 * floor (ES-6), from SCOPING-AX-EFFECT-TRANSITION-2026-09-21 section 3.
 *
 * Four of them are new to the successor and are the point of this module:
 *
 *   runtime     the class of box the item runs in: host, herdr, gvisor, microvm,
 *               workerd. "host is declared, never inferred": a host runtime
 *               must be declared by the item, never filled by a floor default.
 *   placement   the node the puller put it on (coordinator, worker, ...), and
 *               who decided.
 *   egress      the allowlist the box may reach. Never the executor's own
 *               control plane (ax-server, ateapi).
 *   credential  the credential LANE, by name only: none, a seat's config
 *               directory mounted, or a named credential file. A record never
 *               carries a credential value; the decoder refuses unknown keys, so
 *               a `token` or `value` key is a decode failure, not a strip.
 *
 * Harness and model are data (slugs), never enumerated here: the floor names
 * no product (tools/check-fences.mjs F1).
 */
import * as S from "effect/Schema"
import * as Result from "effect/Result"

/** A lower-case slug: seat, harness, model and node names are data. */
export const Slug = S.String.pipe(S.check(S.isPattern(/^[a-z0-9][a-z0-9._-]{0,62}$/)))

/** The runtime classes a box can be. */
export const RuntimeClass = S.Literals(["host", "herdr", "gvisor", "microvm", "workerd"])
export type RuntimeClass = typeof RuntimeClass.Type

const RuntimeFields = S.Struct({
  class: RuntimeClass,
  /** `item` when the item declared it; `floor-default` when the floor filled it. */
  declared_by: S.Literals(["item", "floor-default"])
})

/** The runtime an item runs in, and who chose it. */
export const Runtime = RuntimeFields.pipe(
  S.check(
    S.makeFilter(
      (runtime: typeof RuntimeFields.Type) => runtime.class !== "host" || runtime.declared_by === "item",
      { expected: "a host runtime declared by the item (host is declared, never inferred)" }
    )
  )
)
export type Runtime = typeof Runtime.Type

/** Where the puller put the item. */
export const Placement = S.Struct({
  /** The node, as the fleet names it (`coordinator`, `worker`). */
  node: Slug,
  /** Who decided: the item pinned it, or the puller chose from the readings. */
  decided_by: S.Literals(["item", "puller"]),
  /** Why, in one line, when the puller chose. */
  reason: S.NullOr(S.String)
})
export type Placement = typeof Placement.Type

/** Hosts a box may never reach: the executor's own control plane. */
export const FORBIDDEN_EGRESS = ["ax-server", "ateapi"] as const

const EgressHost = S.String.pipe(
  S.check(S.isPattern(/^[A-Za-z0-9*][A-Za-z0-9.*-]*(:[0-9]{1,5})?$/)),
  S.check(
    S.makeFilter(
      (host: string) => !FORBIDDEN_EGRESS.some((name) => host === name || host.startsWith(`${name}.`) || host.startsWith(`${name}:`)),
      { expected: "an egress host other than the executor's control plane (ax-server, ateapi)" }
    )
  )
)

const EgressFields = S.Struct({
  /** none: no network; allowlist: only `allow`; open: anything (declared, logged). */
  policy: S.Literals(["none", "allowlist", "open"]),
  allow: S.Array(
    S.Struct({
      host: EgressHost,
      /** Why this box needs it (the model endpoint, the NAS sink, the forge). */
      purpose: S.String
    })
  )
})

/** The network a box may reach. */
export const Egress = EgressFields.pipe(
  S.check(
    S.makeFilter(
      (egress: typeof EgressFields.Type) =>
        egress.policy === "allowlist" ? egress.allow.length > 0 : egress.allow.length === 0,
      { expected: "an allowlist policy with at least one host, or none/open with an empty list" }
    )
  )
)
export type Egress = typeof Egress.Type

/** A credential reference: a name or a path, never a value. */
const CredentialRef = S.String.pipe(S.check(S.isPattern(/^[A-Za-z0-9_.~/-][A-Za-z0-9_.~/:@-]{0,255}$/)))

/** The credential lane a box gets, by reference only. */
export const Credential = S.Union([
  S.Struct({ lane: S.Literal("none") }),
  S.Struct({
    lane: S.Literal("seat-config-mount"),
    /** The seat whose config directory is mounted. */
    seat: Slug,
    /** Tom's 2026-09-21 ruling covers a read-write mount. */
    mode: S.Literals(["ro", "rw"])
  }),
  S.Struct({
    lane: S.Literal("credential-file"),
    /** The credential's name (an agenix secret name, a wrangler secret name). */
    ref: CredentialRef
  })
])
export type Credential = typeof Credential.Type

const RunRecordFields = S.Struct({
  /** The run this item belongs to. */
  run_id: S.String.pipe(S.check(S.isMinLength(1))),
  /** The dedup key: the Task name. */
  task: S.String.pipe(S.check(S.isMinLength(1))),
  /** The harness lane, as data. */
  harness: Slug,
  /** The model, as data; null when the harness decides. */
  model: S.NullOr(Slug),
  runtime: Runtime,
  placement: Placement,
  egress: Egress,
  credential: Credential
})

/**
 * One released item's run record. Cross-field rule: a workerd box cannot run
 * an agent (it has no process or shell, W3), so it carries no credential.
 */
export const RunRecord = RunRecordFields.pipe(
  S.check(
    S.makeFilter(
      (record: typeof RunRecordFields.Type) =>
        record.runtime.class !== "workerd" || record.credential.lane === "none",
      { expected: "no credential lane on a workerd runtime" }
    )
  )
)
export type RunRecord = typeof RunRecord.Type

/** The run record's field names, in declaration order. */
export const RUN_RECORD_FIELDS = Object.keys(RunRecordFields.fields) as ReadonlyArray<string>

const PARSE = { onExcessProperty: "error", errors: "all" } as const
const run = S.decodeUnknownResult(RunRecord)

/** Decodes an untrusted run record; unknown keys (a stray `token`) fail. */
export const decodeRunRecord = (
  input: unknown
): { readonly ok: true; readonly value: RunRecord } | { readonly ok: false; readonly why: string } => {
  const result = run(input, PARSE)
  return Result.isSuccess(result)
    ? { ok: true, value: result.success }
    : { ok: false, why: result.failure.message.replace(/\s*\n\s*/g, " ") }
}
