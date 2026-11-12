/**
 * src/verbs/schema.mjs - The `scheduled schema` verb.
 * Usage: schema
 * Prints the JSON Schema of a scheduled item (scheduled-item.v1) to stdout.
 */

import { jsonSchema } from '../lib/schema.mjs';

export async function main(args, ctx) {
  ctx.out(JSON.stringify(jsonSchema(), null, 2) + '\n');
  return 0;
}
