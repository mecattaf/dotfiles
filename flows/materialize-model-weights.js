export const meta = {
  name: "materialize-model-weights",
  description: "Refuses: model bytes reach a host only through the operator's local-models-borrow transaction, which a flow cannot run",
  pools: ["flow-build"],
  argsSchema: {
    type: "object",
    required: ["flake", "models"],
    properties: {
      flake: { type: "string", minLength: 1 },
      models: {
        type: "array",
        items: { type: "string", minLength: 1 }
      }
    },
    additionalProperties: false
  },
  maxNodes: 64,
  selectors: []
};

(async () => {
  // The weight plane lives outside Nix. There is no `.#models.<id>` store
  // path to build: a catalogue row in lib/local-models.nix is an identity and
  // a provenance record, the NAS Library holds the bytes, and a host's wanted
  // set is rendered to /etc/local-models/wanted.json by a switch that moves
  // nothing. Copying those bytes onto a host is a root-held operator
  // transaction with its own lock, free-space gate and hash verification:
  //
  //   sudo local-models-borrow --dry-run
  //   sudo local-models-borrow --yes
  //
  // This flow runs as the tally daemon's user and cannot hold that lock, so
  // it refuses loudly rather than pretending to materialize anything. It stays
  // registered so the fact is visible in `tally flow` listings.
  const requested = [...new Set(args.models)];
  throw new Error(
    [
      "materialize-model-weights: refusing.",
      `Requested ${requested.length} artifact id(s): ${JSON.stringify(requested)}.`,
      "Model bytes are not built from the flake; they are borrowed from the NAS Library",
      "by an operator with `sudo local-models-borrow --dry-run` then `--yes` on the host",
      "whose /etc/local-models/wanted.json names them (docs/local-ai/README.md)."
    ].join(" ")
  );
})();
