export const meta = {
  name: "errata-map",
  description: "Map every errata candidate in the reshaped notes (annex + weak-claims + discovery sweep), quorum-verify each, emit a decision ledger for Tom",
  pools: ["codex-window", "worker-gpu", "build"],
  argsSchema: {
    type: "object",
    required: ["notesRepo", "outDir", "maxRows"],
    properties: {
      notesRepo: { type: "string", pattern: "^/" },
      outDir: { type: "string", pattern: "^/" },
      maxRows: { type: "integer", minimum: 1, maximum: 120 }
    },
    additionalProperties: false
  },
  maxNodes: 400,
  selectors: ["errata-review"]
};

(async () => {
  // Gate: the notes cutover (prompt A) must have landed — inspections run
  // against the live tree, never the snapshot.
  await sh(
    ["bash", "-c", 'test -d "$1/journal/2026/07" && git -C "$1" rev-parse --verify HEAD', "cutover-gate", args.notesRepo],
    { pools: ["build"], key: "cutover-gate", evidence: ["exit:0"], label: "cutover-gate" }
  );

  // Discovery: the errata annex is the STARTING POINT, not the boundary
  // (ruling 2026-07-25) — sweep for more.
  const discovery = await codex(
    [
      `Work read-only in the notes repo at ${args.notesRepo}. Build the complete`,
      "errata candidate list for the July reshape. Sources, in order: (1) the",
      "harvested errata annex (the semantic-corrections contract copied into the",
      "campaign record at cutover — locate it under the july23-notes-reshape",
      "campaign folder or references/archive/restructuring-history/); (2) the",
      "weak-claims table from the harvested MORNING-HANDOFF (17 rows covering 25",
      "journal entries); (3) your own discovery sweep of journal/2026/07/ for",
      "entries whose 'done' language outruns cited evidence — the annex is a",
      "starting point, more files are expected to need corrections. NO-GO zones:",
      "never read or quote references/learnings/, references/statsforstartups.com/,",
      "or any health/leg-injury material — pointer-only if a claim touches them.",
      "Output STRICT JSON only, no prose, shape:",
      '{"rows":[{"id":"<short-slug>","entry":"<repo-relative path>",',
      '"claim":"<the specific overstated/contested claim>",',
      '"sources":["<evidence paths/refs to check>"],',
      '"origin":"annex|weak-claims|discovery"}]}'
    ].join(" "),
    { key: "discovery", label: "discovery" }
  );

  let rows;
  try {
    rows = JSON.parse(discovery.result).rows;
  } catch (parseError) {
    const repaired = await codex(
      `Your previous output was not valid JSON (${String(parseError)}). Re-emit the exact same errata rows as STRICT JSON only, shape {"rows":[{"id","entry","claim","sources","origin"}]}. Previous output: ${discovery.result}`,
      { key: "discovery@1", label: "discovery-repair" }
    );
    rows = JSON.parse(repaired.result).rows;
  }
  const bounded = rows.slice(0, args.maxRows);
  log(`errata-map: ${rows.length} candidate rows, inspecting ${bounded.length}`);

  // Per-row verdicts from three family-diverse local members on worker-gpu.
  const selected = members("errata-review", { count: 3, diversity: "family" });
  const verdictSchema = {
    type: "object",
    required: ["verdict", "rationale"],
    properties: {
      verdict: { type: "string", enum: ["stands", "correct-language", "finish-work"] },
      rationale: { type: "string", minLength: 1 }
    },
    additionalProperties: false
  };

  const judged = [];
  for (const row of bounded) {
    const votes = await parallel(
      selected.map(member => () =>
        local(
          [
            `Journal entry ${row.entry} makes this claim: "${row.claim}".`,
            `Evidence to weigh: ${JSON.stringify(row.sources)}.`,
            "Verdict options: 'stands' (claim is adequately supported as written),",
            "'correct-language' (work happened but the entry overstates it — the",
            "prose should be bounded), 'finish-work' (the claim describes work",
            "that must actually be completed). Choose exactly one and justify",
            "briefly against the evidence, not vibes."
          ].join(" "),
          {
            member,
            settle: true,
            resultSchema: verdictSchema,
            key: `insp-${row.id}-${member.id}`,
            label: `insp:${row.id}:${member.id}`
          }
        )
      ),
      { settle: true }
    );
    const valid = votes.filter(vote => vote && vote.verdict === "pass" && vote.result);
    const tally = {};
    for (const vote of valid) {
      tally[vote.result.verdict] = (tally[vote.result.verdict] || 0) + 1;
    }
    let consensus = "CONTESTED";
    for (const option of ["stands", "correct-language", "finish-work"]) {
      if ((tally[option] || 0) >= 2) {
        consensus = option;
      }
    }
    judged.push({
      row,
      consensus,
      votes: valid.map((vote, index) => ({
        member: selected[index] ? selected[index].id : "unknown",
        verdict: vote.result.verdict,
        rationale: vote.result.rationale
      }))
    });
  }

  // Deterministic ledger assembly in-script — Tom rules only on CONTESTED and
  // finish-work rows; stands/correct-language rows are pre-dispositioned.
  const header = "id\tentry\torigin\tconsensus\tclaim\tvote-detail";
  const lines = judged.map(item =>
    [
      item.row.id,
      item.row.entry,
      item.row.origin,
      item.consensus,
      item.row.claim.replace(/\t/g, " "),
      item.votes.map(vote => `${vote.member}:${vote.verdict}`).join(",")
    ].join("\t")
  );
  const tsv = [header].concat(lines).join("\n") + "\n";

  await sh(
    ["bash", "-c", 'mkdir -p "$2" && printf %s "$1" > "$2/ERRATA-LEDGER.tsv"', "ledger-writer", tsv, args.outDir],
    { pools: ["build"], key: "write-ledger", evidence: ["exit:0"], label: "write-ledger" }
  );

  const contested = judged.filter(item => item.consensus === "CONTESTED" || item.consensus === "finish-work");
  return {
    inspected: judged.length,
    contestedForTom: contested.map(item => ({
      id: item.row.id,
      entry: item.row.entry,
      consensus: item.consensus,
      votes: item.votes
    })),
    ledger: `${args.outDir}/ERRATA-LEDGER.tsv`
  };
})();
