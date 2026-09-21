#!/usr/bin/env python3
"""M1 corpus builder for the agentmemory probe (prompt-agentmemory.md §5 M1).

Two parts, both required for a comparable measurement:

  A. REPLAY  -- the 21 corpus files (the OV lane's grep-baseline file set, which is a
     superset of OV's 19-file P1 corpus) are replayed as prompt_submit observations,
     one observation per ~700-char paragraph, tagged with project=<repo-relative path>
     so hit@5 is scored exactly like the OV lane (p2_run.py: expected_file in returned
     sources). This is what makes hit@5 comparable with p2_ov.json / p2_grep.json.

  B. SYNTHETIC -- 20 sessions in this repo's real shapes carrying the exact identifiers
     the brief names: ports (9002, 3111, 6333), numbers (515,786 / 0.34 / 512/64), row
     ids (HD-268, HD-387, #26, #28), Slovene strings, and one contradiction pair
     (port 3113 -> corrected to 3114) plus a paraphrase-only session (no exact token)
     for M2's paraphrase gate.

Everything is factual against the tree at the probe commit; nothing is invented.
Usage: m1_corpus.py OUT_JSON
"""
import json
import os
import re
import sys

CORPUS = "/home/domen/amprobe/corpus"
CWD = CORPUS
TS0 = "2026-09-2"

# ---------------------------------------------------------------- A. replay
CHUNK = 700


def paragraphs(text):
    out = []
    for block in re.split(r"\n\s*\n", text):
        b = block.strip()
        if len(b) < 40:
            continue
        while len(b) > CHUNK:
            out.append(b[:CHUNK])
            b = b[CHUNK:]
        if len(b.strip()) >= 40:
            out.append(b.strip())
    return out


