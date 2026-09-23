/**
 * From a configured runtime to its Runner. One place, so a new runtime type is
 * one case here plus one adapter file.
 */
import type { Runtime } from "./config.ts";
import type { Runner } from "./job.ts";
import { hostRunner, runtimeTestRunner } from "./host.ts";
import { herdrRunner } from "./herdr.ts";
import { gvisorRunner } from "./gvisor.ts";
import { microvmRunner } from "./microvm.ts";
import { sshRunner } from "./ssh.ts";
import { workerdRunner } from "./workerd.ts";
import { axRunner } from "./ax.ts";

export function runnerFor(name: string, r: Runtime): Runner {
  const t = r.timeoutMs !== undefined ? { timeoutMs: r.timeoutMs } : {};
  switch (r.type) {
    case "host":
      return hostRunner(name, t);
    case "runtime-test":
      return runtimeTestRunner(name, { ...t, ...(r.wrapper !== undefined ? { wrapper: r.wrapper } : {}) });
    case "herdr":
      return herdrRunner(name, {
        ...t,
        ...(r.socket !== undefined ? { socket: r.socket } : {}),
        ...(r.mode !== undefined ? { mode: r.mode } : {}),
        ...(r.plugin !== undefined ? { plugin: r.plugin } : {}),
        ...(r.autoLink !== undefined ? { autoLink: r.autoLink } : {}),
      });
    case "gvisor":
      return gvisorRunner(name, {
        ...t,
        runsc: r.runsc,
        ...(r.state !== undefined ? { state: r.state } : {}),
        ...(r.network !== undefined ? { network: r.network } : {}),
        ...(r.pasta !== undefined ? { pasta: r.pasta } : {}),
      });
    case "microvm":
      return microvmRunner(name, {
        ...t,
        ...(r.nixpkgs !== undefined ? { nixpkgs: r.nixpkgs } : {}),
        ...(r.microvm !== undefined ? { microvm: r.microvm } : {}),
        ...(r.vcpu !== undefined ? { vcpu: r.vcpu } : {}),
        ...(r.memMiB !== undefined ? { memMiB: r.memMiB } : {}),
      });
    case "ssh":
      return sshRunner(name, { ...t, host: r.host });
    case "workerd":
      return workerdRunner(name, {
        ...t,
        ...(r.workerd !== undefined ? { workerd: r.workerd } : {}),
        ...(r.flake !== undefined ? { flake: r.flake } : {}),
        ...(r.compatibilityDate !== undefined ? { compatibilityDate: r.compatibilityDate } : {}),
      });
    case "ax":
      return axRunner(name);
  }
}
