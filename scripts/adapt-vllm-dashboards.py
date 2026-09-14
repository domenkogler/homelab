#!/usr/bin/env python3
"""Adapt grafana.com vLLM dashboard templates to the homelab file-provisioning format.

Source files (downloaded from grafana.com / the vLLM production-stack repo):
  /tmp/vllm-dash/25502.json            -> llm-inference-sglang-vllm.json
  /tmp/vllm-dash/24756.json            -> vllm-master-v2.json
  /tmp/vllm-dash/vllm-dashboard.json   -> vllm-dashboard.json (gnet 25043)

Adaptations (homelab conventions, docs/observability.md §Dashboards):
  * strip grafana.com template scaffolding: __inputs / __requires / id / gnetId
  * replace the ${DS_PROMETHEUS} datasource input with the literal uid `prometheus`
    (the homelab VictoriaMetrics datasource uid, API-seeded by the monitoring role)
  * unique uids (the 25043 export shares uid 750918234 with the 24756 one — id collision)
  * homelab tags + refresh/time defaults matching the other homelab dashboards
  * keep the panel queries byte-identical — they query the standard vLLM metric family
    (vllm:num_requests_running, vllm:kv_cache_usage_perc, vllm:generation_tokens_total, …)
"""
import json
import re
import sys
from pathlib import Path

SRC_DIR = Path("/tmp/vllm-dash")
DST_DIR = Path("IaC/ansible/roles/monitoring/files/dashboards")

# canonical homelab dashboard header fields (see homelab-ups.json)
HOMELAB_HEAD = {
    "timezone": "browser",
    "editable": True,
    "refresh": "30s",
    "time": {"from": "now-6h", "to": "now"},
}

ADAPT = [
    {
        "src": SRC_DIR / "25502.json",
        "dst": DST_DIR / "llm-inference-sglang-vllm.json",
        "title": "Homelab — LLM Inference (vLLM/SGLang)",
        "uid": "homelab-llm-inference",
        "tags": ["homelab", "vllm", "sglang", "llm"],
        "refresh": "10s",  # inference dashboards want fast refresh (gnet default)
        "time": {"from": "now-1h", "to": "now"},
    },
    {
        "src": SRC_DIR / "24756.json",
        "dst": DST_DIR / "vllm-master-v2.json",
        "title": "Homelab — vLLM Monitoring V2",
        "uid": "homelab-vllm-monitoring-v2",
        "tags": ["homelab", "vllm"],
        "refresh": "10s",
        "time": {"from": "now-1h", "to": "now"},
    },
    {
        "src": SRC_DIR / "vllm-dashboard.json",
        "dst": DST_DIR / "vllm-dashboard.json",
        "title": "Homelab — vLLM Dashboard",
        "uid": "homelab-vllm-dashboard",
        "tags": ["homelab", "vllm"],
        "refresh": "10s",
        "time": {"from": "now-1h", "to": "now"},
    },
]


def walk_scrub(obj):
    """Recursively rewrite ${DS_*} datasource refs to the literal `prometheus` uid."""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if k == "datasource" and isinstance(v, dict) and "uid" in v:
                v = dict(v)
                uid = v.get("uid", "")
                if isinstance(uid, str) and uid.startswith("${DS_"):
                    v["uid"] = "prometheus"
                out[k] = v
            else:
                out[k] = walk_scrub(v)
        return out
    if isinstance(obj, list):
        return [walk_scrub(x) for x in obj]
    return obj


def main() -> int:
    DST_DIR.mkdir(parents=True, exist_ok=True)
    for spec in ADAPT:
        src = spec["src"]
        if not src.exists():
            print(f"SKIP {src} — source missing", file=sys.stderr)
            return 1
        d = json.loads(src.read_text(encoding="utf-8"))

        # strip gnet scaffolding
        for key in ("__inputs", "__requires", "id", "gnetId"):
            d.pop(key, None)

        # rewrite datasource templates
        d = walk_scrub(d)

        # canonical homelab header
        d.update(HOMELAB_HEAD)
        d["title"] = spec["title"]
        d["uid"] = spec["uid"]
        d["tags"] = spec["tags"]
        if spec.get("refresh"):
            d["refresh"] = spec["refresh"]
        if spec.get("time"):
            d["time"] = spec["time"]
        # version: keep the source version (bump on future refreshes)
        d.setdefault("version", 1)

        # sanity: no leftover template refs, no duplicate uids across the set
        blob = json.dumps(d)
        if "${DS_" in blob:
            print(f"FAIL {spec['dst']}: leftover ${{DS_}} template ref", file=sys.stderr)
            return 1

        out = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
        dst = spec["dst"]
        dst.write_text(out, encoding="utf-8")
        print(f"wrote {dst} ({len(out)} bytes, uid={d['uid']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())