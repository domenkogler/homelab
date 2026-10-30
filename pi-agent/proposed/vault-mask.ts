/**
 * vault-mask.ts — the masker at the earliest seam where a vault value can be stopped (HD-1216).
 *
 * WHY THIS SEAM AND NO OTHER: every debt in `scripts/gate/secret_debt_register.txt` arrived the same
 * way — a command ran, its output came back as a tool result, and the harness wrote that result into
 * the session JSONL before anyone read it. The capture store lives outside the repo, so no `git` act
 * and no scrubber can un-write it, and rotation is the only close (docs/deployment-secrets.md §Creation
 * & Rotation Workflow). This extension stops the value BEFORE that write, which is the only place where
 * "before" is true: it prevents, it never closes, and it reduces the register by zero lines.
 *
 * THE HOOK, and the one detail that decides whether this file works at all: `tool_result` is a CHAINED
 * transformation — every handler receives what the earlier handlers returned — and its result carries
 * `content`, `structuredContent` and `details` as SEPARATE fields. Per the pi package's
 * `ToolResultEventResult`: "`content` without returning `structuredContent` drops the structured
 * content, because it may no longer match." So a redacting handler that returns only `content` would
 * (a) destroy a field it never touched and (b) leave the value standing in that structured half,
 * visible to the model and to the transcript. This file therefore owns all three halves or none.
 *
 * MATCH BY VALUE, NEVER BY KEY NAME, AND NEVER BY A RULE OWNED HERE. The shape that has walked past
 * every shape-based filter in this fleet is `KEY: "value"` in a rendered compose file, where the key is
 * `N8N_BASIC_AUTH_PASSWORD` or anything else a regex cannot predict. Which field of an item counts as a
 * credential, and the 8-character containment floor below which a secret cannot be told from prose, are
 * the leak eye's ruling — so this file asks `scripts/gate/check_secret_leak.py` for its own needle map
 * instead of restating any part of it. A second copy of that rule is the twin every gate in this repo
 * exists to catch, and a masker whose rule had drifted would be a masker quietly switched off.
 *
 * THE VALUES come from ONE batched read per process, through that same leg, so a busy lane pays the
 * cost once per child session against the vault's shared request bucket. The count is printed; values
 * are held in memory only and are never logged.
 *
 * THE BYPASS exists because a masker that rewrote the value a rotation is about to WRITE would break
 * the act. It is `HL_VAULT_MASK_BYPASS=1`, it prints one loud line the first time it fires, and it is an
 * environment variable — so it dies with the process and cannot survive into the next command.
 *
 * FAILURE: a seat that cannot read the vault masks NOTHING and says so once, in a notification, instead
 * of corrupting every tool result. That is deliberately not a silent degradation and deliberately not a
 * block: the instrument that judges whether a value leaked is `check_secret_leak.py`, and a hook that
 * reddens a session gets worked around the first time it misfires.
 *
 * ─── WHY THIS FILE SITS IN `pi-agent/proposed/` AND NOT IN `pi-agent/extensions/` ───
 * It is authored, not enabled. An extension that transforms tool output changes what EVERY session
 * sees, which is a fleet-wide harness change and not a lane's call. Two sides of it, both true:
 *   * WHAT IT PREVENTS: the next capture of a CURRENT value by a lane that was never asked to print one
 *     — the exact shape of every line in the debt register, and the reason the register is the size it
 *     is. Prevention at this seam is the only prevention that exists; everything else in this repo is
 *     detection after the fact.
 *   * WHAT IT COULD HIDE: a lane that reads its own masked output believes the value is gone. The
 *     marker is not a redaction of the vault, the debt stays open, and `check_secret_leak.py` still
 *     finds the copy the harness wrote before this hook existed — but a model that has to COMPARE a
 *     value (a rotation leg, a hash-to-config proof) would be working blind, and a tool result that
 *     lies about the fleet is worse than one that is merely noisy.
 * The owner act, when the hazard is accepted: `git mv pi-agent/proposed/vault-mask.ts
 * pi-agent/extensions/vault-mask.ts`, run `scripts/harness/sync-extensions.sh --push` on every seat,
 * then `--check --strict`. The `extensions` plane owns `pi-agent/extensions/**`, so the move is the
 * enable switch — and it is why this file lives one directory outside that glob until then.
 */

