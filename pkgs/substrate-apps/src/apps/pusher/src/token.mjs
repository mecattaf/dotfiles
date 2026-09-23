// apps/pusher/src/token.mjs: reads the floor's bearer from a file. The value is
// returned to the caller and never printed; an error names the path only.
import { readFileSync } from "node:fs"

export class TokenError extends Error {}

export const tokenFromFile = (path) => {
  try {
    return readFileSync(path, "utf8").trim()
  } catch (error) {
    throw new TokenError(`cannot read the floor token file ${path}: ${error.code ?? error.message}`)
  }
}
