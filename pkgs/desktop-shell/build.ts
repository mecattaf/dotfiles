import solidPlugin from "@gpuix/solid/bun-plugin";
// Bundle Solid so the plugin replaces Node's server conditional export with
// the reactive client runtime. Externalizing solid-js silently loses reactivity.
const result = await Bun.build({
  entrypoints: ["./main.ts"],
  target: "bun",
  outdir: "dist",
  plugins: [
    solidPlugin,
    {
      name: "native-addon-boundary",
      setup(build) {
        // Externalize only the binary loader, not its pure-JS host subpath.
        // Bun 1.3 loses the namespace binding for export-star of an external
        // subpath when @gpuix/solid is loaded through a dynamic import.
        build.onResolve({ filter: /^@gpuix\/native$/ }, () => ({
          path: "@gpuix/native",
          external: true,
        }));
      },
    },
  ],
  external: ["dbus-next"],
});
if (!result.success) {
  console.error(result.logs);
  process.exit(1);
}
