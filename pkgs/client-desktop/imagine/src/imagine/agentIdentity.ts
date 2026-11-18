/** Native window identities that Imagine treats as agent-opened: their focus
 * requests are ignored, by class alone, so the rule survives a shell reload
 * without an in-memory reservation. No imports, so its test runs without the
 * desktop SDK. */

/** A persistent terminal an agent asked for. kitty-persist's window class is
 * `kitty-persist-<session id>`; the agent-window helper derives that version-4
 * id from the request with this fixed first group
 * (modules/imagine-helpers/agent-windows/transport.py `session_id`). Ids the
 * owner's own opener chooses never start with it (domicile-persist). */
export const AGENT_SESSION_MARKER = "a6e17a12";
const agentTerminal = "kitty-persist-a6e17a12-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";

/** The exact tag of a terminal request's window. */
export const isAgentTerminalTag = (tag: unknown) =>
  typeof tag === "string" && new RegExp(`^${agentTerminal}$`).test(tag);

/** `agencyagent<hex>` is the class the helper gave terminal windows before
 * they were persistent; windows still open from then stay quiet. */
export const isAgentDesktopId = (value: string) =>
  new RegExp(`${agentTerminal}|agencyagent[0-9a-f]{32}|agencychata6e17a11[0-9a-f]{24}`).test(value);
