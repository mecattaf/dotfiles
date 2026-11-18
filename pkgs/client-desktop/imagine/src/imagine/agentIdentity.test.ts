import { expect, test } from "bun:test";
import { AGENT_SESSION_MARKER, isAgentDesktopId, isAgentTerminalTag } from "./agentIdentity";

const derived = "kitty-persist-a6e17a12-3b1c-4d2e-9f00-0123456789ab";
const owners = "kitty-persist-0f3b2a11-3b1c-4d2e-9f00-0123456789ab";

test("agent terminals keep the kitty-persist-<id> class and stay quiet by class alone", () => {
  expect(AGENT_SESSION_MARKER).toBe("a6e17a12");
  expect(isAgentTerminalTag(derived)).toBe(true);
  expect(isAgentDesktopId(derived)).toBe(true);
  expect(isAgentDesktopId("prefix-" + derived)).toBe(true);
});

test("the owner's own persistent windows are not agent windows", () => {
  expect(isAgentTerminalTag(owners)).toBe(false);
  expect(isAgentDesktopId(owners)).toBe(false);
  expect(isAgentDesktopId("domicile-terminal")).toBe(false);
});

test("terminal tags are exact version-4 ids", () => {
  expect(isAgentTerminalTag(derived + "0")).toBe(false);
  expect(isAgentTerminalTag("x" + derived)).toBe(false);
  expect(isAgentTerminalTag(derived.toUpperCase())).toBe(false);
  expect(isAgentTerminalTag("kitty-persist-a6e17a12-3b1c-1d2e-9f00-0123456789ab")).toBe(false);
  expect(isAgentTerminalTag("kitty-persist-a6e17a12-3b1c-4d2e-7f00-0123456789ab")).toBe(false);
  expect(isAgentTerminalTag(undefined)).toBe(false);
});

test("windows opened before the change stay quiet", () => {
  expect(isAgentDesktopId("agencyagent" + "a".repeat(32))).toBe(true);
  expect(isAgentDesktopId("chrome_agencychata6e17a11" + "b".repeat(24))).toBe(true);
  expect(isAgentDesktopId("agencychat" + "c".repeat(32))).toBe(false);
  expect(isAgentTerminalTag("agencyagent" + "a".repeat(32))).toBe(false);
});