def replay_observations():
    obs = []
    files = []
    for root, _, names in os.walk(CORPUS):
        for n in sorted(names):
            files.append(os.path.join(root, n))
    for path in sorted(files):
        rel = os.path.relpath(path, CORPUS)
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        # strip front matter: it is metadata, not content
        text = re.sub(r"\A---.*?\n---\n", "", text, flags=re.S)
        for j, p in enumerate(paragraphs(text)):
            obs.append({
                "hookType": "prompt_submit",
                "sessionId": "replay-" + rel.replace("/", "_").replace(".", "_"),
                "project": rel,
                "cwd": CWD,
                "timestamp": "2026-09-21T%02d:%02d:%02dZ" % (10 + j // 60, j % 60, (j * 7) % 60),
                "data": {"prompt": p},
            })
    return obs


# ------------------------------------------------------------- B. synthetic
PROMPT = "prompt"
TOOL = "tool"

SESSIONS = [
    # (session id, project, [(kind, text), ...])
    ("s01-embedding-leg", "homelab/docs", [
        (PROMPT, "Kateri TCP port posluša noge za vgradne vektorske predstavitve (embedding leg)?"),
        (TOOL, "grep -n 9002 docs/services-ai.md -> the pinned embedding leg listens on TCP 9002 on oldsrv (bge-m3-vk behind llama.cpp on the RX 7600)"),
        (PROMPT, "Potrdi: port 9002, modelov vrstic v LiteLLM je bge-m3-vk."),
    ]),
    ("s02-rerank-latency", "homelab/docs", [
        (TOOL, "bench rerank --docs 20 --device RX7600 -> 0.34 s wall-clock for twenty documents on the RX 7600"),
        (PROMPT, "Torej rerank 20 dokumentov traja 0.34 s na RX 7600; zabeleži številko."),
    ]),
    ("s03-kv-pool", "homelab/docs", [
        (TOOL, "cat docs/hardware-spark.md | grep KV -> KV cache pool = 515,786 tokens; a single 262,144-token context leaves 1.97 concurrent full contexts"),
        (PROMPT, "Zapiši: 515,786 tokenov KV bazena, 1.97 polnih kontekstov hkrati."),
    ]),
    ("s04-vlan-mgmt", "homelab/docs", [
        (PROMPT, "Kateri VLAN je Management?"),
        (TOOL, "grep Management docs/network-vlans.md -> | 99 | Management | Router, switch, AP management |"),
    ]),
    ("s05-chunking", "homelab/docs", [
        (PROMPT, "Kakšna velikost kosov (chunk size) in prekrivanje (overlap) sta dogovorjeni za RAG korpus?"),
        (TOOL, "decision log: chunk size 512 s prekrivanjem 64 (512/64) za korpus rag-mcp"),
    ]),
    ("s06-decision-28", "homelab/docs", [
        (TOOL, "grep '| 28 |' docs/services-ai.md -> #28 Vision: spark is text-only, the RX 7600 gets no vision-LLM leg"),
        (PROMPT, "Odločitev #28 torej pravi da je spark samo besedilen brez vizualne noge."),
    ]),
    ("s07-rag-owner", "homelab/todo", [
        (PROMPT, "Kateri HD red ima v lasti rag-mcp, bralnik korpusa?"),
        (TOOL, "grep todo-table.md -> HD-268 owns rag-mcp, the corpus reader; HD-268b is the build tail"),
    ]),
    ("s07b-hd387", "homelab/todo", [
        (TOOL, "grep todo-table.md -> HD-387: every LLM path through lan-litellm must use the spark/ prefix; no bare model names"),
        (PROMPT, "HD-387 torej zahteva spark/ predpono na vsaki LLM poti."),
    ]),
    ("s08-restore-sl", "homelab/manual", [
        (PROMPT, "Kako obnovim izbrisane datoteke iz varnostne kopije?"),
        (TOOL, "cat docs/manual/restore-backup.md -> Obnovitev iz Kopia backupa; dokument je še v pripravi (wip)"),
        (PROMPT, "Torej orodje se imenuje Kopia, prav?"),
    ]),
    ("s09-gpu-host", "homelab/docs", [
        (TOOL, "lspci | grep VGA -> AMD RX 7600; host oldsrv drži embedding, rerank in speech-to-text"),
        (PROMPT, "Potrdi: starski strežnik oldsrv z grafično kartico RX 7600 poganja vse tri noge."),
    ]),
    ("s10-decision-26", "homelab/docs", [
        (TOOL, "grep '#26' docs/services-ai.md docs/pi-harness.md -> decision #26: harnesses reach the engine directly, not through a gateway"),
        (PROMPT, "Zabeleži odločitev #26: coding harness gre naravno na pogon, ne prek prehoda."),
    ]),
    # --- ports + the contradiction pair (3113 asserted, then corrected to 3114)
    ("s11-agentmemory-ports", "probe/amprobe", [
        (PROMPT, "Kateri port ima agentmemory REST in kje je vizualni pregledovalnik?"),
        (TOOL, "agentmemory banner -> REST API: 130 endpoints at http://localhost:3111/agentmemory/*; Streams ws://localhost:3112; Viewer: http://localhost:3113"),
        (PROMPT, "Torej moj vizualni pregledovalnik je na 3113. Uporabi to kot dejstvo za naprej."),
    ]),
    ("s12-correction", "probe/amprobe", [
        (PROMPT, "Popravek: v tej namestitvi smo vizualni pregledovalnik prestavili na 3114, da se izognemo trku. Prejšnja trditev o 3113 je bila napačna in je ne uporabljaj več."),
        (TOOL, "ss -ltnp -> LISTEN 127.0.0.1:3114 users:((\"node\")) # viewer moved off 3113 by probe decision; 3113 is not bound"),
    ]),
    ("s13-qdrant-port", "homelab/iac", [
        (TOOL, "grep 6333 IaC/ansible/group_vars/home_servers.yml -> qdrant REST 6333, p2p 6334 on oldsrv, behind https://qdrant.kogler.si"),
        (PROMPT, "Zapiši: Qdrant REST je na 6333."),
    ]),
    # --- paraphrase-only sessions: deliberately carry NO exact query token (M2 gate)
    ("s14-paraphrase-kv", "homelab/docs", [
        (PROMPT, "Zanima me, kolikšno pomnilniško bazo za vmesne rezultate attention ima pogon na majhnem računalniku in koliko celotnih dolgih pogovorov hkrati zmore. Ne iščem besede 'kontekst' niti številke 262144."),
        (TOOL, "docs/hardware-spark.md: the engine's key-value pool holds five hundred fifteen thousand seven hundred eighty-six tokens, which is under two full-length twenty-six-two-thousand conversations at once"),
    ]),
    ("s15-paraphrase-rerank", "homelab/docs", [
        (PROMPT, "Koliko časa potrebuje razvrščanje natančnosti za dvajset odstavkov na grafični kartici, če ne smem uporabiti besede 'rerank' in ne številke z vejico?"),
        (TOOL, "measured: re-ordering twenty candidate passages by relevance on the discrete GPU took thirty-four hundredths of a second"),
    ]),
    # --- harness shapes: subagent/task, failure, notification
    ("s16-litellm-rows", "homelab/docs", [
        (PROMPT, "Kateri modeli so na lan-litellm?"),
        (TOOL, "GET /v1/models -> spark/qwen3.8-flash-next, local-rerank, local-stt, bge-m3-vk (four rows only)"),
        ("subagent_stop", "sub-agent summary: four model rows; embeddings must be requested with the provider prefix on the VPS spine but bare on the LAN leg"),
    ]),
    ("s17-split-dns", "homelab/network", [
        ("task_completed", "task: reach the gateway from oldsrv. Result: llitellm.kogler.si does NOT resolve on oldsrv (split DNS); use the direct address http://10.10.1.30:4000/v1 instead"),
        (PROMPT, "Zapomni si: na oldsrv domena llitellm.kogler.si ne deluje, uporabiti moram 10.10.1.30:4000."),
    ]),
    ("s18-guard-failure", "homelab/scripts", [
        ("post_tool_failure", "guard-session.sh refused a write: primary=no, branch=session-20260921-2259, dirty=no -> the edit context was unsafe at that moment"),
        (PROMPT, "Kdaj je guard zavrnil zapis in kaj je bil izid?"),
        ("notification", "notified: use scripts/guard-session.sh before any write in a session worktree"),
    ]),
    ("s19-kopia-retention", "homelab/backup", [
        (TOOL, "kopia policy show -> hourly 48, daily 30, weekly 12, monthly 24; repository on nas, encryption zstd-CreationCount"),
        (PROMPT, "Kakšna je politika obdržanja za varnostne kopije?"),
    ]),
    ("s20-mikrotik-sl", "homelab/skills", [
        (PROMPT, "V slovenščini: kako preverim, ali je mikrotikova pravila požarnega zidu spustila moj promet?"),
        ("post_tool_use", "/ip firewall filter print where hits>0 -> pravilo 'drop-from-wan' je zadetilo 4219-krat; komentar v slovenščini: 'ustavi celoten dohodni promet iz WAN'"),
        ("notification", "usmeritev: za mikrotikova pravila uporabi skill skills/mikrotik/SKILL.md"),
    ]),
]


def synthetic_observations():
    obs = []
    k = 0
    for sid, project, turns in SESSIONS:
        for kind, text in turns:
            k += 1
            if kind == PROMPT:
                payload = {"prompt": text}
            elif kind == TOOL:
                payload = {"toolName": "bash",
                           "toolInput": {"command": text[:120]},
                           "toolOutput": text}
            else:
                payload = {"note": text, "toolName": "hook", "toolOutput": text}
            obs.append({
                "hookType": kind if kind not in (PROMPT, TOOL) else (
                    "prompt_submit" if kind == PROMPT else "post_tool_use"),
                "sessionId": sid,
                "project": project,
                "cwd": CWD,
                "timestamp": "2026-09-21T%02d:%02d:%02dZ" % (12 + k // 60, k % 60, (k * 3) % 60),
                "data": payload,
            })
    return obs


if __name__ == "__main__":
    out = sys.argv[1]
    a = replay_observations()
    b = synthetic_observations()
    json.dump({"replay": a, "synthetic": b,
               "counts": {"replay_obs": len(a), "synthetic_obs": len(b),
                          "synthetic_sessions": len(SESSIONS)}},
              open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("replay obs=%d  synthetic obs=%d  synthetic sessions=%d"
          % (len(a), len(b), len(SESSIONS)))
