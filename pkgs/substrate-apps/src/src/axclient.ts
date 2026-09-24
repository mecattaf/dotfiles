/**
 * The ax client. protobuf over plain gRPC with h2c, loaded at runtime from
 * ax.proto with @grpc/proto-loader. No codegen toolchain is involved and no
 * generated file is checked in.
 *
 * `service AX` declares nineteen rpcs. There is NO CreateTask: the proto's own
 * comment says manifests are parsed client-side and submitted through the typed
 * Update* rpcs, so UpdateTask is the dispatch rpc. See DESIGN.md.
 */
import { deployConfig } from "./deploy-config.ts";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as grpc from "@grpc/grpc-js";
import * as protoLoader from "@grpc/proto-loader";

/**
 * A-17 of the 2026-09-23 review. `DEFAULT_PROTO_PATH` used to BE the path
 * below: a machine-local absolute path outside any repository, so on a host
 * where that checkout is absent `protoLoader.loadSync` throws ENOENT inside
 * `connect` and the program does not start at all. A nix module cannot paper
 * over that, and the module in dotfiles runs this program.
 *
 * `proto/ax.proto` is now vendored here: 8236 bytes, Apache-2.0, carrying its
 * own licence header, copied verbatim and never edited. The resolution order
 * is env override, then the vendored copy, then the machine-local path, which
 * stays as the last fallback so nothing that works today stops working.
 */
export const PROTO_PATH_ENV_VAR = "AX_CONWIP_PROTO_PATH";

/**
 * Where the proto lived before it was vendored. The last fallback, not the
 * default: `axProtoFallbackPath` in the substrate config, else the vendored path.
 */
export const MACHINE_LOCAL_PROTO_PATH: string = deployConfig().axProtoFallbackPath ?? vendoredProtoPath();

/** The vendored copy, resolved relative to this module rather than to cwd. */
function vendoredProtoPath(): string {
  return resolve(dirname(fileURLToPath(import.meta.url)), "..", "proto", "ax.proto");
}

export const VENDORED_PROTO_PATH = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "proto",
  "ax.proto",
);

export function resolveProtoPath(
  env: Record<string, string | undefined> = process.env,
  vendored: string = VENDORED_PROTO_PATH,
): string {
  const override = env[PROTO_PATH_ENV_VAR];
  if (override !== undefined && override !== "") return override;
  if (existsSync(vendored)) return vendored;
  return MACHINE_LOCAL_PROTO_PATH;
}

export const DEFAULT_PROTO_PATH = resolveProtoPath();

export interface AxTask {
  apiVersion?: string;
  kind?: string;
  metadata?: { name?: string; atespace?: string };
  spec?: Record<string, unknown>;
  status?: { phase?: string; id?: string; actor?: string };
}

export interface WatchEvent {
  readonly action: string;
  readonly phase: string;
}

/* eslint-disable @typescript-eslint/no-explicit-any */
type AnyClient = any;

export class AxClient {
  readonly #client: AnyClient;
  readonly atespace: string;

  private constructor(client: AnyClient, atespace: string) {
    this.#client = client;
    this.atespace = atespace;
  }

  /** Load ax.proto and dial the server over h2c (insecure credentials). */
  static connect(address: string, atespace = "default", protoPath = DEFAULT_PROTO_PATH): AxClient {
    const def = protoLoader.loadSync(protoPath, {
      keepCase: false,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true,
    });
    const pkg = grpc.loadPackageDefinition(def) as AnyClient;
    const Ctor = pkg.ax?.v1alpha1?.AX;
    if (typeof Ctor !== "function") {
      throw new Error(`ax.v1alpha1.AX not found in ${protoPath}`);
    }
    return new AxClient(new Ctor(address, grpc.credentials.createInsecure()), atespace);
  }

  close(): void {
    this.#client.close();
  }

  #unary<T>(method: string, request: unknown): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      this.#client[method](request, (err: Error | null, res: T) => {
        if (err) reject(err);
        else resolve(res);
      });
    });
  }

  updateTask(task: AxTask): Promise<AxTask> {
    return this.#unary<AxTask>("UpdateTask", { task });
  }

  getTask(name: string): Promise<AxTask> {
    return this.#unary<AxTask>("GetTask", { atespace: this.atespace, name });
  }

  listTasks(limit = 0, offset = 0): Promise<{ tasks?: AxTask[] }> {
    return this.#unary<{ tasks?: AxTask[] }>("ListTasks", { atespace: this.atespace, limit, offset });
  }

  /**
   * Drain WatchTask, the one server-streaming rpc, to its end. ax closes the
   * stream on Running, Completed or Failed, so the end of the stream is a
   * signal to read the phase again, not a release in itself.
   */
  watchTaskToEnd(name: string, timeoutMs: number): Promise<WatchEvent[]> {
    return new Promise<WatchEvent[]>((resolve, reject) => {
      const events: WatchEvent[] = [];
      const call = this.#client.WatchTask({ atespace: this.atespace, name });
      const timer = setTimeout(() => {
        call.cancel();
        resolve(events);
      }, timeoutMs);
      call.on("data", (resp: { action?: string; task?: AxTask }) => {
        events.push({ action: resp.action ?? "", phase: resp.task?.status?.phase ?? "" });
      });
      call.on("end", () => {
        clearTimeout(timer);
        resolve(events);
      });
      call.on("error", (err: Error & { code?: number }) => {
        clearTimeout(timer);
        if (err.code === grpc.status.CANCELLED) resolve(events);
        else reject(err);
      });
    });
  }
}
