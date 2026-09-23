// The puller's floor connection: the link's own rpcFloor client (Effect RPC over HTTP, its retry classifier and
// per-call ceilings), held open in a scope for the life of the process.
import { Effect, Exit, Scope } from "effect"
import { rpcFloor } from "@substrate/link/floor.ts"
import type { FloorOptions } from "@substrate/link/floor.ts"
import { floorPort } from "./puller.ts"
import type { FloorPort } from "./puller.ts"

export const connectFloor = async (o: FloorOptions): Promise<{ port: FloorPort; close: () => Promise<void> }> => {
  const scope = await Effect.runPromise(Scope.make())
  const api = await Effect.runPromise(Scope.provide(scope)(rpcFloor(o)))
  return { port: floorPort(api), close: () => Effect.runPromise(Scope.close(scope, Exit.void)) }
}
