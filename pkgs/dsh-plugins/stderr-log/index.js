// stderr-log: the `herdr` profile's log sink. dsh 0.2.1 mounts no logger
// exporter that prints: Cordis keeps every ctx.logger message in an in-memory
// buffer, and headless writes only reasoning and `dsh: <error>` lines to
// stderr, so a plugin's warnings and its startup line are lost. This plugin
// prints error, info and warn messages (never debug) to stderr, one
// `dsh: <logger> <type>: <text>` line each. Messages logged before it mounted
// come from the logger's buffer first, so row order does not matter.
// Plain ESM; the only import is a Node builtin.
import { format } from 'node:util'

export const name = '@mecattaf/stderr-log'

const SHOWN = new Set(['error', 'info', 'warn'])
const MAX_LINE = 4096

/** One log message as the line this sink writes, or undefined to skip it. */
export function render(message) {
  if (!SHOWN.has(message?.type)) return undefined
  const args = Array.isArray(message.args) ? message.args.slice() : []
  // Cordis' %C and %c (a highlighted value) print plain here.
  if (typeof args[0] === 'string') args[0] = args[0].replace(/%([Cc])/g, '%s')
  const text = format(...args)
    .split(/\r?\n/)
    .map((line) => (line.length > MAX_LINE ? `${line.slice(0, MAX_LINE)}...` : line))
    .join('\n')
  return `dsh: ${message.name} ${message.type}: ${text}\n`
}

export function apply(ctx, _config, write = (line) => void process.stderr.write(line)) {
  const emit = (message) => {
    const line = render(message)
    if (line !== undefined) write(line)
  }
  // Read the backlog and register in one synchronous step, so no message is
  // printed twice or missed.
  for (const message of ctx.logger.buffer ?? []) emit(message)
  ctx.logger.exporter({ levels: { default: 2 }, export: emit })
}
