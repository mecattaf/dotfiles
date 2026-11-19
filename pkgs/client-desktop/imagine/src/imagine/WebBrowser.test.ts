import { expect, test } from "bun:test";
import { externalWebCommand } from "./WebBrowser";
test("Chrome receives explicit URL arguments and private browser intent", () => {
  const browser = { command: ["domicile-apps", "chrome"] };
  expect(externalWebCommand(browser, "https://example.com/?q=$HOME", true)).toEqual([
    "domicile-apps", "chrome", "--incognito", "--", "https://example.com/?q=$HOME",
  ]);
  expect(externalWebCommand(browser, "domicile://settings/", false)).toBeUndefined();
  expect(externalWebCommand(undefined, "https://example.com/", false)).toBeUndefined();
});
