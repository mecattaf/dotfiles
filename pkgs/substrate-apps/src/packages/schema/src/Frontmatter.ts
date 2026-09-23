/**
 * Frontmatter.ts — U-A8 LAKE-SCHEMA.
 *
 * The register's cards are Markdown files whose front matter is YAML. This
 * module turns that front matter into a plain JavaScript value so an Effect
 * Schema can decode it. It is NOT a YAML implementation: it is a reader for the
 * documented subset the register actually uses, and it REFUSES everything else
 * rather than guessing.
 *
 * Why a reader and not a dependency: dependencies arrive by local copy with
 * recorded provenance and never from a registry (CONTRIBUTING.md §2 rule 2),
 * and no YAML parser is in the tree U-A3 copied (MEASURED: no `yaml`, no
 * `js-yaml` under packages/planning/node_modules). Fetching one is a network
 * act and a network act is Tom's.
 *
 * The subset, MEASURED over the 173 front matters of
 * /home/tom/research-methods/cards on 2026-09-06 (14 cards, 89 ladder, 70 SH):
 *
 *   - block mappings, indented in steps of two, to depth 3
 *   - block sequences whose items are flow mappings, quoted scalars or plain
 *     scalars (MEASURED: zero `- key: value` items in the corpus)
 *   - folded and literal block scalars: `>-` `>` `|` `|-` `>+` `|+`
 *   - single-line flow mappings `{a: b}` and flow sequences `[a, "b"]`
 *     (MEASURED: zero flow collections span a line break in the corpus)
 *   - scalars: null / ~ / empty, true, false, integers, floats,
 *     double-quoted (\\ \" \n \t escapes), single-quoted ('' escape), plain
 *   - full-line comments, and trailing comments introduced by " #" outside a
 *     quoted span (MEASURED: 53 quoted values contain " #" and must keep it)
 *
 * Anything else throws FrontmatterError naming the file, the line number and
 * the line. A refusal is a gap the caller records; it is never a silent
 * mis-parse. "A green that cannot go red is vacuous" (CONTRIBUTING.md §2
 * rule 5) — the same applies to a reader that accepts everything.
 */

export class FrontmatterError extends Error {
  readonly path: string
  readonly line: number
  readonly text: string
  constructor(path: string, line: number, text: string, why: string) {
    super(`${path}:${line}: ${why}\n  | ${text}`)
    this.name = "FrontmatterError"
    this.path = path
    this.line = line
    this.text = text
  }
}

export type Scalar = string | number | boolean | null
export type Value = Scalar | ReadonlyArray<Value> | { readonly [k: string]: Value }

/** The fenced front matter of a Markdown file, and the body after it. */
export interface Split {
  readonly frontmatter: string
  /** 1-based line number of the first front-matter line, for error messages. */
  readonly firstLine: number
  readonly body: string
}

const FENCE = "---"

/**
 * Split `---` … `---` off the head of a Markdown document.
 * Returns null when the document opens with no fence at all.
 */
export const split = (text: string): Split | null => {
  const lines = text.split("\n")
  if (lines.length === 0 || (lines[0] ?? "").trimEnd() !== FENCE) return null
  for (let i = 1; i < lines.length; i++) {
    if ((lines[i] ?? "").trimEnd() === FENCE) {
      return {
        frontmatter: lines.slice(1, i).join("\n"),
        firstLine: 2,
        body: lines.slice(i + 1).join("\n")
      }
    }
  }
  return null
}

// --- scalars -----------------------------------------------------------------

const isBlank = (s: string): boolean => s.trim() === ""
const indentOf = (s: string): number => s.length - s.replace(/^ +/, "").length

