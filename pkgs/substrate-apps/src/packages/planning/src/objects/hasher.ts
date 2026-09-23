/**
 * Hashing the armed bytes, as a capability.
 *
 * Arming is approval, and the hash of what was approved is the whole of a plan's
 * authority: the Factory hashes the artifact it was handed, refuses a mismatch
 * against what the client claimed, and every later admit carries that digest for
 * the kernel to verify against its armed set. No commit stands behind it and
 * none is required.
 *
 * A digest needs a platform primitive — WebCrypto on a Worker — and this package
 * imports nothing but `effect`, so the digest is a service the composition root
 * provides and never a function in a library module. That is the same rule the
 * storage interface follows and for the same reason: a library that reaches for
 * a binding stops running on the hermetic bench.
 *
 * The fake Layer here does not implement sha-256 and must not pretend to. It
 * answers from an authored table, so a test states exactly which bytes hash to
 * which digest and the mismatch path is tested by stating a mismatch rather than
 * by hoping one occurs.
 */
import { Context, Effect, Layer } from "effect";
import { ArtifactHashError } from "../schema/errors.ts";
import type { Sha256Hex } from "../schema/ids.ts";

/**
 * The bytes of one plan artifact.
 *
 * An ultracode workflow script with its arguments, or a campaign worklist,
 * exactly as they were handed to the object over HTTPS. They are carried as
 * bytes rather than as a parsed value because the digest must be taken over what
 * arrived, not over a re-serialisation of what it decoded to.
 */
export type ArtifactBytes = Uint8Array;

/** The digest capability. */
export interface IArtifactHasher {
  /**
   * Hashes one artifact's bytes.
   *
   * @param bytes - What arrived, verbatim.
   * @param label - The artifact's label, carried only so a failure can name
   *   which arming failed. Never the content.
   */
  readonly hash: (
    bytes: ArtifactBytes,
    label: string
  ) => Effect.Effect<Sha256Hex, ArtifactHashError>;
}

/** Provides the digest capability. */
export class ArtifactHasher extends Context.Service<ArtifactHasher, IArtifactHasher>()(
  "@substrate/planning/ArtifactHasher"
) {}

/**
 * Constructs a hasher that answers from an authored table.
 *
 * @param answers - Pairs of byte length and digest is not enough to be honest
 *   about, so the table is keyed by the exact byte sequence, compared element by
 *   element. A test therefore states the correspondence it is testing.
 * @returns A hasher that fails with `Unavailable` for bytes the table does not
 *   cover, rather than inventing a digest. An unknown artifact has no authority,
 *   and the arming must fail rather than proceed under a fabricated one.
 */
export const makeTableArtifactHasher = (
  answers: ReadonlyArray<readonly [ArtifactBytes, Sha256Hex]>
): IArtifactHasher => ({
  hash: (bytes: ArtifactBytes, label: string) => {
    for (const [candidate, digest] of answers) {
      if (candidate.length !== bytes.length) continue;
      let same = true;
      for (let index = 0; index < candidate.length; index += 1) {
        if (candidate[index] !== bytes[index]) {
          same = false;
          break;
        }
      }
      if (same) return Effect.succeed(digest);
    }
    return Effect.fail(new ArtifactHashError({ reason: "Unavailable", label }));
  }
});

/** Provides a table-driven hasher, for tests and the hermetic bench. */
export const artifactHasherTableLayer = (
  answers: ReadonlyArray<readonly [ArtifactBytes, Sha256Hex]>
): Layer.Layer<ArtifactHasher> =>
  Layer.succeed(ArtifactHasher)(ArtifactHasher.of(makeTableArtifactHasher(answers)));
