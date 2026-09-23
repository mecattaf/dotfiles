/**
 * JSON Schema handling for structured agent() output.
 *
 * Two layers:
 *  1. `preflightSchema`: the checks the harness makes before it spawns anything
 *     (root must be `type: "object"`; every `required` name must be in
 *     `properties`, or the schema is unsatisfiable). A failure here is a
 *     programming error in the script, so agent() THROWS, it does not return null.
 *  2. `compileValidator`: ajv (draft 2020-12 dialect, non-strict so real
 *     scripts' annotation keywords pass) used to validate every structured
 *     result a backend returns. A mismatch is retried by the interpreter.
 */
import { Ajv } from "ajv";

export class SchemaPreflightError extends Error {
  override readonly name = "SchemaPreflightError";
}

type Json = Record<string, unknown>;

export function preflightSchema(schema: unknown): void {
  if (!schema || typeof schema !== "object" || Array.isArray(schema)) {
    throw new SchemaPreflightError("agent(): opts.schema must be a JSON Schema object");
  }
  const s = schema as Json;
  if (s.type !== "object") throw new SchemaPreflightError("agent(): schema root must be { type: 'object' }");
  const props = (s.properties ?? {}) as Json;
  const req = Array.isArray(s.required) ? (s.required as unknown[]) : [];
  const missing = req.filter((r) => typeof r !== "string" || !(r in props));
  if (missing.length) {
    throw new SchemaPreflightError(`agent(): unsatisfiable schema, required not in properties: ${missing.join(", ")}`);
  }
  // Compile here, at the call site: a schema ajv cannot compile is a programming
  // error, and must throw BEFORE the call takes a key, a journal line or a
  // backend attempt (it used to throw only after the first attempt had run).
  try {
    compileValidator(s);
  } catch (e) {
    throw new SchemaPreflightError(`agent(): invalid schema: ${(e as Error).message}`);
  }
}

export interface Validator {
  (value: unknown): { ok: true } | { ok: false; errors: string[] };
}

/**
 * Validators cached by the schema's JSON text, one Ajv instance per distinct
 * schema. One shared instance registers every `$id` it compiles, so the SECOND
 * agent() call with a schema carrying `$id` threw "schema with key or id ...
 * already exists" (MEASURED, test/edges.test.ts). Every call's opts arrive as a
 * fresh object (JSON across the realm boundary), so an object-identity cache
 * never hit either.
 */
const cache = new Map<string, Validator>();

export function compileValidator(schema: object): Validator {
  const text = JSON.stringify(schema);
  const hit = cache.get(text);
  if (hit) return hit;
  const ajv = new Ajv({ strict: false, allErrors: true, validateFormats: false });
  // Parsing the text detaches any foreign-realm prototypes.
  const fn = ajv.compile(JSON.parse(text));
  const v: Validator = (value) => {
    if (fn(value)) return { ok: true };
    return {
      ok: false,
      errors: (fn.errors ?? []).map((e) => `${e.instancePath || "$"} ${e.message ?? "invalid"}`),
    };
  };
  cache.set(text, v);
  return v;
}
