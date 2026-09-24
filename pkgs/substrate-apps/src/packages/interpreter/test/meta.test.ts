import { describe, expect, it } from "vitest";
import { extractMeta, MetaError } from "../src/meta.ts";
import { run } from "./helpers.ts";

describe("meta: a pure literal, read without running the script", () => {
  it("accepts objects, arrays, strings, templates without ${}, numbers, booleans, null, comments, trailing commas", () => {
    const { meta, body } = extractMeta(`// header
export const meta = {
  name: 'n', "description": \`multi
line\`, // comment
  phases: [ { title: 'Read', detail: 'x', model: 'opus', }, /* c */ { title: 'Judge' }, ],
  extra: { n: -1.5e2, ok: true, nothing: null, hex: 0x1F },
}
return 1`);
    expect(meta.name).toBe("n");
    expect(meta.description).toBe("multi\nline");
    expect(meta.phases).toEqual([{ title: "Read", detail: "x", model: "opus" }, { title: "Judge" }]);
    // the declaration is replaced by the same number of newlines: line numbers stay true
    expect(body.split("\n").length).toBe(8);
    expect(body.split("\n")[7]).toBe("return 1");
  });

  it.each([
    ["a free identifier", "export const meta = { name: X, description: 'd' }"],
    ["a call", "export const meta = { name: f(), description: 'd' }"],
    ["a spread", "export const meta = { ...base, name: 'n', description: 'd' }"],
    ["a template interpolation", "export const meta = { name: `a${1}`, description: 'd' }"],
    ["a computed key", "export const meta = { ['name']: 'n', description: 'd' }"],
    ["a shorthand property", "export const meta = { name, description: 'd' }"],
    ["an operator after the literal", "export const meta = { name: 'n', description: 'd' }.name"],
    ["a missing description", "export const meta = { name: 'n' }"],
    ["an empty name", "export const meta = { name: '', description: 'd' }"],
    ["phases that are not an array of {title}", "export const meta = { name: 'n', description: 'd', phases: ['Read'] }"],
    ["no meta at all", "const meta = { name: 'n', description: 'd' }"],
    ["a second export", "export const meta = { name: 'n', description: 'd' }\nexport const x = 1"],
  ])("rejects %s", (_why, src) => {
    expect(() => extractMeta(src)).toThrow(MetaError);
  });

  it("does not evaluate the header: a getter-like or side-effecting expression never runs", () => {
    expect(() => extractMeta("export const meta = { name: (globalThis.hit = 1), description: 'd' }")).toThrow(MetaError);
    expect((globalThis as { hit?: unknown }).hit).toBeUndefined();
  });

  it("a script with a bad meta fails before any agent() call", async () => {
    const { runWorkflow } = await import("../src/interpreter.ts");
    const { MockBackend } = await import("../src/backend.ts");
    const b = new MockBackend();
    await expect(runWorkflow("export const meta = { name: X }\nawait agent('x')", { backend: b })).rejects.toThrow(MetaError);
    expect(b.calls).toHaveLength(0);
  });

  it("keeps stack-trace line numbers equal to the file's", async () => {
    // META is line 1 of the file; this throw sits on line 4.
    const r = await run("\n\nthrow new Error(String(new Error('x').stack).split('\\n')[1])");
    expect(r.status).toBe("failed");
    expect(r.error).toMatch(/t\.js:4:/);
  });
});
