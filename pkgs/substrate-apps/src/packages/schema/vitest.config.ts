import { defineConfig } from "vitest/config"

// U-A8 LAKE-SCHEMA. Scoped to this package: the root has no suite of its own
// and packages/planning's 86 tests are U-A7's, not this unit's (they must stay
// provably unchanged, so this config never reaches them).
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node"
  }
})
