/**
 * host-status.ts — name the machine in the footer.
 *
 * WHY. The same pi runs on three seats: this cockpit (hostname `oldsrv`), WSL
 * Debian on the laptop, and the Win11 host. Reaching the cockpit happens over
 * SSH, where the shell prompt is gone for the whole session and pi's footer
 * names folder / model / context / cost — nothing that answers "which box am I
 * typing to?". That question has been answered wrongly on this repo's seats at
 * least twice (pi-harness.md §5: the two laptop halves divided on
 * defaultThinkingLevel without any carrier noticing), so the seat identity is
 * operator-facing information, not decoration.
 *
 * WHY setStatus AND NOT setFooter. `ctx.ui.setStatus()` ADDS one entry to pi's
 * own footer, so folder/model/context/cost stay pi's problem forever.
 * `ctx.ui.setFooter()` replaces the line — see pi's
 * examples/extensions/custom-footer.ts, which recomputes input/output/cost from
 * ctx.sessionManager.getBranch() just to place a branch name. A footer rewrite
 * is a standing maintenance debt against pi's own footer; this file is 3 lines
 * of intent.
 *
 * Deployed by scripts/sync-extensions.sh --push (repo pi-agent/extensions/ is
 * the SSOT; ~/.pi/agent/extensions/ is the deploy target).
 */

import { hostname } from "node:os";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Namespaced-ish key: setStatus entries share one footer area across extensions,
// so a bare "host" could be silently overwritten by another extension's status.
const STATUS_KEY = "host";

export default function (pi: ExtensionAPI) {
	// Resolved once at load. hostname() does not change during a session, and
	// reading it per render would pay a syscall in the render path.
	const label = hostname() || "unknown-host";

	// session_start fires on startup AND after /new AND on a session switch —
	// exactly the moments pi rebuilds the footer. Setting it anywhere else either
	// runs once before the UI exists or leaves the entry behind after a switch.
	pi.on("session_start", async (_event, ctx) => {
		ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("dim", `@ ${label}`));
	});
}
