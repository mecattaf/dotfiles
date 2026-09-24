import { defineConfig } from "vitest/config";
export default defineConfig({ test: { name: "puller", include: ["test/**/*.test.ts"], environment: "node", testTimeout: 60000 } });
