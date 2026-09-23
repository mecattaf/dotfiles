import { describe, expect, it } from "vitest"
import * as FM from "../src/Frontmatter.ts"

const read = (s: string) => FM.parse(s, "<test>")

describe("split", () => {
  it("takes the fenced head and leaves the body", () => {
    const s = FM.split("---\nid: X\n---\n\n# body\n")
    expect(s?.frontmatter).toBe("id: X")
    expect(s?.body.trim()).toBe("# body")
  })
  it("returns null when the document opens with no fence", () => {
    expect(FM.split("# just a heading\n")).toBeNull()
  })
  it("returns null when the fence never closes", () => {
    expect(FM.split("---\nid: X\n")).toBeNull()
  })
})

describe("scalars", () => {
  it("resolves the core types", () => {
    expect(read("a: 1\nb: 1.5\nc: true\nd: false\ne: null\nf: ~\ng:")).toEqual({
      a: 1,
      b: 1.5,
      c: true,
      d: false,
      e: null,
      f: null,
      g: null
    })
  })
  it("keeps a plain scalar as written, dates included", () => {
    expect(read("created: 2026-09-06\nid: T-LAKE")).toEqual({ created: "2026-09-06", id: "T-LAKE" })
  })
  it("unescapes a double-quoted scalar and keeps a single-quoted one literal", () => {
    expect(read('a: "x\\ny"\nb: \'it\'\'s\'')).toEqual({ a: "x\ny", b: "it's" })
  })
  it("treats an apostrophe inside a plain scalar as text, not a quote", () => {
    expect(read("a: Tom's own line")).toEqual({ a: "Tom's own line" })
  })
})

describe("comments", () => {
  it("drops a trailing comment", () => {
    expect(read("status: DRAFT   # DRAFT → ARMED → RUNNING")).toEqual({ status: "DRAFT" })
  })
  it("drops a whole-line comment", () => {
    expect(read("# --- R(y) ---\nid: X")).toEqual({ id: "X" })
  })
  it("keeps a ' #' that is inside a quoted value (MEASURED: 53 such values)", () => {
    const v = read('path: "/a/b.jsonl   # 744 rows, read-only"') as Record<string, unknown>
    expect(v.path).toBe("/a/b.jsonl   # 744 rows, read-only")
  })
  it("keeps a '#' that no whitespace introduces", () => {
    expect(read("issue: dotfiles#311")).toEqual({ issue: "dotfiles#311" })
  })
})

describe("flow collections", () => {
  it("reads a flow sequence, empty and not", () => {
    expect(read("a: []\nb: [X, \"Y, Z\"]")).toEqual({ a: [], b: ["X", "Y, Z"] })
  })
  it("reads a flow mapping", () => {
    expect(read('arm: {model: opus, executors: 2, note: "a, b"}')).toEqual({
      arm: { model: "opus", executors: 2, note: "a, b" }
    })
  })
  it("reads a key-only flow mapping as keys mapped to null (cards/UTIL-01.md:118)", () => {
    expect(read("inputs_paths: {sampler_log, ledger}")).toEqual({
      inputs_paths: { sampler_log: null, ledger: null }
    })
  })
  it("refuses a flow collection that does not close on its line", () => {
    expect(() => read("a: [X, Y")).toThrow(FM.FrontmatterError)
  })
})

describe("block structure", () => {
  it("nests mappings by indentation", () => {
    expect(read("prior:\n  p_pass: 0.4\n  basis: text\nid: X")).toEqual({
      prior: { p_pass: 0.4, basis: "text" },
      id: "X"
    })
  })
  it("reads a sequence of flow mappings", () => {
    expect(read('sources:\n  - {path: "/a", locator: "l1"}\n  - {path: "/b", locator: "l2"}')).toEqual({
      sources: [{ path: "/a", locator: "l1" }, { path: "/b", locator: "l2" }]
    })
  })
  it("reads a sequence of quoted scalars", () => {
    expect(read('abort_on:\n  - "one"\n  - "two"')).toEqual({ abort_on: ["one", "two"] })
  })
  it("gives an empty key with no deeper block the value null", () => {
    expect(read("supervisory:\nid: X")).toEqual({ supervisory: null, id: "X" })
  })
  it("refuses a duplicate key", () => {
    expect(() => read("id: A\nid: B")).toThrow(/duplicate key/)
  })
  it("refuses a sequence item that is a block mapping (outside the subset)", () => {
    expect(() => read("a:\n  - k: v\n    j: w")).toThrow(/outside the subset/)
  })
  it("names the file and the line when it refuses", () => {
    try {
      FM.parse("id: X\n  bad: 1", "/a/b.md", 2)
      throw new Error("should have thrown")
    } catch (e) {
      expect(e).toBeInstanceOf(FM.FrontmatterError)
      expect((e as FM.FrontmatterError).line).toBe(3)
      expect((e as FM.FrontmatterError).path).toBe("/a/b.md")
    }
  })
})

describe("block scalars", () => {
  it("folds `>-` and strips the trailing break", () => {
    expect(read("problem: >-\n  one line\n  and another\nid: X")).toEqual({
      problem: "one line and another",
      id: "X"
    })
  })
  it("folds a blank line into a newline", () => {
    expect(read("problem: >-\n  a\n\n  b")).toEqual({ problem: "a\nb" })
  })
  it("keeps newlines under `|`", () => {
    expect(read("body: |\n  a\n  b")).toEqual({ body: "a\nb\n" })
  })
  it("keeps a '#' line inside a block scalar as text", () => {
    expect(read("problem: >-\n  a\n  # not a comment here\nid: X")).toEqual({
      problem: "a # not a comment here",
      id: "X"
    })
  })
})
