import { describe, expect, test } from "bun:test";
import { workspaceHeight } from "./WorkspaceMotion";

describe("workspace slide screen extent", () => {
  test("uses each full logical screen rather than a window or viewport height", () => {
    expect(workspaceHeight("rect(0px, 1440px, 900px, 0px)")).toBe(900);
    expect(workspaceHeight("rect(900px, 1440px, 1800px, 0px)")).toBe(900);
    expect(workspaceHeight("rect(-800px, 2560px, 0px, 1280px)")).toBe(800);
  });
  test("retains fractional logical geometry and negative display origins", () => {
    expect(workspaceHeight("rect(-300.5px, 640.25px, 419.75px, -639.75px)")).toBe(720.25);
  });
  test("does not invent a height for idle, malformed or empty clips", () => {
    for (const clip of ["", "auto", "none", "rect(auto, 100px, 100px, 0px)",
      "rect(0px, 100px, 0px, 0px)", "rect(0px, 0px, 100px, 0px)",
      "rect(0, 100px, 100px, 0px)", "rect(0px, 100px, 100px)",
      "rect(0px, 1e999px, 100px, 0px)"]) {
      expect(workspaceHeight(clip)).toBeUndefined();
    }
  });
});
