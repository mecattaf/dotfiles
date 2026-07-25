export const meta = {
  name: "materialize-model-weights",
  description: "Gate on #104 closing, then materialize allowlisted model weights on coordinator and worker; replay-safe per artifact",
  pools: ["build"],
  argsSchema: {
    type: "object",
    required: ["coordinatorFlake", "workerFlake", "coordinatorModels", "workerModels"],
    properties: {
      coordinatorFlake: { type: "string", minLength: 1 },
      workerFlake: { type: "string", minLength: 1 },
      coordinatorModels: {
        type: "array",
        items: { type: "string", minLength: 1 }
      },
      workerModels: {
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
  // The whole campaign is armed but inert until the LaCie post-restore umbrella
  // closes and the SSD space is real. This node IS the gate: it fails until then.
  await sh(
    [
      "bash",
      "-c",
      'test "$(gh issue view 104 -R mecattaf/dotfiles --json state -q .state)" = "CLOSED"'
    ],
    { pools: ["build"], key: "gate-issue-104", evidence: ["exit:0"], label: "gate-issue-104" }
  );

  // Weight downloads serialize through the build lane (capacity 1) on purpose:
  // one WAN link, and this keeps the lane honest against the nightly deploy.
  // Interrupted runs replay cheaply — each artifact node is keyed, so completed
  // downloads collapse to Reused on re-run.
  const coordinatorBuilt = [];
  for (const model of args.coordinatorModels) {
    const built = await sh(
      ["nix", "build", `${args.coordinatorFlake}#models.${model}`, "--no-link", "--print-out-paths"],
      {
        pools: ["build"],
        key: `coordinator-${model}`,
        evidence: ["exit:0"],
        label: `coordinator:${model}`
      }
    );
    coordinatorBuilt.push({ model, result: built.result });
  }

  const workerBuilt = [];
  for (const model of args.workerModels) {
    const built = await sh(
      ["nix", "build", `${args.workerFlake}#models.${model}`, "--no-link", "--print-out-paths"],
      {
        pools: ["build"],
        executor: "worker",
        key: `worker-${model}`,
        evidence: ["exit:0"],
        label: `worker:${model}`
      }
    );
    workerBuilt.push({ model, result: built.result });
  }

  // Post-materialization smoke: the coordinator rebuild must now see every
  // allowlisted deployment resolvable without any network fetch.
  return sh(
    ["nix", "build", `${args.coordinatorFlake}#nixosConfigurations.coordinator.config.system.build.toplevel`, "--no-link"],
    {
      pools: ["build"],
      key: "closure-proof",
      brief: { coordinator: coordinatorBuilt, worker: workerBuilt },
      evidence: ["exit:0"],
      label: "closure-proof"
    }
  );
})();
