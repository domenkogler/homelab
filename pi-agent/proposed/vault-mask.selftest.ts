/**
 * vault-mask.selftest.ts — the arms `pi-agent/extensions/vault-mask.ts` passes on every seat (HD-1216).
 * This file sits OUTSIDE the `extensions` plane's glob on purpose: the plane deploys
 * `pi-agent/extensions/**` to `~/.pi/agent/extensions`, and a self-test loaded as an extension would run
 * its fixtures inside every session and `process.exit` the harness.
 *
 * ZERO vault requests: the masker asks the leak eye for its needle map, and the eye honours
 * `$HL_VAULT_READ_FIXTURE`, so a minted fixture stands in for the fleet. Nothing here needs `op`, a
 * credential, or a network.
 *
 * RUN:  node --experimental-strip-types pi-agent/proposed/vault-mask.selftest.ts
 *       node is the runtime pi itself runs on — every seat's `pi` launcher execs a node binary — and this
 *       file is erasable-syntax-only TypeScript, so node's own type-stripping runs the same ten arms on
 *       every seat. This repo invokes no other JS runtime.
 * One arm asks a seat question rather than a unit question: it puts a `python3` that answers non-zero
 * ahead of PATH and checks that the needle map still arrives (or, where the seat's own resolver answers
 * exactly that name, that the OFF line names the launcher and the rc). The arms therefore fail on a seat
 * that cannot resolve its interpreter, which is the state a green run on another seat cannot rule out.
 * Exit 0 = every arm green; 1 = at least one arm red. A scenario that could not be reached prints a
 * FAIL line, never a silent skip.
 *
 * THE ACCEPTANCE PAIR, as one command on the seat that is being accepted:
 *       node --experimental-strip-types pi-agent/proposed/vault-mask.selftest.ts acceptance-pair
 *   prints one JSON record — the same fixture value masked, then the same value under
 *   `HL_VAULT_MASK_BYPASS=1` — with the node that answered and the load line's request count, and exits 0
 *   only when the pair is GREEN on this seat. It exists because the arms answer a UNIT question: a seat
 *   whose launcher is not the one the needle map needs can still print ten green arms while every tool
 *   result reaches the capture whole. Only the pair, read under the node that seat's `pi` actually execs,
 *   says masking is live THERE.
 *   A seat whose git cannot name the checkout (the engine's Linux git on a Windows linked worktree) is
 *   given the root the same way the extension is: `HL_REPO=<engine-side path>`, the seam that already
 *   exists for exactly that case — a crossed git answer proves nothing about the checkout either way.
 */

import { execFileSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter } from "node:path";
import { fileURLToPath } from "node:url";

const SECRET = "LONGSECRETvalue0123456789ab"; // a field the eye calls secret, at or above its floor
const OPAQUE = "OPAQUEvalue0123456789abcdef"; // a NON-secret field: masking it would be a bug
const SHORT = "12345"; // a SECRET field under the eye's containment floor: reported, never matched
const ID = "aaaa11112222333344445555";

const here = fileURLToPath(new URL(".", import.meta.url));
// The checkout the arms run against, by the extension's own rule: git answers where git can, and
// `HL_REPO` answers where it cannot. The cannot is not hypothetical — a Linux git on a Windows linked
// worktree exits 128 (`D:/…` in the worktree's `.git` file, joined as a relative path), which is the
// engine-side view of this same checkout. Naming the root is the leg; asking that git and reporting
// its failure as the seat's would be the crossed-git false negative this repo keeps meeting.
let repoRoot = "";
try {
	repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd: here, encoding: "utf8" }).trim();
} catch {
	repoRoot = process.env.HL_REPO ?? "";
}

const dir = mkdtempSync(`${tmpdir()}/vault-mask-fixture-`);
const fixture = `${dir}/vault.json`;
process.env.HL_VAULT_READ_FIXTURE = fixture; // zero vault requests, and the child python inherits it
writeFileSync(
	fixture,
	JSON.stringify({
		items: {
			[ID]: {
				title: "fixture_api",
				version: 1,
				fields: [
					{ id: "credential", label: "credential", value: SECRET },
					{ id: "opaque", label: "opaque", value: OPAQUE },
					{ id: "password", label: "password", value: SHORT },
				],
			},
		},
	}),
	"utf-8",
);