/** Strip a trailing `#` comment that begins outside any quoted span. */
export const stripComment = (s: string): string => {
  let quote: '"' | "'" | null = null
  for (let i = 0; i < s.length; i++) {
    const c = s[i]
    if (quote === '"') {
      if (c === "\\") i++
      else if (c === '"') quote = null
      continue
    }
    if (quote === "'") {
      if (c === "'" && s[i + 1] === "'") i++
      else if (c === "'") quote = null
      continue
    }
    // A quote opens a span only where a scalar may begin: at the start of the
    // value, or just after a flow separator. Elsewhere it is an apostrophe.
    if (c === '"' || c === "'") {
      const before = s.slice(0, i).trimEnd()
      if (before === "" || /[[{,:]$/.test(before)) quote = c as '"' | "'"
      continue
    }
    if (c === "#" && (i === 0 || s[i - 1] === " " || s[i - 1] === "\t")) {
      return s.slice(0, i)
    }
  }
  return s
}

const unescapeDouble = (raw: string): string =>
  raw.replace(/\\(u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)/g, (_m, g: string) => {
    switch (g[0]) {
      case "n":
        return "\n"
      case "t":
        return "\t"
      case "r":
        return "\r"
      case "0":
        return "\0"
      case "u":
      case "x":
        return String.fromCodePoint(parseInt(g.slice(1), 16))
      default:
        return g
    }
  })

const INT = /^[-+]?[0-9][0-9_]*$/
const FLOAT = /^[-+]?(?:[0-9][0-9_]*)?\.[0-9]+(?:[eE][-+]?[0-9]+)?$/

/** Parse one scalar: quoted, or plain with YAML's core resolution. */
const parseScalar = (raw: string): Scalar => {
  const s = raw.trim()
  if (s === "" || s === "~" || s === "null" || s === "Null" || s === "NULL") return null
  if (s === "true" || s === "True" || s === "TRUE") return true
  if (s === "false" || s === "False" || s === "FALSE") return false
  if (s.startsWith('"')) return unescapeDouble(s.slice(1, -1))
  if (s.startsWith("'")) return s.slice(1, -1).replace(/''/g, "'")
  if (INT.test(s)) return Number(s.replace(/_/g, ""))
  if (FLOAT.test(s)) return Number(s.replace(/_/g, ""))
  return s
}

/** Split a flow collection body on top-level commas, honouring quotes. */
const splitFlow = (s: string, path: string, line: number, text: string): Array<string> => {
  const out: Array<string> = []
  let depth = 0
  let quote: '"' | "'" | null = null
  let start = 0
  for (let i = 0; i < s.length; i++) {
    const c = s[i]
    if (quote === '"') {
      if (c === "\\") i++
      else if (c === '"') quote = null
      continue
    }
    if (quote === "'") {
      if (c === "'" && s[i + 1] === "'") i++
      else if (c === "'") quote = null
      continue
    }
    if (c === '"' || c === "'") {
      const before = s.slice(start, i).trim()
      if (before === "" || /[:[{]$/.test(before)) quote = c as '"' | "'"
      continue
    }
    if (c === "{" || c === "[") depth++
    else if (c === "}" || c === "]") depth--
    else if (c === "," && depth === 0) {
      out.push(s.slice(start, i))
      start = i + 1
    }
  }
  if (depth !== 0 || quote !== null) {
    throw new FrontmatterError(path, line, text, "unterminated flow collection or quoted scalar")
  }
  const tail = s.slice(start)
  if (tail.trim() !== "" || out.length > 0) out.push(tail)
  return out
}

/** Parse a value that fits on one line: a flow collection or a scalar. */
const parseInline = (raw: string, path: string, line: number, text: string): Value => {
  const s = raw.trim()
  if (s.startsWith("{")) {
    if (!s.endsWith("}")) {
      throw new FrontmatterError(path, line, text, "flow mapping does not close on its own line")
    }
    const obj: Record<string, Value> = {}
    for (const part of splitFlow(s.slice(1, -1), path, line, text)) {
      if (part.trim() === "") continue
      const idx = keyEnd(part)
      // `{a, b}` is a flow mapping of a and b to null — MEASURED at
      // cards/UTIL-01.md:118 (`inputs_paths: {sampler_log, ledger, …}`).
      if (idx < 0) {
        obj[String(parseScalar(part))] = null
        continue
      }
      const k = String(parseScalar(part.slice(0, idx)))
      obj[k] = parseInline(part.slice(idx + 1), path, line, text)
    }
    return obj
  }
  if (s.startsWith("[")) {
    if (!s.endsWith("]")) {
      throw new FrontmatterError(path, line, text, "flow sequence does not close on its own line")
    }
    return splitFlow(s.slice(1, -1), path, line, text).map((p) => parseInline(p, path, line, text))
  }
  if ((s.startsWith('"') && !s.endsWith('"')) || (s.startsWith("'") && !s.endsWith("'"))) {
    throw new FrontmatterError(path, line, text, "quoted scalar does not close on its own line")
  }
  return parseScalar(s)
}

/** Index of the `:` that ends a flow-mapping key, or -1. */
const keyEnd = (s: string): number => {
  let quote: '"' | "'" | null = null
  for (let i = 0; i < s.length; i++) {
    const c = s[i]
    if (quote) {
      if (quote === '"' && c === "\\") i++
      else if (c === quote) quote = null
      continue
    }
    if (c === '"' || c === "'") {
      if (s.slice(0, i).trim() === "") quote = c as '"' | "'"
      continue
    }
    if (c === ":" && (i + 1 === s.length || s[i + 1] === " ")) return i
  }
  return -1
}

// --- block structure ---------------------------------------------------------

const BLOCK_HEADER = /^([|>])([-+]?)$/
const KEY = /^([A-Za-z_][A-Za-z0-9_.\-]*|"[^"]*"|'[^']*'):(?:\s+(.*))?$/

interface Cursor {
  readonly lines: ReadonlyArray<string>
  readonly path: string
  /** 1-based line number of lines[0]. */
  readonly base: number
  i: number
}

const at = (c: Cursor): string => c.lines[c.i] ?? ""
const lineNo = (c: Cursor): number => c.base + c.i
const done = (c: Cursor): boolean => c.i >= c.lines.length

/** Advance past blank lines and full-line comments. */
const skipNoise = (c: Cursor): void => {
  while (!done(c)) {
    const s = at(c)
    if (isBlank(s) || s.trimStart().startsWith("#")) c.i++
    else return
  }
}

/** Consume a block scalar introduced at `parentIndent`. */
const readBlockScalar = (c: Cursor, parentIndent: number, style: string, chomp: string): string => {
  const raw: Array<string> = []
  while (!done(c)) {
    const s = at(c)
    if (!isBlank(s) && indentOf(s) <= parentIndent) break
    raw.push(s)
    c.i++
  }
  while (raw.length > 0 && isBlank(raw[raw.length - 1] ?? "")) raw.pop()
  if (raw.length === 0) return ""
  const indent = Math.min(...raw.filter((s) => !isBlank(s)).map(indentOf))
  const body = raw.map((s) => (isBlank(s) ? "" : s.slice(indent)))
  let out: string
  if (style === "|") {
    out = body.join("\n")
  } else {
    // Folded: a single line break between two equally-indented non-empty lines
    // becomes a space; a blank line becomes a newline; a more-indented line
    // keeps its break.
    let acc = ""
    for (let k = 0; k < body.length; k++) {
      const cur = body[k] ?? ""
      if (k === 0) {
        acc = cur
        continue
      }
      const prev = body[k - 1] ?? ""
      if (cur === "") acc += "\n"
      else if (prev === "") acc += cur
      else if (indentOf(cur) > 0 || indentOf(prev) > 0) acc += "\n" + cur
      else acc += " " + cur
    }
    out = acc
  }
  if (chomp === "+") return out + "\n"
  if (chomp === "-") return out
  return out + "\n"
}

const parseBlock = (c: Cursor, indent: number): Value => {
  skipNoise(c)
  if (done(c)) return null
  const first = at(c)
  if (first.trimStart().startsWith("- ") || first.trim() === "-") return parseSeq(c, indent)
  return parseMap(c, indent)
}

const parseSeq = (c: Cursor, indent: number): ReadonlyArray<Value> => {
  const out: Array<Value> = []
  for (;;) {
    skipNoise(c)
    if (done(c)) break
    const s = at(c)
    const ind = indentOf(s)
    if (ind < indent) break
    const body = s.slice(ind)
    if (!body.startsWith("- ") && body.trim() !== "-") {
      throw new FrontmatterError(c.path, lineNo(c), s, "expected a sequence item ('- …')")
    }
    if (ind > indent) {
      throw new FrontmatterError(c.path, lineNo(c), s, "sequence item indented past its sequence")
    }
    const rest = stripComment(body.replace(/^-\s*/, "")).trim()
    const ln = lineNo(c)
    c.i++
    if (rest === "") {
      out.push(parseBlock(c, indent + 2))
    } else if (KEY.test(rest)) {
      throw new FrontmatterError(c.path, ln, s, "sequence items that are block mappings are outside the subset")
    } else {
      out.push(parseInline(rest, c.path, ln, s))
    }
  }
  return out
}

const parseMap = (c: Cursor, indent: number): { readonly [k: string]: Value } => {
  const out: Record<string, Value> = {}
  for (;;) {
    skipNoise(c)
    if (done(c)) break
    const s = at(c)
    const ind = indentOf(s)
    if (ind < indent) break
    if (ind > indent) {
      throw new FrontmatterError(c.path, lineNo(c), s, `unexpected indent ${ind}, expected ${indent}`)
    }
    const body = s.slice(ind)
    if (body.startsWith("- ")) {
      throw new FrontmatterError(c.path, lineNo(c), s, "sequence item where a mapping key was expected")
    }
    const m = KEY.exec(body)
    if (m === null) {
      throw new FrontmatterError(c.path, lineNo(c), s, "not a mapping key ('key: value')")
    }
    const key = String(parseScalar(m[1] ?? ""))
    if (Object.prototype.hasOwnProperty.call(out, key)) {
      throw new FrontmatterError(c.path, lineNo(c), s, `duplicate key '${key}'`)
    }
    const rawRest = m[2] === undefined ? "" : m[2]
    const ln = lineNo(c)
    const blockHeader = BLOCK_HEADER.exec(stripComment(rawRest).trim())
    c.i++
    if (blockHeader !== null) {
      out[key] = readBlockScalar(c, ind, blockHeader[1] ?? ">", blockHeader[2] ?? "")
      continue
    }
    const rest = stripComment(rawRest).trim()
    if (rest === "") {
      // Either a nested block at a deeper indent, or an explicit empty value.
      const save = c.i
      skipNoise(c)
      if (!done(c) && indentOf(at(c)) > ind) {
        out[key] = parseBlock(c, indentOf(at(c)))
      } else {
        c.i = save
        out[key] = null
      }
      continue
    }
    out[key] = parseInline(rest, c.path, ln, s)
  }
  return out
}

/**
 * Read a front-matter block into a plain value.
 * `path` and `firstLine` are used only for error messages.
 */
export const parse = (frontmatter: string, path: string, firstLine = 1): Value => {
  const c: Cursor = { lines: frontmatter.split("\n"), path, base: firstLine, i: 0 }
  const v = parseBlock(c, 0)
  skipNoise(c)
  if (!done(c)) {
    throw new FrontmatterError(c.path, lineNo(c), at(c), "trailing content after the document")
  }
  return v
}

/** Split a Markdown document and read its front matter. Throws if it has none. */
export const read = (text: string, path: string): Value => {
  const s = split(text)
  if (s === null) throw new FrontmatterError(path, 1, text.split("\n")[0] ?? "", "no `---` front-matter fence")
  return parse(s.frontmatter, path, s.firstLine)
}
