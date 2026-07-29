export const meta = {
  name: "materialize-model-weights",
  description: "Gate on #104 closing, then materialize allowlisted model weights on coordinator; replay-safe per artifact",
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
  const retiredModels = new Set([
    "deepseek-v4-flash-q4-imatrix",
    "deepseek-v4-flash-mtp"
  ]);
  const models = [...new Set(args.models)];
  for (const model of models) {
    if (retiredModels.has(model)) {
      throw new Error(`retired DS4 artifact is not a materialization target: ${model}`);
    }
  }

  // The whole campaign is armed but inert until the LaCie post-restore umbrella
  // closes and the SSD space is real. This node IS the gate: it fails until then.
  await sh(
    [
      "bash",
      "-c",
      'test "$(gh issue view 104 -R mecattaf/dotfiles --json state -q .state)" = "CLOSED"'
    ],
    { pools: ["flow-build"], key: "gate-issue-104", evidence: ["exit:0"], label: "gate-issue-104" }
  );

  // Weight downloads serialize through the build lane (capacity 1) on purpose:
  // one WAN link, and this keeps the lane honest against the nightly deploy.
  // Interrupted runs replay cheaply — each artifact node is keyed, so completed
  // downloads collapse to Reused on re-run.
  const coordinatorBuilt = [];
  for (const model of models) {
    const built = await sh(
      ["nix", "build", `${args.flake}#models.${model}`, "--no-link", "--print-out-paths"],
      {
        pools: ["flow-build"],
        key: `coordinator-${model}`,
        evidence: ["exit:0"],
        label: `coordinator:${model}`
      }
    );
    coordinatorBuilt.push({ model, result: built.result });
  }

  // Post-materialization smoke: the coordinator rebuild must now see every
  // allowlisted deployment resolvable without any network fetch.
  return sh(
    ["nix", "build", `${args.flake}#nixosConfigurations.coordinator.config.system.build.toplevel`, "--no-link"],
    {
      pools: ["flow-build"],
      key: "closure-proof",
      brief: { coordinator: coordinatorBuilt },
      evidence: ["exit:0"],
      label: "closure-proof"
    }
  );
})();
