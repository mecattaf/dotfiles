export const meta = {
  name: "paper-e2e",
  description:
    "One paper end-to-end: fetch, per-page mech-first OCR with VLM consensus fallback, assemble, chunk, embed, index, receipt",
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
      "minAgreementPermille",
      "mechSelfAgreementPermille",
      "mechMinWords",
      "tableMinNumericRun"
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
      minAgreementPermille: { type: "integer", minimum: 0, maximum: 1000 },
      mechSelfAgreementPermille: { type: "integer", minimum: 0, maximum: 1000 },
      mechMinWords: { type: "integer", minimum: 0 },
      tableMinNumericRun: { type: "integer", minimum: 2 }
    },
    additionalProperties: false
  },
  maxNodes: 11000,
  iterationCap: 11000,
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

// #145: a cancelled node is an operator instruction, never OCR evidence. The
// settled verdicts below otherwise make `tally flow cancel` indistinguishable
// from a genuine disagreement: the 2026-08-03 incident cancelled in-flight
// vlm32b refines and the fallback accepted vlm8b-disputed for those pages,
// then wrote the receipt — freezing the paper at degraded quality forever
// (receipted papers are never retried). A cancelled node instead aborts the
// page, and one cancelled page aborts the paper before assembly, so no
// receipt exists and the next drain session redoes the paper in full.
const CANCELLED_MARK = "#145-cancelled";
function guardCancelled(result, page, node) {
  if (result.verdict === "cancelled") {
    throw new Error(`page ${page}: ${node} cancelled by operator (${CANCELLED_MARK})`);
  }
}

async function resolvePage(page) {
  const p = pad3(page);
  const png = `${root}/renders/${p}.png`;
  const mechDir = `${root}/mech/${p}`;
  const vlm8b = `${root}/vlm/${p}.md`;
  const vlm32b = `${root}/refine/${p}.md`;

  const mech = await run("mech", [blob, String(page), mechDir], {
    pools: ["flow-build"],
    key: `mech-${p}`,
    label: `mech-${p}`,
    evidence: ["exit:0", `artifact:${mechDir}/mech.json`, "hash:sha256"],
    settle: true
  });
  guardCancelled(mech, page, "mech");
  const mechOk = mech.verdict === "pass" && !mech.error;
  const mechRef = `${mechDir}/poppler.txt`;

  // Mech-first shortcut (dotfiles#147): when the two mechanical engines agree
  // with each other AND both cleared the word floor, the digital text layer is
  // the page — resolve without rendering or any GPU node. The floor, not the
  // Dice gate, is what excludes sparse-layer pages (figures, covers, UI-chrome
  // print-to-PDFs) whose engines agree perfectly on text that doesn't cover
  // the visual content; compare.sh's truncation guard stays live because the
  // floor keeps every shortcut reference voucher-eligible.
  if (mechOk) {
    const self = await run(
      "compare",
      [
        mechRef,
        `${mechDir}/mupdf.txt`,
        `${root}/verdicts/${p}-mech.json`,
        String(args.mechSelfAgreementPermille),
        String(args.mechMinWords)
      ],
      {
        pools: ["flow-build"],
        key: `cmpmech-${p}`,
        label: `cmpmech-${p}`,
        evidence: ["exit:0", `artifact:${root}/verdicts/${p}-mech.json`, "hash:sha256"],
        settle: true
      }
    );
    guardCancelled(self, page, "cmpmech");
    if (self.verdict === "pass" && !self.error) {
      // Table gate (Tom's ruling, 2026-08-06: tables route to the VLM lane).
      // The agreement gate above is structurally blind to this one failure:
      // the text layer linearizes a table column-major, poppler and mupdf
      // linearize it identically, so two engines agree perfectly on a reading
      // in which every value survives and every row/column association is
      // lost. Nothing downstream can recover it, and a scrambled table reads
      // as authoritative — so the page goes to the lane that sees it as a
      // picture and emits a real GFM table.
      //
      // Forward cost, measured 2026-08-06 over every page that has resolved
      // source:mech to date: 463 of 2,662, i.e. 17.4% of would-be-shortcut
      // pages now take the VLM lane. That is above the ~12% quoted when the
      // ruling was made — the caption signal alone is 15.6% on this corpus,
      // not 12%, and the numeric-run signal adds the other 1.8 points.
      // tables.sh carries the detector calibration (85% recall, 3.6% false
      // positives) and the reasoning for spending those points.
      const tbl = await run(
        "tables",
        [mechRef, `${root}/verdicts/${p}-tables.json`, String(args.tableMinNumericRun)],
        {
          pools: ["flow-build"],
          key: `tables-${p}`,
          label: `tables-${p}`,
          evidence: ["exit:0", `artifact:${root}/verdicts/${p}-tables.json`, "hash:sha256"],
          settle: true
        }
      );
      guardCancelled(tbl, page, "tables");
      if (tbl.verdict === "pass" && !tbl.error) {
        return { page, source: "mech" };
      }
    }
  }

  // VLM lane: mech failed closed (scanned page), the engines disagreed, or the
  // page carries a table. Only now is the page render needed. A rerouted table
  // page is not bounced straight back by the cmp8b gate below: Dice runs over
  // word multisets, so the linearized mechanical reference still agrees with a
  // properly tabulated VLM transcription of the same cells — the reference is
  // only ever a check on *which words* are present, never on their order.
  await run("raster", [blob, String(page), String(args.dpi), png], {
    pools: ["flow-build"],
    key: `raster-${p}`,
    label: `raster-${p}`,
    evidence: ["exit:0", `artifact:${png}`, "hash:sha256"]
  });

  const ocr = await run("vlm", [png, args.ocrModel, vlm8b], {
    pools: ["coordinator-gpu"],
    priority: "low",
    runtimeMaxSec: 1800,
    key: `vlm8b-${p}`,
    label: `vlm8b-${p}`,
    evidence: ["exit:0", `artifact:${vlm8b}`, "hash:sha256"],
    settle: true
  });
  guardCancelled(ocr, page, "vlm8b");
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
    guardCancelled(cmp, page, "cmp8b");
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
  guardCancelled(refine, page, "vlm32b");
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
    guardCancelled(cmp, page, "cmp32b");
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
  // #145: one cancelled page means the operator is stopping this run. A page
  // that fails for its own reasons is recorded and the paper completes
  // without it; a cancelled page must instead abort the paper here, before
  // assembly, because a written receipt is the one thing that makes the
  // drain never look at this paper again.
  const cancelled = settled.some(
    o => !o.ok && String((o.error && o.error.message) || o.error).includes("#145-cancelled")
  );
  if (cancelled) {
    throw new Error(
      "operator cancelled page work mid-run; aborting before assembly so no receipt locks in a partial result (#145-cancelled)"
    );
  }
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
