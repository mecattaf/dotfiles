import { describe, expect, test } from "bun:test";
import {
  displayTitle,
  formatClock,
  formatDuration,
  formatDurationWords,
  formatPlays,
  livePositionMs,
  monogram,
  plural,
  songSubtitle,
  truncateMiddle,
} from "./format";

describe("format", () => {
  test("durations", () => {
    expect(formatDuration(336_000)).toBe("5:36");
    expect(formatDuration(3_723_000)).toBe("1:02:03");
    expect(formatDuration(-5)).toBe("0:00");
    expect(formatDurationWords(39 * 60_000)).toBe("39 min");
    expect(formatDurationWords(72 * 60_000)).toBe("1 h 12 min");
    expect(formatDurationWords(120 * 60_000)).toBe("2 h");
    expect(formatClock(72_000, 220_000)).toBe("1:12 / 3:40");
  });
  test("counts", () => {
    expect(plural(1, "song")).toBe("1 song");
    expect(plural(38524, "song")).toBe("38,524 songs");
    expect(formatPlays(0)).toBe("");
    expect(formatPlays(1)).toBe("1 play");
    expect(formatPlays(12)).toBe("12 plays");
  });
  test("truncation", () => {
    expect(truncateMiddle("Bon Iver, Bon Iver", 50)).toBe("Bon Iver, Bon Iver");
    const t = truncateMiddle("Bon Iver, Bon Iver", 9);
    expect([...t].length).toBe(9);
    expect(t.includes("…")).toBe(true);
  });
  test("display rules", () => {
    expect(displayTitle({ title: "Daft Punk - Aerodynamic", artist: "Daft Punk" })).toBe("Aerodynamic");
    expect(displayTitle({ title: "Holocene", artist: "Bon Iver" })).toBe("Holocene");
    expect(songSubtitle({ artist: "Parcels", album: "[Unknown Album]" })).toBe("Parcels");
    expect(songSubtitle({ artist: "[Unknown Artist]", album: "[Unknown Album]" })).toBe("Unknown artist");
    expect(monogram("The xx")).toBe("X");
    expect(monogram("")).toBe("♪");
  });
  test("position extrapolation", () => {
    const track = { durationMs: 10_000 } as never;
    expect(livePositionMs({ status: "playing", positionMs: 1000, positionAt: 5000, track }, 7000)).toBe(3000);
    expect(livePositionMs({ status: "paused", positionMs: 1000, positionAt: 5000, track }, 7000)).toBe(1000);
    expect(livePositionMs({ status: "playing", positionMs: 9000, positionAt: 0, track }, 60_000)).toBe(10_000);
  });
});
