import { defineConfig } from "vitest/config"

// U-A12 LAKE-SERIALIZER. Scoped to this package, for the same reason
// packages/schema's config is: the root has no suite of its own, and
// packages/planning's 86 tests are U-A7's and must stay provably unchanged, so
// this config never reaches them.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node"
  }
})
