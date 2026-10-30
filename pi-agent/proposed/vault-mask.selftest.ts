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
 *       file is erasable-syntax-only TypeScript, so node's own type-stripping runs the same nine arms on
 *       every seat. This repo invokes no other JS runtime.
 * Exit 0 = every arm green; 1 = at least one arm red. A scenario that could not be reached prints a
 * FAIL line, never a silent skip.
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const SECRET = "LONGSECRETvalue0123456789ab"; // a field the eye calls secret, at or above its floor
const OPAQUE = "OPAQUEvalue0123456789abcdef"; // a NON-secret field: masking it would be a bug
const SHORT = "12345"; // a SECRET field under the eye's containment floor: reported, never matched
const ID = "aaaa11112222333344445555";

const here = fileURLToPath(new URL(".", import.meta.url));
const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd: here, encoding: "utf8" }).trim();

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

	console.log(`vault-mask.selftest: ${fails} failing arm(s)`);
	process.exit(fails ? 1 : 0);
}

main();
