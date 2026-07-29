export const meta = {
  name: "paper-e2e",
  description:
    "One paper end-to-end: fetch, per-page mechanical + VLM consensus OCR, assemble, chunk, embed, index, receipt",
  pools: ["coordinator-gpu", "flow-build"],
  argsSchema: {
    type: "object",
    required: [
      "paperId",
      "title",
      "sourceUrl",
      "sha256",
      "pageCount",
      "dataRoot",
      "tools",
      "bash",
      "dpi",
      "ocrModel",
      "refineModel",
      "embedModel",
      "minAgreementPermille"
    ],
    properties: {
      paperId: { type: "string", pattern: "^[0-9a-f-]{36}$" },
      title: { type: "string", minLength: 1 },
      sourceUrl: { type: "string", pattern: "^(https|file)://" },
      sha256: { type: "string", pattern: "^[0-9a-f]{64}$" },
      pageCount: { type: "integer", minimum: 1, maximum: 1500 },
      dataRoot: { type: "string", pattern: "^/" },
      tools: { type: "string", pattern: "^/" },
      bash: { type: "string", pattern: "^/" },
      dpi: { type: "integer", minimum: 150, maximum: 600 },
      ocrModel: { type: "string", minLength: 1 },
      refineModel: { type: "string", minLength: 1 },
      embedModel: { type: "string", minLength: 1 },
      minAgreementPermille: { type: "integer", minimum: 0, maximum: 1000 }
    },
    additionalProperties: false
  },
  maxNodes: 10000,
  iterationCap: 10000,
  selectors: []
};

function pad3(n) {
  return String(n).padStart(3, "0");
}

const root = `${args.dataRoot}/papers/${args.paperId}`;
const blob = `${args.dataRoot}/blobs/${args.sha256}.pdf`;
const tool = name => `${args.tools}/${name}.sh`;

function run(name, argvTail, opts) {
  return sh([args.bash, tool(name), ...argvTail], opts);
}

async function resolvePage(page) {
  const p = pad3(page);
  const png = `${root}/renders/${p}.png`;
  const mechDir = `${root}/mech/${p}`;
  const vlm8b = `${root}/vlm/${p}.md`;
  const vlm32b = `${root}/refine/${p}.md`;

  await run("raster", [blob, String(page), String(args.dpi), png], {
    pools: ["flow-build"],
    key: `raster-${p}`,
    label: `raster-${p}`,
    evidence: ["exit:0", `artifact:${png}`, "hash:sha256"]
  });

  const mech = await run("mech", [blob, String(page), mechDir], {
    pools: ["flow-build"],
    key: `mech-${p}`,
    label: `mech-${p}`,
    evidence: ["exit:0", `artifact:${mechDir}/mech.json`, "hash:sha256"],
    settle: true
  });
  const mechOk = mech.verdict === "pass" && !mech.error;
  const mechRef = `${mechDir}/poppler.txt`;

  const ocr = await run("vlm", [png, args.ocrModel, vlm8b], {
    pools: ["coordinator-gpu"],
    priority: "low",
    runtimeMaxSec: 1800,
    key: `vlm8b-${p}`,
    label: `vlm8b-${p}`,
    evidence: ["exit:0", `artifact:${vlm8b}`, "hash:sha256"],
    settle: true
  });
  const ocrOk = ocr.verdict === "pass" && !ocr.error;

  if (ocrOk && mechOk) {
    const cmp = await run(
      "compare",
      [mechRef, vlm8b, `${root}/verdicts/${p}-8b.json`, String(args.minAgreementPermille)],
      {
        pools: ["flow-build"],
        key: `cmp8b-${p}`,
        label: `cmp8b-${p}`,
        evidence: ["exit:0", `artifact:${root}/verdicts/${p}-8b.json`, "hash:sha256"],
        settle: true
      }
    );
    if (cmp.verdict === "pass" && !cmp.error) {
      return { page, source: "vlm8b" };
    }
  }

  // Specialist lane: 8B unavailable or disagreed with the mechanical reference.
  const refine = await run("vlm", [png, args.refineModel, vlm32b], {
    pools: ["coordinator-gpu"],
    priority: "low",
    runtimeMaxSec: 1800,
    key: `vlm32b-${p}`,
    label: `vlm32b-${p}`,
    evidence: ["exit:0", `artifact:${vlm32b}`, "hash:sha256"],
    settle: true
  });
  const refineOk = refine.verdict === "pass" && !refine.error;

  if (!refineOk) {
    if (ocrOk) {
      return { page, source: "vlm8b", disputed: true };
    }
    if (mechOk) {
      return { page, source: "mech", disputed: true };
    }
    throw new Error(`page ${page}: no successful protocol`);
  }

  const reference = mechOk ? mechRef : ocrOk ? vlm8b : null;
  if (reference !== null) {
    const cmp = await run(
      "compare",
      [reference, vlm32b, `${root}/verdicts/${p}-32b.json`, String(args.minAgreementPermille)],
      {
        pools: ["flow-build"],
        key: `cmp32b-${p}`,
        label: `cmp32b-${p}`,
        evidence: ["exit:0", `artifact:${root}/verdicts/${p}-32b.json`, "hash:sha256"],
        settle: true
      }
    );
    if (cmp.verdict === "pass" && !cmp.error) {
      return { page, source: "vlm32b" };
    }
    return { page, source: "vlm32b", disputed: true };
  }
  return { page, source: "vlm32b", disputed: true };
}

