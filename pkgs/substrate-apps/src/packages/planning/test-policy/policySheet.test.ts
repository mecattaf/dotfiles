/**
 * The policy sheet: RUL-01's B-Q3, B-Q4 and B-Q5 bound to `ReleasePolicy`
 * fields, each marked `default, unruled`, and the fourth rule filed.
 *
 * These are U-A9's tests. They sit in `test-policy/` and not in `test/`
 * deliberately: `test/` is U-A7's port, 9 files copied byte-identical from the
 * sketch, and `tools/port-copy.sh --check` G6 fails on any file under
 * `packages/planning/{src,test}` the port manifest does not name. The 86 ported
 * tests stay exactly the 86; these are the policy tests beside them.
 *
 * What is tested here that `tools/policy-sheet-diff.mjs` does not already say
 * when it prints an empty diff: that the diff is *not vacuous*. Four mutations
 * of the sheet are driven through the same pure function the tool uses, and
 * each must produce a diff line naming what moved.
 */
import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { defaultReleasePolicy } from "../src/release/evaluator.ts";
import {
	anchorCount,
	cardBlock,
	constantLiteral,
	diffAgainstCard,
	diffPolicyAgainstSheet,
	unionMembers
} from "../../../tools/policy-sheet-diff.mjs";

const REPO = new URL("../../../", import.meta.url).pathname;
const read = (rel: string): string => readFileSync(`${REPO}${rel}`, "utf8");

const sheet = JSON.parse(read("packages/planning/policy/policy-sheet.json"));
const sources = (rel: string): string => read(rel);
const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

const run = (s: unknown = sheet) =>
	diffPolicyAgainstSheet(s, defaultReleasePolicy, sources) as {
		diff: string[];
		checks: Array<{ id: string; ok: boolean; what: string }>;
	};

describe("the sheet", () => {
	it("carries exactly RUL-01's three accepted lines, and one finding", () => {
		expect(sheet.lines.map((line: { id: string }) => line.id)).toEqual(["B-Q3", "B-Q4", "B-Q5"]);
		expect(sheet.findings).toHaveLength(1);
		expect(sheet.findings[0].field).toBe("dropMeteredWhenFreePreferred");
	});

	it("marks every line `default, unruled`, because RULINGS.md carries no ruling for them", () => {
		// TL-2 / D-B2: Tom accepted Q3-Q5 at the sheet's defaults in a
		// transcript on 2026-09-05T23:23. A transcript is not the durable
		// store, so the status stays `default, unruled` and DEFERRED.md keeps
		// the [OPERATOR] row.
		for (const line of sheet.lines) {
			expect(line.status).toBe("default, unruled");
			expect(line.ruled_by).toBe("none");
		}
		expect(sheet.acceptance.decision).toBe("D-B2");
	});

	it("names, for every binding, the source line it marks in place", () => {
		for (const line of sheet.lines) {
			for (const binding of line.bindings) {
				const source = sources(binding.file);
				for (const key of ["declaration_anchor", "value_anchor"]) {
					if (binding[key] === undefined) continue;
					expect(anchorCount(source, binding[key]), `${line.id} ${key}`).toBe(1);
				}
			}
		}
	});
});

describe("the built policy against the sheet", () => {
	it("agrees: the diff is empty", () => {
		const { diff } = run();
		expect(diff).toEqual([]);
	});

	it("passes every check the tool makes, C1 through C7", () => {
		const { checks } = run();
		expect(checks.map((c) => c.id)).toEqual(["C1", "C2", "C3", "C4", "C5", "C6", "C7"]);
		expect(checks.filter((c) => !c.ok)).toEqual([]);
	});

	it("binds B-Q3 to routingPreference, B-Q4 to congestion, B-Q5 to lengthExponent", () => {
		expect(defaultReleasePolicy.routingPreference).toBe("routerOrder");
		expect(defaultReleasePolicy.congestion).toEqual({ _tag: "Wait" });
		expect(defaultReleasePolicy.lengthExponent).toBe(1);
	});

	it("holds B-Q4's second half: the closed list of three escalation triggers", () => {
		// "escalation on capability floor, deadline, or a failed verdict only
		// — a closed list of three triggers" (RUL-01 B-Q4). The closure lives
		// in the union, not in the policy field.
		expect(unionMembers(sources("packages/planning/src/heuristics/localFirst.ts"), "EscalationReason")).toEqual([
			"capabilityFloor",
			"deadline",
			"failedVerdict"
		]);
	});

	it("holds B-Q5 through the named constant, not a literal", () => {
		expect(constantLiteral(sources("packages/planning/src/heuristics/lengthTermFlip.ts"), "DEFAULT_LENGTH_EXPONENT")).toBe(1);
	});

	it("is the whole twelve-field policy the sketch shipped, unchanged", () => {
		// The non-goal: no change to the ported sketch's behaviour. Any edit to
		// any policy value — bound, unbound or filed — is red here.
		expect(defaultReleasePolicy).toEqual({
			kappa: 2,
			medianMultiple: 3,
			runtimeFloorSeconds: 300,
			runtimeCeilingSeconds: 43200,
			redundancyCount: 2,
			redundancyDiversity: "pair",
			minimumBatchSavingSeconds: 60,
			spentThisWindow: 0,
			routingPreference: "routerOrder",
			dropMeteredWhenFreePreferred: true,
			lengthExponent: 1,
			congestion: { _tag: "Wait" }
		});
	});
});

