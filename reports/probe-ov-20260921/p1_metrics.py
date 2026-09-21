#!/usr/bin/env python3
"""P1 fidelity metrics — the SAME code runs on the git-blob copy and on the OV copy.

Usage: p1_metrics.py ROOT_DIR OUT.json

Emits per-file metrics used by p1_diff.py for the eight checks of prompt-OV.md §7.3.
No network, no OV knowledge: it measures a plain directory tree, so the baseline is
independent of the thing under test.
"""
import hashlib
import json
import os
import re
import sys

FENCE_RE = re.compile(r"^(\s*)(`{3,}|~{3,})")
ATX_RE = re.compile(r"^(#{1,6})[ \t]+(.*)$")
YAML_FM_RE = re.compile(r"\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*\r?\n", re.S)
TOP_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_.-]*):", re.M)
BLOCK_SCALAR_RE = re.compile(r"^\s*[A-Za-z_][\w.-]*:[ \t]*[|>&][-+0-9]*[ \t]*(#.*)?$", re.M)
DIACRITICS = "čćšžČĆŠŽđĐ"


def read_text(path):
    with open(path, "rb") as f:
        raw = f.read()
    try:
        text = raw.decode("utf-8")
        enc_ok = True
    except UnicodeDecodeError:
        text = raw.decode("utf-8", errors="replace")
        enc_ok = False
    return raw, text, enc_ok


def split_lines_keepends(text):
    return text.splitlines(keepends=True)


def in_fence_state(lines):
    """Yield (line, inside_fence) using the standard toggle on fence markers."""
    open_marker = None
    open_indent = 0
    for ln in lines:
        m = FENCE_RE.match(ln)
        if m:
            marker = m.group(2)
            indent = len(m.group(1))
            if open_marker is None:
                open_marker = (marker, indent, len(marker))
                yield ln, True
                continue
            if marker[0] == open_marker[0] and len(marker) >= open_marker[2] and indent <= open_marker[1]:
                open_marker = None
                yield ln, True
                continue
        yield ln, open_marker is not None


def norm_ws(text):
    """Whitespace-only normalisation: strip trailing ws, collapse runs of blanks."""
    out = []
    blank = False
    for ln in text.splitlines():
        ln = re.sub(r"[ \t]+$", "", ln)
        ln = re.sub(r"[ \t]+", " ", ln)
        if ln == "":
            if not blank:
                out.append(ln)
            blank = True
        else:
            out.append(ln)
            blank = False
    return "\n".join(out).strip()


def metrics_for(path):
    raw, text, enc_ok = read_text(path)
    lines = split_lines_keepends(text)

    headers = []
    pipe_rows = []
    fence_markers = 0
    fence_langs = []
    for ln, inside in in_fence_state(lines):
        m = FENCE_RE.match(ln)
        if m:
            fence_markers += 1
            lang = ln.strip().strip("`~").strip()
            if lang:
                fence_langs.append(lang.split()[0] if lang.split() else lang)
            continue
        if inside:
            continue
        h = ATX_RE.match(ln.rstrip("\r\n"))
        if h:
            headers.append([len(h.group(1)), h.group(2).strip()])
        if "|" in ln:
            stripped = ln.rstrip("\r\n")
            unescaped = len(re.findall(r"(?<!\\)\|", stripped))
            if unescaped:
                pipe_rows.append(unescaped)

    fm = YAML_FM_RE.match(text)
    fm_keys = sorted(set(TOP_KEY_RE.findall(fm.group(1)))) if fm else []

    # fence survival also for j2/yaml block scalars anywhere in the file
    block_scalars = len(BLOCK_SCALAR_RE.findall(text))

    return {
        "bytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "sha256_ws": hashlib.sha256(norm_ws(text).encode("utf-8")).hexdigest(),
        "lines": len(lines),
        "utf8_clean": enc_ok,
        "front_matter": bool(fm),
        "front_matter_keys": fm_keys,
        "headers": headers,
        "header_count": len(headers),
        "pipe_counts": pipe_rows,
        "pipe_total": sum(pipe_rows),
        "fence_markers": fence_markers,
        "fence_langs": sorted(set(fence_langs)),
        "yaml_block_scalars": block_scalars,
        "diacritics": {c: text.count(c) for c in DIACRITICS if text.count(c)},
        "diacritics_total": sum(text.count(c) for c in DIACRITICS),
    }


def main():
    root, out = sys.argv[1], sys.argv[2]
    data = {}
    for dirpath, _dirs, files in os.walk(root):
        for fn in sorted(files):
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root)
            try:
                data[rel] = metrics_for(full)
            except Exception as e:  # noqa: BLE001
                data[rel] = {"error": f"{type(e).__name__}: {e}"}
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1, sort_keys=True)
    print(f"files={len(data)} out={out}")


if __name__ == "__main__":
    main()