(async () => {
  await run("fetch", [args.sourceUrl, args.sha256, blob], {
    pools: ["flow-build"],
    key: "fetch",
    label: "fetch",
    runtimeMaxSec: 600,
    evidence: ["exit:0", `artifact:${blob}`, "hash:sha256"]
  });

  const pageNumbers = [];
  for (let page = 1; page <= args.pageCount; page += 1) {
    pageNumbers.push(page);
  }
  const settled = await parallel(
    pageNumbers.map(page => () => resolvePage(page)),
    { settle: true }
  );

  const resolved = [];
  const failedPages = [];
  settled.forEach((outcome, index) => {
    if (outcome.ok) {
      resolved.push(outcome.value);
    } else {
      failedPages.push(pageNumbers[index]);
    }
  });
  if (resolved.length === 0) {
    throw new Error("no page resolved; refusing to assemble an empty paper");
  }

  const assembleSpecs = resolved.map(r => `${r.page}:${r.source}`);
  const receiptSpecs = resolved.map(
    r => `${r.page}:${r.source}${r.disputed ? "-disputed" : ""}`
  );
  const paperMd = `${root}/canonical/paper.md`;
  const chunks = `${root}/canonical/chunks.json`;
  const embeddings = `${root}/canonical/embeddings.json`;
  const index = `${root}/canonical/index.jsonl`;
  const receipt = `${root}/canonical/receipt.json`;

  await run(
    "assemble",
    [root, args.paperId, args.sha256, args.title, paperMd, ...assembleSpecs],
    {
      pools: ["flow-build"],
      key: "assemble",
      label: "assemble",
      evidence: ["exit:0", `artifact:${paperMd}`, "hash:sha256"]
    }
  );

  await run("chunk", [paperMd, args.paperId, chunks], {
    pools: ["flow-build"],
    key: "chunk",
    label: "chunk",
    evidence: ["exit:0", `artifact:${chunks}`, "hash:sha256"]
  });

  await run("embed", [chunks, args.embedModel, embeddings], {
    pools: ["coordinator-gpu"],
    priority: "low",
    runtimeMaxSec: 3600,
    key: "embed",
    label: "embed",
    evidence: ["exit:0", `artifact:${embeddings}`, "hash:sha256"]
  });

  await run("index", [chunks, embeddings, index], {
    pools: ["flow-build"],
    key: "index",
    label: "index",
    evidence: ["exit:0", `artifact:${index}`, "hash:sha256"]
  });

  await run("receipt", [root, args.paperId, receipt, ...receiptSpecs], {
    pools: ["flow-build"],
    key: "receipt",
    label: "receipt",
    evidence: ["exit:0", `artifact:${receipt}`, "hash:sha256"]
  });

  return {
    schemaVersion: 1,
    paperId: args.paperId,
    pageCount: args.pageCount,
    resolvedCount: resolved.length,
    disputedPages: resolved.filter(r => r.disputed).map(r => r.page),
    failedPages,
    bySource: {
      vlm8b: resolved.filter(r => r.source === "vlm8b").length,
      vlm32b: resolved.filter(r => r.source === "vlm32b").length,
      mech: resolved.filter(r => r.source === "mech").length
    },
    receiptPath: receipt
  };
})();
