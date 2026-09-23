/**
 * The catalog: machines as data.
 *
 * Volume II Part III section 1 promotes the machine index to the
 * `(model x harness)` pair, because the same weights mounted in three harnesses
 * are three machines with three processing times, three yields and three setup
 * structures. Under ruling 4 the harness half is a herdr agent kind and nothing
 * more: launch, argv, resume and trace scraping are herdr's manifest, and this
 * package holds only what is harness-agnostic — the rows a member needs, its
 * classes, its maker, and whether it is metered.
 */
import { Schema } from "effect";
import { AgentKind, ClassName, MakerName, MemberId, ModelId, RowName } from "./ids.ts";

/**
 * One `(model x herdr agent kind)` machine.
 *
 * A node names a class and never a member; the Factory resolves the member, and
 * the kernel evaluates the member's rows.
 */
export const CatalogMember = Schema.Struct({
  /** The member's catalog id. */
  id: MemberId,
  /** The mounted model, the "tool head" of the machine model. */
  model: ModelId,
  /** The herdr agent kind this member runs under. */
  agentKind: AgentKind,
  /** The model's maker, used only to decorrelate redundant attempts. */
  maker: MakerName,
  /**
   * Capability classes this member satisfies.
   *
   * Classes are grade-of-service floors, never dedication. There is no reason
   * to dedicate a lane to a product family, because tooling changeover is free.
   */
  classes: Schema.Array(ClassName),
  /** The rows a job on this member consumes; a tensor-parallel member names both devices. */
  rows: Schema.Array(RowName),
  /** Whether this member draws on a metered envelope. Free lanes have zero weight cost. */
  metered: Schema.Boolean
});
/** One `(model x herdr agent kind)` machine. */
export type CatalogMember = typeof CatalogMember.Type;

/**
 * The pinned catalog.
 *
 * The runner pins the exact catalog bytes for a whole run; a byte change fails
 * before node reuse or admission, which is what replay needs.
 */
export const Catalog = Schema.Struct({
  /** Hash over the catalog bytes, pinned for the life of a run. */
  hash: Schema.String,
  /** The declared members. */
  members: Schema.Array(CatalogMember)
});
/** The pinned catalog. */
export type Catalog = typeof Catalog.Type;

/**
 * Members satisfying a capability floor.
 *
 * @returns every member declaring the class, in catalog order, which is
 *   deterministic for a given catalog and therefore replayable.
 */
export const membersForClass = (
  catalog: Catalog,
  required: ClassName
): ReadonlyArray<CatalogMember> =>
  catalog.members.filter((member) => member.classes.includes(required));