import { execFileSync, spawnSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** The marker that replaces a value: it names the item PREFIX so a human can go read it deliberately. */
const MARKER = (id8: string) => `[vault-mask:${id8}]`;
/** The vault this seat's IaC reads; the same default the reader itself uses. */
const VAULT = process.env.HL_VAULT || "Homelab-ansible";
const BYPASS_ENV = "HL_VAULT_MASK_BYPASS";

type Needle = { value: string; id8: string; title: string };
type Ready = { needles: Needle[]; short: string[]; items: number; requests: string };
type State = { kind: "unloaded" } | { kind: "ready"; ready: Ready } | { kind: "off"; why: string };

let state: State = { kind: "unloaded" };
/** One notification per item per process: a recurring value is not a recurring banner. */
const announced = new Set<string>();
let saidBypass = false;

function repoRoot(): string | null {
	// The deployed copy lives in a seat's HOME, so this file's own path says nothing about the repo.
	// `HL_REPO` is the seam the plane's own tests use; otherwise git answers for the checkout in cwd.
	try {
		return execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim() || null;
	} catch {
		return process.env.HL_REPO || null;
	}
}

/**
 * Ask the leak eye for ITS needle map: `[[value, [item ids…]], …]`, longest first. Everything the
 * masker is allowed to know about what counts as a secret comes from this one call — the field rule,
 * the containment floor and the partial-read boundary included.
 */
function load(): State {
	const root = repoRoot();
	if (!root) return { kind: "off", why: "no repository root on this seat (git refused, HL_REPO unset)" };
	// The ONE leg that decides what a secret is, asked for its own answer. `load_values()` applies the
	// field rule and the containment floor, raises on an unreadable vault, and prints its own request
	// count — which is exactly what this file must not re-decide, and could not keep in step if it did.
	const py = "import sys,json;sys.path.insert(0,sys.argv[1]);import check_secret_leak as l;"
		+ "n,t,short,_,_=l.load_values();"
		+ "print(json.dumps({'needles':[[k.decode('utf-8','surrogateescape'),v] for k,v in n.items()],"
		+ "'short':short,'items':len(t),"
		+ "'titles':{k[:8]:v for k,v in t.items()}}))";
	const res = spawnSync("python3", ["-c", py, `${root}/scripts/gate`], {
		encoding: "utf8",
		maxBuffer: 64 * 1024 * 1024,
	});
	if (res.error) return { kind: "off", why: `python3 could not run: ${res.error.message}` };
	if (res.status !== 0) {
		return {
			kind: "off",
			why: `the leak eye's read exited ${res.status}: ${(res.stderr || "").trim().slice(0, 160)}`,
		};
	}
	let body: { needles: [string, string[]][]; short: string[]; items: number; titles: Record<string, string> };
	try {
		// The reader prints its own quota line on the same stream, so the payload is the LAST line.
		body = JSON.parse(res.stdout.trimEnd().split("\n").pop() ?? "");
	} catch {
		return { kind: "off", why: "the needle map came back as something that is not JSON" };
	}
	// Longest first, so a value that contains another is replaced before the shorter one could split it.
	const needles: Needle[] = body.needles
		.map(([value, ids]) => ({ value, id8: ids[0].slice(0, 8), title: body.titles[ids[0].slice(0, 8)] ?? "?" }))
		.sort((a, b) => b.value.length - a.value.length);
	const m = /requests=(\d+)/.exec(res.stderr || "");
	return { kind: "ready", ready: { needles, short: body.short, items: body.items, requests: m ? m[1] : "?" } };
}

function maskText(text: string, needles: Needle[], hits: Map<string, number>): { text: string; changed: boolean } {
	let out = text;
	let changed = false;
	for (const n of needles) {
		if (!out.includes(n.value)) continue;
		out = out.split(n.value).join(MARKER(n.id8));
		hits.set(n.id8, (hits.get(n.id8) ?? 0) + 1);
		changed = true;
	}
	return { text: out, changed };
}

/** JSON-aware: replace inside string LEAVES, so a value that JSON-escapes cannot be missed. */
function maskJson(node: unknown, needles: Needle[], hits: Map<string, number>): unknown {
	if (typeof node === "string") return maskText(node, needles, hits).text;
	if (Array.isArray(node)) return node.map((item) => maskJson(item, needles, hits));
	if (node && typeof node === "object") {
		const out: Record<string, unknown> = {};
		for (const [k, v] of Object.entries(node as Record<string, unknown>)) out[k] = maskJson(v, needles, hits);
		return out;
	}
	return node;
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_result", async (event, ctx) => {
		if (process.env[BYPASS_ENV]) {
			if (!saidBypass) {
				saidBypass = true;
				ctx.ui.notify(`vault-mask: BYPASS ACTIVE (${BYPASS_ENV}) — values are NOT being masked in this process`, "warning");
			}
			return undefined;
		}
		if (state.kind === "unloaded") {
			state = load();
			if (state.kind === "ready") {
				ctx.ui.setStatus(
					"vault-mask",
					`vault-mask: ${state.ready.needles.length} value(s) from ${state.ready.items} items (requests=${state.ready.requests})`,
				);
				if (state.ready.short.length) {
					ctx.ui.notify(
						`vault-mask: ${state.ready.short.length} secret field value(s) sit under the leak eye's ` +
							"containment floor and are NOT masked — scripts/gate/check_secrets.py is the instrument there",
						"warning",
					);
				}
			} else if (state.kind === "off") {
				ctx.ui.notify(`vault-mask: masking is OFF — ${state.why}`, "warning");
			}
		}
		if (state.kind !== "ready") return undefined;
		const needles = state.ready.needles;
		const hits = new Map<string, number>();

		const content = event.content.map((block) => {
			if (block.type !== "text") return block;
			const r = maskText(block.text, needles, hits);
			return r.changed ? { ...block, text: r.text } : block;
		});
		// structuredContent and details are returned WHOLE and masked whenever anything is returned:
		// dropping a field this extension does not own would destroy it, and returning it unmasked would
		// leave the value standing in the half the model reads structurally.
		const hasStructured = event.structuredContent !== undefined;
		const structured = hasStructured ? maskJson(event.structuredContent, needles, hits) : undefined;
		const hasDetails = !!event.details && typeof event.details === "object";
		const details = hasDetails ? maskJson(event.details, needles, hits) : undefined;

		if (hits.size === 0) return undefined; // identity: return nothing, change nothing, chain intact
		for (const id8 of hits.keys()) {
			if (announced.has(id8)) continue;
			announced.add(id8);
			ctx.ui.notify(
				`vault-mask: replaced a value of ${state.ready.needles.find((n) => n.id8 === id8)?.title ?? "?"} ` +
					`(${id8}) in a tool result — a mask, not a close`,
				"warning",
			);
		}
		return {
			content,
			...(hasStructured ? { structuredContent: structured } : {}),
			...(hasDetails ? { details } : {}),
			isError: event.isError,
		};
	});
}
