import { expect, test } from "bun:test";
import { scrollSheetClip, scrollViewportClip } from "./ScrollClip";

test("permanent viewport clipping uses the reserved workspace and logical monitor origin", () => {
  expect(scrollViewportClip({ x: 256, y: 0, width: 1184, height: 900 })).toBe("rect(0px, 1440px, 900px, 256px)");
  expect(scrollViewportClip({ x: -1280, y: 900, width: 1280, height: 720 })).toBe("rect(900px, 0px, 1620px, -1280px)");
});

test("modifier sheets and resize borders cannot cover the rail or a neighboring monitor", () => {
  const viewport = { x: 256, y: 0, width: 1184, height: 900 };
  expect(scrollSheetClip({ x: -928, y: 0, width: 1184, height: 900 }, viewport)).toBe("inset(50%)");
  expect(scrollSheetClip({ x: 0, y: 0, width: 1440, height: 900 }, viewport)).toBe("inset(0px 0px 0px 256px)");
  expect(scrollSheetClip({ x: 1200, y: -100, width: 600, height: 1100 }, viewport)).toBe("inset(100px 360px 100px 0px)");
  expect(scrollSheetClip({ x: 1500, y: 0, width: 1000, height: 900 }, viewport)).toBe("inset(50%)");
});