describe("the diff is not vacuous", () => {
	it("one mutated policy value makes the sheet diff non-empty", () => {
		const mutated = clone(sheet);
		mutated.lines[0].bindings[0].value = "catalogOrder";
		const { diff, checks } = run(mutated);
		expect(diff).toEqual([
			'- B-Q3 routingPreference sheet="catalogOrder"',
			'+ B-Q3 routingPreference built="routerOrder"'
		]);
		// VERIFY-parity-tally: the C2 flag itself, not only the diff, must report the mismatch.
		expect(checks.find((c) => c.id === "C2")?.ok).toBe(false);
	});

	it("a dropped escalation trigger makes it non-empty", () => {
		const mutated = clone(sheet);
		const binding = mutated.lines[1].bindings.find((b: { kind: string }) => b.kind === "closedList");
		binding.members = ["capabilityFloor", "deadline"];
		const { diff } = run(mutated);
		expect(diff.join("\n")).toContain("EscalationReason");
	});

	it("a moved anchor makes it non-empty, so a later port drift cannot pass", () => {
		const mutated = clone(sheet);
		mutated.lines[2].bindings[0].value_anchor = "  lengthExponent: 2,";
		const { diff } = run(mutated);
		expect(diff.join("\n")).toContain("value_anchor appears 0 time(s)");
	});

	it("a line whose status is not `default, unruled` is refused before anything else", () => {
		const mutated = clone(sheet);
		mutated.lines[0].status = "ruled";
		const { diff, checks } = run(mutated);
		expect(checks[0].ok).toBe(false);
		expect(diff.join("\n")).toContain('not "default, unruled"');
	});
});

describe("the fourth rule, dropMeteredWhenFreePreferred", () => {
	const finding = sheet.findings[0];

	it("rides unchanged at the value U-A7 ported", () => {
		expect(defaultReleasePolicy.dropMeteredWhenFreePreferred).toBe(true);
		expect(finding.rides_unchanged_value).toBe(true);
	});

	it("is filed, not adopted: it has no RUL-01 line and is in no lines[] binding", () => {
		expect(finding.disposition).toBe("filed, not adopted");
		expect(finding.sheet_line).toBe("none");
		const bound = sheet.lines.flatMap((line: { bindings: Array<{ field?: string }> }) =>
			line.bindings.map((b) => b.field)
		);
		expect(bound).not.toContain("dropMeteredWhenFreePreferred");
	});

	it("is filed in U-E4's form, beside the card and never on it", () => {
		expect(existsSync(`${REPO}${finding.filed_at}`)).toBe(true);
		const filed = read(finding.filed_at);
		expect(filed).toContain("**Default (PROPOSED).**");
		expect(filed).toContain("dropMeteredWhenFreePreferred");
		expect(filed).toContain("NOT modified by this unit");
		// The `>` line is Tom's and must be delivered empty.
		expect(filed).toMatch(/\n>\n/);
	});

	it("adopting it as a fourth default makes the diff non-empty", () => {
		const mutated = clone(sheet);
		mutated.lines[0].bindings.push({
			kind: "policyField",
			field: "dropMeteredWhenFreePreferred",
			value: true,
			file: finding.file,
			value_anchor: finding.value_anchor
		});
		const { diff } = run(mutated);
		expect(diff.join("\n")).toContain("adopted as a default by B-Q3");
	});

	it("moving it into a sheet line, so a value change would need no ruling, is refused", () => {
		const mutated = clone(sheet);
		mutated.findings = [];
		mutated.lines.push({
			id: "B-Q5b",
			question: "invented",
			default_proposed: "invented",
			status: "default, unruled",
			ruled_by: "none",
			bindings: [
				{
					kind: "policyField",
					field: "dropMeteredWhenFreePreferred",
					value: false,
					file: finding.file,
					value_anchor: finding.value_anchor
				}
			]
		});
		const { diff } = run(mutated);
		expect(diff.join("\n")).toContain("dropMeteredWhenFreePreferred sheet=false");
	});
});

describe("the transcription against the card's own text", () => {
	// A verbatim excerpt of cards/RUL-01.md lines 444-481, so this is hermetic:
	// the card is read-only to this repository and is not on every box. The
	// tool's `--against-card` runs the same comparison against the live card;
	// packages/planning/policy/policy-sheet.md §5 records that run.
	const excerpt = read("packages/planning/test-policy/fixtures/rul-01-section-b-excerpt.md");

	it("quotes each question and each `Default (PROPOSED).` sentence exactly", () => {
		expect(diffAgainstCard(sheet, excerpt)).toEqual([]);
	});

	it("finds all three blocks in the excerpt", () => {
		for (const line of sheet.lines) expect(cardBlock(excerpt, line.id)).not.toBeNull();
	});

	it("goes red on a transcription that drifts by one word", () => {
		const mutated = clone(sheet);
		mutated.lines[2].default_proposed = "1.5 until measurement, so the attended/unattended flip is a sign change and nothing more.";
		expect(diffAgainstCard(mutated, excerpt).join("\n")).toContain("B-Q5 default");
	});
});