type Check = (label: string, ok: boolean, detail?: string) => void;
let fails = 0;
const check: Check = (label, ok, detail) => {
	if (!ok) fails++;
	console.log(`  arm ${label}: ${ok ? "ok" : "FAIL"}${ok || !detail ? "" : ` — ${detail}`}`);
};

/** The pi surface the extension touches: one hook registration, and a UI that remembers what it heard. */
function harness() {
	let handler: ((event: any, ctx: any) => Promise<any>) | null = null;
	const notifications: string[] = [];
	const statuses: (string | undefined)[] = [];
	const pi = { on: (_event: string, h: (event: any, ctx: any) => Promise<any>) => (handler = h) };
	const ctx = { cwd: repoRoot, ui: { notify: (m: string) => notifications.push(m), setStatus: (_k: string, v: string | undefined) => statuses.push(v) } };
	return {
		pi,
		ctx,
		notifications,
		statuses,
		register: () => handler as (event: any, ctx: any) => Promise<any>,
	};
}

function event(text: string, extra: Record<string, unknown> = {}) {
	return {
		type: "tool_result",
		toolCallId: "call-1",
		toolName: "bash",
		input: {},
		isError: false,
		content: [{ type: "text", text }],
		...extra,
	};
}

async function main() {
	const scenario = process.argv[2] ?? "";
	const { pi, ctx, notifications, statuses, register } = harness();
	const { default: vaultMask } = await import("../extensions/vault-mask.ts");
	vaultMask(pi as never);
	const handle = register();

	if (scenario === "off") {
		// An unreachable vault: the honest answer is "masking is OFF, here is why", never silence.
		// Set INSIDE the child: a fixture that cannot be read is the boundary, and it costs zero
		// requests. (The env has to be moved before the first tool result, because the needle map is
		// loaded once per process — which is the point of the once-per-session design.)
		process.env.HL_VAULT_READ_FIXTURE = `${dir}/does-not-exist.json`;
		await handle(event(`text mentioning ${SECRET}`), ctx);
		console.log(JSON.stringify(notifications));
		return;
	}

	if (scenario === "acceptance-pair") {
		// The PAIR the row's seat legs are read with, on the seat that is being accepted: one fixture value,
		// run twice through the live handler — masked, then under the rotation bypass. Both halves ride the
		// fixture minted above, so the record costs zero vault requests and the load line's `requests=0` is
		// that proof. What prints is shape, never content: the marker, the node that answered, and the OFF
		// reasons — a probe that quotes a value is the fourth leak.
		//
		// GRADED, not just printed, and graded on what the HARNESS WOULD WRITE: a handler that returns
		// nothing leaves the original result standing, so "returned undefined" is a value that survived,
		// never a value that vanished. A record that read `valueGone: true` on a seat whose masking is OFF
		// would be the exact lie this file exists to prevent.
		const text = `token=${SECRET}`;
		const written = (r: any) => JSON.stringify(r ?? event(text));
		const masked = await handle(event(text), ctx);
		const maskedWritten = written(masked);
		process.env.HL_VAULT_MASK_BYPASS = "1";
		const bypassed = await handle(event(text), ctx);
		delete process.env.HL_VAULT_MASK_BYPASS;
		const bypassWritten = written(bypassed);
		const off = notifications.filter((n) => n.includes("masking is OFF"));
		const load = statuses.filter((s) => s?.includes("requests="));
		const half = {
			masked: { changed: masked !== undefined, valueGone: !maskedWritten.includes(SECRET), marker: maskedWritten.includes(`[vault-mask:${ID.slice(0, 8)}]`) },
			bypass: { changed: bypassed !== undefined, valueStanding: bypassWritten.includes(SECRET), saidBypass: notifications.some((n) => n.includes("BYPASS ACTIVE")) },
		};
		const why: string[] = [];
		if (off.length) why.push("masking is OFF on this seat");
		if (!half.masked.valueGone) why.push("the fixture value survived a masked run");
		if (!half.masked.marker) why.push("no marker in the masked result");
		if (!half.bypass.valueStanding) why.push("the bypass rewrote the value it must leave alone");
		if (!half.bypass.saidBypass) why.push("the bypass said nothing");
		// The load line only exists when the needle map arrived, so the request-count half is asked only
		// of a run that got that far — otherwise an OFF would be reported twice, once with a wrong reason.
		if (!off.length && !load.some((s) => s?.includes("requests=0"))) why.push("the load line does not report requests=0 — this pair read something that is not the fixture");
		process.exitCode = why.length ? 1 : 0;
		console.log(
			JSON.stringify({
				node: process.execPath,
				load,
				off,
				verdict: why.length ? `PAIR NOT GREEN — ${why.join("; ")}` : "PAIR OK — masked here, and the bypass leaves the value standing",
				...half,
			}),
		);
		return;
	}

	if (scenario === "stubbed-interpreter") {
		// The child half of arm (10). PATH here carries a `python3` that answers non-zero ahead of every
		// real program, and the fixture is still the fixture, so the leg costs zero requests. What prints
		// is what the masker DID and the OFF reasons it gave — never the value it was shown.
		const text = `token=${SECRET}`;
		const r = await handle(event(text), ctx);
		console.log(
			JSON.stringify({
				masked: r !== undefined && !String(r?.content?.[0]?.text ?? "").includes(SECRET),
				// The marker, not merely a changed result: a handler that returned something else would
				// still be a masker that never saw the needle map.
				marker: String(r?.content?.[0]?.text ?? "").includes(`[vault-mask:${ID.slice(0, 8)}]`),
				off: notifications.filter((n) => n.includes("masking is OFF")),
			}),
		);
		return;
	}

	// (1) the value in a tool result becomes a marker naming the item prefix, and no value survives.
	let r = await handle(event(`token=${SECRET} (again ${SECRET})`), ctx);
	check(
		"a vault value in a tool result is replaced by a marker naming the item prefix",
		r !== undefined && !JSON.stringify(r).includes(SECRET) && r.content[0].text.includes(`[vault-mask:${ID.slice(0, 8)}]`),
		JSON.stringify(r?.content?.[0]?.text ?? r),
	);

	// (2) the chained-handler contract: the structured half is neither dropped nor left un-red.
	r = await handle(event(`x ${SECRET}`, { structuredContent: { nested: { key: SECRET }, keep: 7 } }), ctx);
	check(
		"structuredContent survives a redaction and is masked too",
		r?.structuredContent?.nested?.key === `[vault-mask:${ID.slice(0, 8)}]` && r?.structuredContent?.keep === 7,
		JSON.stringify(r?.structuredContent),
	);

	// (3) `details` is the third half of the same result and carries tool output too.
	r = await handle(event("no value here", { details: { stdout: `ran with ${SECRET}` } }), ctx);
	check("details is masked rather than carried through un-red", r?.details?.stdout?.includes("[vault-mask:") === true, JSON.stringify(r?.details));

	// (4) nothing to mask = return NOTHING, so the chain and every other handler's result stand intact.
	r = await handle(event("an ordinary line of ordinary output"), ctx);
	check("a result with no value in it is returned untouched, so later handlers keep theirs", r === undefined, JSON.stringify(r));

	// (5) the rule is the leak eye's, not "every long string": a NON-secret field is left standing.
	r = await handle(event(`opaque field ${OPAQUE} stays`), ctx);
	check("a field the leak eye does not call secret is NOT masked — the rule is not owned here", r === undefined, JSON.stringify(r?.content));

	// (6) under the containment floor a value cannot be told from prose: reported, never pretended.
	r = await handle(event(`a code like ${SHORT} in prose`), ctx);
	check(
		"a value under the containment floor is left standing and REPORTED, not silently passed",
		r === undefined && notifications.some((n) => n.includes("containment floor") && n.includes("NOT masked")),
		notifications.join(" | "),
	);

	// (7) the cost of the prevention is printed once, at load.
	check(
		"the load line prints the request count and the value count",
		statuses.some((s) => s?.includes("requests=") && s.includes("value(s)")),
		JSON.stringify(statuses),
	);

	// (8) the rotation bypass: loud, and dead with the process.
	process.env.HL_VAULT_MASK_BYPASS = "1";
	notifications.length = 0;
	r = await handle(event(`write ${SECRET} now`), ctx);
	check(
		"HL_VAULT_MASK_BYPASS leaves the value standing and says so out loud",
		r === undefined && notifications.some((n) => n.includes("BYPASS ACTIVE")),
		notifications.join(" | "),
	);
	delete process.env.HL_VAULT_MASK_BYPASS;

	// (9) an unreachable vault is a boundary: OFF with a reason, not a green and not a broken session.
	let off = "";
	try {
		off = execFileSync(process.execPath, [fileURLToPath(import.meta.url), "off"], { encoding: "utf8" });
	} catch (e) {
		off = String(e);
	}
	check("an unreadable vault switches masking OFF and prints why", off.includes("masking is OFF"), off.slice(0, 160));

	// (10) WHICH interpreter reads the needle map is the SEAT's answer, not a name on PATH. The canary
	// plants a `python3` that answers non-zero in a bin dir ahead of PATH — WRAPPER form, the shape
	// install-hooks.sh --self-test uses, because `ln` of a Windows binary leaves a copy that exits 127 —
	// which is what the Microsoft-Store alias stub is on a Windows seat: `command -v` finds it, it is not
	// an interpreter, and under node (the runtime `pi` itself runs on) it answers 9009 without running a
	// line of Python. Two seats, two honest outcomes, one assertion: a seat whose resolver answers a
	// DIFFERENT launcher must still get its needles and must still write the marker, and a seat whose
	// resolver answers THIS name has nothing to route around, so it must say which launcher it tried and
	// what rc it got. An OFF line that names no launcher is the defect this arm was written for — masking
	// switched off on one seat, silently, while the same commit was green on the others.
	const stubBin = `${dir}/stub-bin`;
	mkdirSync(stubBin, { recursive: true });
	writeFileSync(`${stubBin}/python3`, "#!/bin/sh\necho 'python3: the stub answers non-zero' >&2\nexit 49\n", "utf-8");
	chmodSync(`${stubBin}/python3`, 0o755);
	let stubRaw = "";
	try {
		stubRaw = execFileSync(process.execPath, [fileURLToPath(import.meta.url), "stubbed-interpreter"], {
			encoding: "utf8",
			env: { ...process.env, PATH: `${stubBin}${delimiter}${process.env.PATH}` },
		});
	} catch (e) {
		stubRaw = String((e as { stdout?: string }).stdout ?? e);
	}
	let stub: { masked?: boolean; marker?: boolean; off?: string[] } = {};
	try {
		stub = JSON.parse(stubRaw.trimEnd().split("\n").pop() ?? "");
	} catch {
		// not the record the scenario prints: `masked` stays false and the detail below quotes the answer
	}
	const offLine = (stub.off ?? []).join(" | ");
	check(
		"a python3 that answers non-zero does not switch masking off on a seat whose launcher is another program, and an OFF that cannot route around it names its launcher and rc",
		(stub.masked === true && stub.marker === true) || (/launcher=\S/.test(offLine) && /(rc=|could not run)/.test(offLine)),
		stub.masked && stub.marker
			? "the needle map arrived through the resolver and the marker is in the result"
			: offLine.slice(0, 220) || "neither the marker nor an OFF line naming a launcher",
	);

	console.log(`vault-mask.selftest: ${fails} failing arm(s)`);
	process.exit(fails ? 1 : 0);
}

main();
