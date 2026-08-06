#!/usr/bin/env python3
"""Generic plan-integrity validator for plans produced by plan-task.

New (default) layout: a plan is a DIRECTORY
    plan/<date>-<slug>/index.md     # goal, models, summary, CURRENT_TASK, acceptance, invariants
    plan/<date>-<slug>/T<ID>.md     # one task file per task: objective, scope, values, difficulty, model, validation

Backwards-compatible: still accepts a single old-style combined .md file.

Checks that a plan is structurally complete and mechanically parseable:
required index sections, valid statuses, synced CURRENT_TASK, per-task required
fields, valid difficulty (1-5), non-empty Model and Validation, and a Models
table that covers every task.

Does NOT execute task validation commands (those are authoritative per-task and
are run by run-task). This checks the plan's own integrity.

Usage:
    python scripts/validate-plan.py --plan ./plan/2026-08-06-reorg
    python scripts/validate-plan.py --plan ./plan/2026-08-06-reorg --task T4   # scope to one task
Exit 0 if all checks pass; exit 1 otherwise, printing one line per failure.
"""
import argparse
import os
import re
import sys

VALID_STATUS = {"todo", "in-progress", "awaiting-verification", "done", "blocked"}
REQ_TASK_HEADERS = ["Objective", "File scope", "Difficulty", "Model", "Validation"]
# Global sections required in index.md (directory layout). ("## Tasks" no longer
# exists in the index — tasks live in T*.md files.)
INDEX_SECTIONS = ["## Goal", "## Models", "## Task summary", "## CURRENT_TASK",
                  "## Global acceptance", "## Global invariants"]


def parse_tasks(text, heading_re=None):
    """Split on task headings. Returns list of (tid, title, block)."""
    # \u2014 is the em-dash '—' that separates '<id> — title'.
    re_ = heading_re or r"^#{1,3}\s+(T\d+)\s*\u2014\s*(.+)$"
    tasks = []
    for m in re.finditer(re_, text, re.M):
        start = m.start()
        nxt = text.find("\n###", start + 1)
        block = text[start:] if nxt == -1 else text[start:nxt]
        tasks.append((m.group(1), m.group(2).strip(), block))
    return tasks


def check_plan(path, only_task=None):
    errors = []

    index_path = path if os.path.isfile(path) else os.path.join(path, "index.md")
    if not os.path.isfile(index_path):
        print(f"FAIL no index.md (or plan file) at: {path}")
        return 1

    tasks = []
    is_dir = os.path.isdir(path)
    if is_dir:
        # Directory layout: read index for global sections, then each T*.md.
        idx_text = open(index_path, encoding="utf-8").read()
        # 0) required global sections
        for sec in INDEX_SECTIONS:
            if sec not in idx_text:
                errors.append(f"missing index section: {sec}")
        # parse statuses from index summary + CURRENT_TASK sync handled below
        summary_text = idx_text
        # gather task files
        for fn in sorted(os.listdir(path)):
            if re.fullmatch(r"T\d+\.md", fn):
                tpath = os.path.join(path, fn)
                ttext = open(tpath, encoding="utf-8").read()
                parsed = parse_tasks(ttext)
                if not parsed:
                    errors.append(f"{fn}: no task heading '# T<id> —' found")
                    continue
                if len(parsed) > 1:
                    errors.append(f"{fn}: contains more than one task (one task per file)")
                tid, title, block = parsed[0]
                tasks.append((tid, title, block))
    else:
        # Legacy single-file layout
        idx_text = open(index_path, encoding="utf-8").read()
        summary_text = idx_text
        for sec in ["## Tasks"] + INDEX_SECTIONS:
            if sec not in idx_text:
                errors.append(f"missing section: {sec}")
        tasks = parse_tasks(idx_text)

    # 1) status values in the summary table (Status is the 3rd field after ID)
    for m in re.finditer(r"^\|\s*T\d+\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|\s*(\w[\w-]*)\s*\|",
                         summary_text, re.M):
        st = m.group(3).strip()
        if st not in VALID_STATUS:
            errors.append(f"invalid status '{st}' at task {m.group(1)}")

    # 2) CURRENT_TASK sync
    ct = re.search(r"^## CURRENT_TASK:\s*(\w+)", summary_text, re.M)
    if ct:
        cid = ct.group(1)
        found = any(tid == cid for tid, _, _ in tasks)
        if cid != "none" and not found:
            errors.append(f"CURRENT_TASK {cid} not found among task files/headings")

    # 3) per-task fields
    if not tasks:
        errors.append("no task blocks found")
    for tid, title, block in tasks:
        if only_task and tid != only_task:
            continue
        for h in REQ_TASK_HEADERS:
            if not re.search(rf"^\*\*{re.escape(h)}", block, re.M):
                errors.append(f"{tid}: missing '{h}' header")
        dm = re.search(r"^\*\*Difficulty:\*\*[ \t]*(\d)", block, re.M)
        if dm:
            d = int(dm.group(1))
            if not (1 <= d <= 5):
                errors.append(f"{tid}: difficulty {d} out of 1-5")
        else:
            errors.append(f"{tid}: missing Difficulty")
        if not re.search(r"^\*\*Model:\*\*[ \t]*\S", block, re.M):
            errors.append(f"{tid}: missing Model")
        if not re.search(r"^\*\*Validation:\*\*", block, re.M):
            errors.append(f"{tid}: missing Validation block")

    # 4) Models table coverage (index Models section)
    mstart = summary_text.find("## Models")
    msec = summary_text[mstart:summary_text.find("## Task summary", mstart)] if mstart >= 0 else ""
    model_tids = set(re.findall(r"^\|\s*(T\d+)\s*\|", msec, re.M))
    task_tids = {tid for tid, _, _ in tasks}
    missing_models = sorted(t for t in task_tids if t not in model_tids)
    if missing_models:
        errors.append(f"Models table missing rows for: {', '.join(missing_models)}")
    extra_models = sorted(t for t in model_tids if t not in task_tids)
    if extra_models:
        errors.append(f"Models table has rows for unknown tasks: {', '.join(extra_models)}")

    if errors:
        for e in errors:
            print("FAIL:", e)
        return 1
    n = len(tasks)
    scope = f" (task {only_task})" if only_task else f" ({n} tasks)"
    print(f"PASS: plan '{path}' valid{scope}")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--task", default=None, help="validate only this task's block")
    args = ap.parse_args()
    sys.exit(check_plan(args.plan, args.task))


if __name__ == "__main__":
    main()
