export interface CommandResult { exitCode: number; stdout: string; stderr: string }
export function runFixedCommand(argv: readonly string[], options?: { signal?: AbortSignal; timeoutMs?: number; maxBytes?: number }): Promise<CommandResult>;
export function registerMaintenanceTools(ctx: any, defineTool: any, binding: { command: readonly string[]; statusCommand: readonly string[] }): void;
