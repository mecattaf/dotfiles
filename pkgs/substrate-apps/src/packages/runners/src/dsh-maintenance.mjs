// Trusted DSH tool subprocesses: argv comes only from the operator's runtime
// configuration. Model arguments never become command text, flags or environment.
import { spawn } from "node:child_process";

export async function runFixedCommand(argv, { signal, timeoutMs = 30_000, maxBytes = 16_384 } = {}) {
  if (!Array.isArray(argv) || !argv.length || argv.some(a => typeof a !== "string") || !argv[0].startsWith("/")) throw new Error("maintenance argv must be fixed and absolute");
  if (signal?.aborted) throw new Error("maintenance call cancelled before launch");
  return new Promise((resolve, reject) => {
    const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith("PROJECT_") && !key.startsWith("DSH_") && !/(?:_TOKEN|_KEY|_SECRET|_PASSWORD)$/i.test(key)));
    const child = spawn(argv[0], argv.slice(1), { env, shell: false, stdio: ["ignore", "pipe", "pipe"] });
    const out = [], err = [];
    let bytes = 0, failure, kill;
    const stop = reason => {
      failure ??= reason;
      child.kill("SIGTERM");
      kill ??= setTimeout(() => child.kill("SIGKILL"), 500);
      kill.unref?.();
    };
    const onAbort = () => stop("maintenance call cancelled");
    signal?.addEventListener("abort", onAbort, { once: true });
    const timer = setTimeout(() => stop("maintenance command timed out"), timeoutMs);
    timer.unref?.();
    const receive = target => data => {
      bytes += data.length;
      if (bytes > maxBytes) { stop("maintenance command output exceeded its limit"); return; }
      target.push(data);
    };
    child.stdout.on("data", receive(out)); child.stderr.on("data", receive(err));
    child.on("error", error => { failure ??= error.message; });
    child.on("close", code => {
      clearTimeout(timer); if (kill) clearTimeout(kill);
      signal?.removeEventListener("abort", onAbort);
      if (failure) reject(new Error(failure));
      else resolve({ exitCode: code ?? 1, stdout: Buffer.concat(out).toString("utf8").trim(), stderr: Buffer.concat(err).toString("utf8").trim() });
    });
  });
}

export function registerMaintenanceTools(ctx, defineTool, binding) {
  const output = { schema: { type: "object", additionalProperties: false, properties: {
    exitCode: { type: "number", required: true }, stdout: { type: "string", required: true }, stderr: { type: "string", required: true },
  } }, render: (_args, value) => [{ type: "text", text: JSON.stringify(value) }] };
  for (const [name, description, command] of [
    ["fleet_update_start", "Start the authorized nightly fleet-update service using its fixed launcher. The launch receipt is acceptance, not upgrade completion. No arguments.", binding.command],
    ["fleet_update_status", "Read the durable nightly fleet-update job and completion receipt using the fixed status command. No arguments.", binding.statusCommand],
  ]) ctx.tools.register(defineTool({ name, description, parameters: {}, output,
    async execute(args, exec) {
      if (Object.keys(args).length !== 0) throw new Error("maintenance tools accept no arguments");
      return runFixedCommand(command, { signal: exec.signal });
    },
  }));
}
