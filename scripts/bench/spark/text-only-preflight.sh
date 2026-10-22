#!/usr/bin/env bash
# ============================================================================
# text-only-preflight.sh — HD-400's pre-flight: read-only, one command, ANY session.
#
# IT ANSWERS FOUR QUESTIONS, in the order they have to be answered:
#   1. Is the staged checkpoint multimodal at all? (`Qwen4ExpForConditionalGeneration`
#      in the config.json the engine actually mounts — read off the container's own mount
#      source, so the path is derived, not typed.)
#   2. Does the live `spark-ai` command set `--limit-mm-per-prompt` at all, and in which
#      SYNTAX? (read out of `docker inspect` argv — the live SSOT, not the rendered file.)
#   3. Would the ViT therefore be loaded? (the verdict questions 1 and 2 imply together.)
#   4. What exactly is the A/B that must run BEFORE this is applied or rejected?
#
# WHY NO RULE 0 REFUSION HERE — and that is the point of the split. Nothing in this file
# produces a timed number and nothing here issues an inference request: it reads a
# `config.json`, `docker inspect` argv and the repo tree. Rule 0
# (spark/llm-profiles/README.md) forbids a spark-served session from taking timed numbers
# and from contending for the pool; todo-table.md §C rule 2 keeps
# "counter/log/`docker inspect` reads" legal from exactly such a session. So this pre-flight
# runs from a spark-served seat — which is what makes it worth having landed today, while the
# act that DECIDES the row (the A/B, which loads the engine) belongs to an externally-served
# session on the runner station. The contrast is written into needle-window.sh beside here:
# a needle test issues requests against the engine and therefore refuses.
#
# TWO TRAPS, ENCODED AS MACHINE CHECKS RATHER THAN AS PROSE SOMEONE REMEMBERS:
#   · SYNTAX. The `image=0,video=0` COMMA form ERRORS on the pinned vLLM (upstream #39687).
#     So this script emits only the JSON form
#         --limit-mm-per-prompt '{"image": 0, "video": 0}'      (≡ --language-model-only)
#     and if the LIVE engine is found carrying the comma form it stops with exit 4 instead of
#     describing a command that would not boot. The self-test proves the guard has teeth by
#     feeding the comma form in, and asserts the comma form never appears in the script's own
#     output.
#   · CONSEQUENCE. With `image: 0` an image part is a hard **400**, not a silent drop. An A/B
#     that does not include a multimodal request that is EXPECTED to 400 has not measured the
#     change, it has measured half of it. The A/B this prints includes that leg, with its
#     expected status on both arms.
#
# WHAT THIS IS NOT: a speed change and not an apply. With no image tokens the vision tower
# never executes, so **C2 decode is expected FLAT** — the win is memory returned to the ONE
# 121.62 GiB pool (the tower ~0.5–1 GiB device + the mm processor cache, default 4 GiB of host
# RAM, same pool), where 1 GiB ≈ 32.2k KV tokens at the measured 30.3 KiB/token. The freed GiB
# is spent as a SEPARATE row (KV or margin), never in the same change, or the ledger cannot
# attribute either. Applying is an OWNER-WINDOW IaC act that re-creates `spark-ai`; this script
# CHANGES NOTHING — it prints the IaC line an owner would change, read out of the tree, and
# the row stays "proposed, bench-gated, NOT applied" until an A/B says otherwise.
#
# Usage
#   scripts/bench/spark/text-only-preflight.sh [--host spark] [--container NAME]
#       [--model-dir PATH] [--config-file PATH] [--base-url URL] [--dry-run] [--self-test]
#
#   --config-file  read this config.json instead of the box's (a staged copy, a fixture, an
#                  off-line read). The multimodal half then comes from a FILE, and nothing in
#                  the run touches a host.
#   --model-dir    override the checkpoint dir when the container's mount source is not readable.
#   --base-url     where the 400-leg of the A/B would be pointed; it is PRINTED, never sent.
#
# Fixture hooks — what keeps --self-test off every host:
#   PREFLIGHT_SSH_CMD   command that receives each far-side command on stdin
#   PREFLIGHT_IAC       repo tree to read the IaC line out of (defaults to $REPO)
# The self-test also puts a tripwire `ssh` first on PATH and asserts it was never called, so
# "never shells out to a host" is proven, not promised.
#
# Exit: 0 the pre-flight completed and printed its verdict (a FINDING — "the ViT is loaded" —
#         is a verdict, not an error) ·
#       1 a read failed or the config could not be judged: UNKNOWN is never read as TEXT-ONLY ·
#       2 usage ·
#       4 SYNTAX REFUSED — a comma-form `--limit-mm-per-prompt` is live, and it errors on the
#         pinned vLLM (#39687); nothing this script prints would reproduce it ·
#       6 the engine container is not running (measured, not assumed)
# ============================================================================
set -euo pipefail
# Byte counts and GiB figures land in a table and in equality tests; under an sl_SI locale awk
# prints 15,99 where the fixture expects 15.99. Fix the format, not the environment.
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root FOUND, never assumed from a depth (lib/repo-root.sh): the IaC line this prints is
# read out of the tree, and a wrong depth prints a path that does not exist.
_hl_d="$SELF_DIR"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"

IAC="${PREFLIGHT_IAC:-$REPO}"
MM_ARCH='Qwen4ExpForConditionalGeneration'
# THE one form this act ever prints. The comma form errors on the pinned build (#39687), so it
# is not offered as an alternative anywhere — not in a comment, not in a hint.
MM_JSON='{"image": 0, "video": 0}'
MM_FLAG='--limit-mm-per-prompt'
FREED_GIB_NOTE='1 GiB ≈ 32.2k KV tokens (measured 30.3 KiB/token)'
BASE_URL="${PREFLIGHT_BASE_URL:-https://llm.ts.kogler.si/v1}"

HOST="spark"
CONTAINER="${VLLM_CONTAINER:-vllm-qwen-spark}"
MODEL_DIR=""
CONFIG_FILE=""
TEST=0
DRY=0
SELF_NAME="$(basename "${BASH_SOURCE[0]}")"

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --host)       [ $# -ge 2 ] || die "--host needs the box name" 2; HOST="$2"; shift ;;
    --container)  [ $# -ge 2 ] || die "--container needs the engine container name" 2; CONTAINER="$2"; shift ;;
    --model-dir)  [ $# -ge 2 ] || die "--model-dir needs the checkpoint directory" 2; MODEL_DIR="$2"; shift ;;
    --config-file)[ $# -ge 2 ] || die "--config-file needs a path to a config.json" 2; CONFIG_FILE="$2"; shift ;;
    --base-url)   [ $# -ge 2 ] || die "--base-url needs the endpoint the A/B would run against" 2
                  BASE_URL="$2"; shift ;;
    --dry-run)    DRY=1 ;;
    --self-test)  TEST=1 ;;
    *)            die "unknown arg $1 — see the Usage block" 2 ;;
  esac
  shift
done

# The ONE door to the far side. Every command sent through it is a read (docker inspect, one
# bounded head -c of a config.json); --self-test intercepts it here so the fixture arms exercise
# the real command strings, and the self-test's PATH tripwire proves `ssh` itself is never run.
host_read() {
  local cmd="$1"
  if [ -n "${PREFLIGHT_SSH_CMD:-}" ]; then
    printf '%s\n' "$cmd" | $PREFLIGHT_SSH_CMD
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$cmd"
  fi
}

STATE_SNIPPET="docker inspect -f '{{.State.Running}} {{.State.StartedAt}} restarts={{.RestartCount}}' @CONTAINER@"
ARGV_SNIPPET="docker inspect -f '{{join .Config.Cmd \" \"}}' @CONTAINER@"
# The mount source the engine reads its weights from — derived from the live container, so the
# config.json path is never typed (the SSOT-is-live rule in prompt-spark-llm.md).
MOUNT_SNIPPET="docker inspect -f '{{range .Mounts}}{{if eq .Destination \"/model\"}}{{.Source}}{{end}}{{end}}' @CONTAINER@"
CONFIG_SNIPPET="head -c 262144 @MODELDIR@/config.json"

# scrub_argv — the engine argv carries `--api-key`; a raw capture of a running system holds its
# own credentials. Scrub at the point of write, as run-scenario.sh and gate6-couple.sh do.
scrub_argv() { sed -E 's/(--api-key[= ])[^ "]+/\1<scrubbed>/g'; }

# mm_form <value> — classify one --limit-mm-per-prompt value.
#   json   → the only accepted form: a JSON object (the zeroed one is what HD-400 proposes)
#   comma  → `image=0,video=0`: ERRORS on the pinned vLLM (#39687). Named so a reader can find
#            the reason, never so a reader can copy it.
#   other  → anything else: printed raw, judged by a human, never silently accepted.
mm_form() {
  local v="${1# }"
  v="${v%$'\n'}"
  case "$v" in
    ''|'--'*'='*) printf 'other' ;;
    '{'*)         printf 'json' ;;
    *'='*)        printf 'comma' ;;
    *)            printf 'other' ;;
  esac
}

# mm_value_of <argv> — the value the live command hands to --limit-mm-per-prompt. BOTH shapes
# are real on the vLLM CLI (two tokens, or --flag=<value>); a parser that knows only one answers
# "not set" for a flag that IS set, which is the wrong-way failure this script exists to avoid.
mm_value_of() {
  local prev="" tok out=""
  for tok in $1; do
    case "$tok" in
      "$MM_FLAG"=*) out="${tok#*=}"; prev=""; continue ;;
      "$MM_FLAG")   prev="$MM_FLAG"; continue ;;
    esac
    if [ "$prev" = "$MM_FLAG" ]; then out="$tok"; prev=""; continue; fi
    prev="$tok"
  done
  printf '%s' "$out"
}

# argv_facts <argv> — the argv half that decides THIS question, printed for the report. The
# bearer is not in the list at all, and the output goes through scrub_argv anyway: a raw capture
# of a running engine holds its own credentials, which is the leak this repo already has a
# number for (spark/reports/hd489-overnight-20261006-0226/raw/b10-boot.txt, HD-1170).
argv_facts() {
  printf '%s\n' "$1" | tr ' ' '\n' \
    | grep -A1 -e '^--limit-mm-per-prompt$' -e '^--language-model-only$' -e '^--mm-processor-cache-gb$' \
                -e '^--served-model-name$' -e '^--max-model-len$' \
    | grep -v '^--$' | tr '\n' ' ' | scrub_argv \
    | sed -E 's/(--limit-mm-per-prompt )[A-Za-z_]+=[^ ]*/\1<rejected comma form, #39687 — not repeated>/g' || true
}

# argv_has <argv> <flag> — is the flag present as its own token (or flag=value)?
argv_has() {
  printf '%s\n' "$1" | grep -qE -- "(^|[[:space:]])$2(=|[[:space:]]|\$)"
}

# The A/B, printed verbatim. One variable (BENCHMARK-PLAN §6 step 11), and the leg that accepts
# the consequence is part of the measurement, not a footnote to it.
print_ab() {
  printf '## The A/B that must run before this is applied or rejected\n\n'
  printf 'ONE variable: the flag below, nothing else — no pin change, no pool change, no clock\n'
  printf 'change (a clock regime per arm or there is no comparison at all, hardware-spark.md\n'
  printf '§GPU clock cap). Two arms, same boot, same regime:\n\n'
  printf '| arm | engine args | expected |\n|---|---|---|\n'
  printf '| A (live today) | no %s | the ViT + mm processor cache resident; an image part answers 200 |\n' "$MM_FLAG"
  local b_arg="$MM_FLAG '$MM_JSON'"   # the argv arm B would carry, spelled once, quoted once
  printf '| B (proposed) | `%s` (≡ `--language-model-only`) | boot-side MiB down, host usable up, C2 FLAT, an image part answers 400 |\n' "$b_arg"
  printf '\nFive legs, all of them in the same window pair, none optional — the first four are\n'
  printf 'the measurement, the fifth is the consequence. Half a change is not a measurement:\n\n'
  printf '1. **boot per-pid MiB DOWN** — `nvidia-smi --query-compute-apps=pid,used_memory`, read\n'
  printf '   as `engine_pid <PID> mib` by [`run-scenario.sh`](run-scenario.sh)'"'"'s at-rest block.\n'
  printf '   Expect roughly the tower (0.5–1 GiB device) + the mm processor cache (default 4 GiB\n'
  printf '   of host RAM — the SAME unified pool on GB10).\n'
  printf '2. **host usable UP** — `usable = MemAvailable − CmaFree` (never raw MemAvailable: CMA\n'
  printf '   inflates it under pressure). %s, so the freed GiB is quoted in KV tokens.\n' "$FREED_GIB_NOTE"
  printf '3. **C2 decode WITHIN NOISE** — `run-scenario.sh hd400-A C2` and `hd400-B C2`, one arm\n'
  printf '   each, `--profile A|B --client <stamp>`. **Flat is the expected result**: with no\n'
  printf '   image tokens the tower never executes. A decode "win" here is a confound, not a gain.\n'
  printf '4. **the accuracy battery UNCHANGED (10/10)** — `gate6-couple.sh` so the battery and its\n'
  printf '   baseline share one budget, and module-skipping is verified rather than assumed:\n'
  printf '   upstream skips disabled modality modules per model implementation (#21943, closed via\n'
  printf '   #22299) and this is a fork build, so read the loaded modules out of the boot log too.\n'
  printf '5. **the consequence leg** — one multimodal request per arm, because `image: 0` makes an\n'
  printf '   image part a hard **400**, not a silent drop:\n\n'
  printf '```\n# SPARK_LLM_BEARER comes from the `spark-llm_api` vault item at the call site —\n'
  printf '# never into a file, a commit, or this transcript.\n'
  printf 'curl -sS -o /dev/null -w '"'"'%%{http_code}\\n'"'"' \\\n'
  printf '  -H "Authorization: Bearer $SPARK_LLM_BEARER" -H "Content-Type: application/json" \\\n'
  printf '  -d '"'"'{\"model\":\"spark/qwen3.8-flash-next\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"what is in this image?\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==\"}}]}]}'"'"' \\\n'
  printf '  %s/chat/completions\n```\n\n' "${BASE_URL%/}"
  printf '# The endpoint is what --base-url carries; `/v1/chat/completions` is the path the\n'
  printf '# OpenAI-compat server serves (`/health` is the one path NOT under /v1).\n'
  printf 'Expected: **200 on arm A** (the modality is enabled, default 999 per modality) and\n'
  printf '**400 on arm B**. If B answers 200 the flag did not take effect and the memory read is a\n'
  printf 'coincidence; if A answers 400 something else already changed the modality limits.\n\n'
  printf 'Then, and only then, the OWNER decision: apply, or record the number that rejected it.\n'
  printf 'The freed GiB is spent as a **separate** row (KV or margin) — never in this change, or\n'
  printf 'the ledger cannot attribute either half.\n'
}

# The IaC line an owner would have to change, READ OUT OF THE TREE. Printed as file + key, with
# the render line that decides whether a spaced value survives it — because that is the one place
# this proposal can be silently mangled, and it is a fact about the tree, not an opinion.
print_iac_line() {
  local profile_vars compose render quote
  # The folder is `IaC` — capital I, lower a, capital C. A lowercased path prints a file that
  # does not exist, which is the wrong-way failure this section exists to avoid.
  profile_vars="$IAC/IaC/ansible/group_vars/spark.yml"
  compose="$IAC/IaC/ansible/templates/docker_services/spark-ai/docker-compose.yml.j2"
  printf '## The IaC line an owner would change (nothing here is written by this script)\n\n'
  printf '· `%s` → `spark_llm_profiles.<profile>.args_extra:` — add the flag and its value as\n' "$profile_vars"
  printf '  TWO list entries, per profile (the key that already carries every profile-specific\n'
  printf '  engine flag that is not composed):\n'
  printf '  `%s`, `%s`\n\n' "'$MM_FLAG'" "'$MM_JSON'"
  if [ -f "$compose" ]; then
    render="$(grep -n 'for a in command_extra' "$compose" | head -1 | sed "s|^|${compose#"$IAC"/}:|" || true)"
    quote="$(grep -n 'never_evict_prompt | to_json' "$compose" | head -1 | sed "s|^|${compose#"$IAC"/}:|" || true)"
    printf '· rendered by `%s`:\n' "${compose#"$IAC"/}"
    [ -n "$render" ] && printf '  `%s`\n' "$render"
    printf '\n  The loop emits each entry RAW (`- {{ a }}`), so a value containing SPACES arrives\n'
    printf '  as a YAML flow mapping and the compose either fails to parse or serves something else\n'
    printf '  than the review showed. The tree already solves that for another spaced value:\n'
    [ -n "$quote" ] && printf '  `%s`\n' "$quote"
    printf '\n  So the owner-window check is the existing render instruments, not a hand read:\n'
    printf '  `python3 scripts/gate/validate-docker-services.py --only spark-ai` and\n'
    printf '  `python3 scripts/bench/spark-llm-render-matrix.py` (gate 0 in llm-profiles/README.md).\n'
  else
    printf '· UNKNOWN: `%s` is not readable from here, so the render line cannot be quoted.\n' "${compose#"$IAC"/}"
    printf '  A missing read is not a pass — say so in the row rather than assuming the key.\n'
  fi
  printf '\nApplying it is a converge that RE-CREATES `spark-ai` (~20 min boot), which is an owner-\n'
  printf 'window act under todo-table.md §C rule 2 — and while the row stays un-applied, the\n'
  printf 'converge is exactly what a later `--check` must not be used to rehearse blind.\n'
}

run_main() {
  local st argv mm_value="" mm_seen=0 form cfg_src cfg arch_line verdict_mm verdict_vit
  printf '>>> text-only pre-flight — host=%s container=%s (READ-ONLY: no timed number, no request)\n' \
    "$HOST" "$CONTAINER"

  # --- 1. the live command: is the modality limit set, and in which syntax? -------------------
  st="$(host_read "${STATE_SNIPPET//@CONTAINER@/$CONTAINER}" 2>/dev/null || echo "false unknown")"
  if [ "$(printf '%s' "$st" | awk '{print $1}')" != "true" ]; then
    printf 'ERROR: container %s is not running on %s — there is no live engine to read.\n' "$CONTAINER" "$HOST" >&2
    printf '       The name resolves as IaC spark_vllm_container -> spark_llm_profiles[<p>].container;\n' >&2
    printf '       pass --container for the arm actually serving, or --config-file to read a staged\n' >&2
    printf '       checkpoint off-line (that half needs no box at all).\n' >&2
    exit 6
  fi
  argv="$(host_read "${ARGV_SNIPPET//@CONTAINER@/$CONTAINER}" || true)"
  printf '>>> live engine argv (the half that matters, bearer never included): %s\n' "$(argv_facts "$argv")"

  if argv_has "$argv" "$MM_FLAG"; then
    mm_seen=1
    mm_value="$(mm_value_of "$argv")"
  elif argv_has "$argv" '--language-model-only'; then
    mm_seen=1
    mm_value="$MM_JSON"     # the documented equivalent — same verdict, different spelling
    printf '>>> `--language-model-only` is live: the documented equivalent of the zeroed JSON form.\n'
  fi
  if argv_has "$argv" '--mm-processor-cache-gb'; then
    printf '>>> `--mm-processor-cache-gb` is set too — the optional second row of the same proposal.\n'
  fi

  form="absent"
  if [ "$mm_seen" = 1 ]; then
    form="$(mm_form "$mm_value")"
    case "$form" in
      json)  printf '>>> %s %s is live — JSON form, accepted syntax.\n' "$MM_FLAG" "$mm_value" ;;
      comma) printf 'ERROR: SYNTAX REFUSED — the live engine carries %s in the COMMA form, which\n' "$MM_FLAG" >&2
             printf '       ERRORS on the pinned vLLM (upstream #39687). This script will not print\n' >&2
             printf '       a command in that shape, and it will not describe a boot that cannot boot.\n' >&2
             printf '       The accepted form is %s %s (≡ --language-model-only).\n' "$MM_FLAG" "$MM_JSON" >&2
             exit 4 ;;
      other) printf '>>> %s is live with an UNRECOGNISED value: %s — read it yourself before trusting\n' "$MM_FLAG" "$mm_value" >&2
             printf '    any verdict here; it is not the zeroed JSON form this row proposes.\n' >&2 ;;
    esac
  else
    printf '>>> no %s and no --language-model-only in the live command: vLLM keeps its default of\n' "$MM_FLAG"
    printf '    999 items per modality, i.e. the multimodal stack loads at full defaults.\n'
  fi

  # --- 2. the checkpoint: multimodal at all? --------------------------------------------------
  cfg="" cfg_src=""
  if [ -n "$CONFIG_FILE" ]; then
    [ -r "$CONFIG_FILE" ] || die "the config file '$CONFIG_FILE' is not readable — a missing read is not a TEXT-ONLY answer" 1
    cfg="$(head -c 262144 "$CONFIG_FILE")"
    cfg_src="$CONFIG_FILE (local file, no host read)"
  else
    if [ -z "$MODEL_DIR" ]; then
      MODEL_DIR="$(host_read "${MOUNT_SNIPPET//@CONTAINER@/$CONTAINER}" 2>/dev/null | tr -d '[:space:]')" || true
    fi
    [ -n "$MODEL_DIR" ] || {
      printf 'ERROR: no /model mount source came back from %s, so the checkpoint'"'"'s config.json cannot\n' "$HOST" >&2
      printf '       be located. Pass --model-dir or --config-file: refusing to guess a path, because\n' >&2
      printf '       a guessed path reads someone else'"'"'s config and answers the one question wrongly.\n' >&2
      exit 1; }
    cfg="$(host_read "${CONFIG_SNIPPET//@MODELDIR@/$MODEL_DIR}" 2>/dev/null)" || true
    [ -n "$cfg" ] || {
      printf 'ERROR: the config.json read at %s/config.json came back empty. UNKNOWN is not TEXT-ONLY:\n' "$MODEL_DIR" >&2
      printf '       no verdict prints from a read that did not happen. Fix the read, or pass\n' >&2
      printf '       --config-file with a staged copy.\n' >&2
      exit 1; }
    cfg_src="$MODEL_DIR/config.json (read from $HOST)"
  fi

  if printf '%s\n' "$cfg" | grep -qF -- "$MM_ARCH"; then
    verdict_mm="MULTIMODAL"
  elif printf '%s\n' "$cfg" | grep -qF -- '"architectures"'; then
    verdict_mm="TEXT-ONLY"
  else
    {
      printf 'ERROR: the config read from %s holds no "architectures" key at all, so multimodality\n' "$cfg_src" >&2
      printf '       cannot be judged from it — and UNKNOWN is never read as TEXT-ONLY.\n' >&2
      exit 1; }
  fi
  arch_line="$(printf '%s\n' "$cfg" | tr -d ' \n' | grep -oE '"architectures":\[[^]]*\]' | head -1 || true)"

  # --- 3. the verdict the two reads imply together ---------------------------------------------
  printf '\n## Verdict\n\n'
  printf '| read | value | source |\n|---|---|---|\n'
  printf '| checkpoint architecture | %s | %s |\n' "${arch_line:-not found}" "$cfg_src"
  printf '| multimodal? | %s | `%s` in config.json |\n' "$verdict_mm" "$MM_ARCH"
  printf '| %s | %s | live container argv |\n' "$MM_FLAG" \
    "$([ "$mm_seen" = 1 ] && printf 'set (%s form): %s' "$form" "$mm_value" || printf 'NOT SET — default 999 per modality')"

  verdict_vit="UNKNOWN — one of the two reads is missing, so the ViT question is not answered"
  case "$verdict_mm/$form" in
    MULTIMODAL/absent)
      verdict_vit="LOADED — the vision tower AND the mm processor cache are resident for consumers that are all text-only. This is the finding HD-400 is about." ;;
    MULTIMODAL/json)
      verdict_vit="NOT loaded — the zeroed limit is live, so the row's change is ALREADY APPLIED. Verify on this fork that the modules really are skipped (#21943 is per-model-implementation) before writing that conclusion." ;;
    MULTIMODAL/other)
      verdict_vit="PROBABLY LOADED — a limit is set but it is not the zeroed JSON form, so the tower is only skipped if the value disables every modality. Read the value." ;;
    TEXT-ONLY/*)
      verdict_vit="N/A — a text-only checkpoint has no vision tower to drop; the row is moot for this arm." ;;
    UNKNOWN/*) : ;;
  esac
  printf '| would the ViT load? | %s |\n\n' "$verdict_vit"

  printf 'The win is MEMORY, not speed: no image tokens means the tower never executes, so decode\n'
  printf 'is expected FLAT. What comes back is pool headroom on the boot-bound side (%s).\n' "$FREED_GIB_NOTE"
  printf 'This script wrote nothing and converged nothing; applying stays an owner-window IaC act.\n\n'

  print_iac_line
  printf '\n'
  print_ab
}

# --dry-run is ONE path: the reads it would take, then the two sections it would print. Both
# sections are local text (the tree, the A/B), so nothing about --dry-run differs from a real run
# except that no read happens — which is what makes the printed A/B trustworthy to copy.
run_dry() {
  printf '# the reads this pre-flight takes, then the two sections it prints\n\n'
  printf '  ssh %s %s\n' "$HOST" "${STATE_SNIPPET//@CONTAINER@/$CONTAINER}"
  printf '  ssh %s %s\n' "$HOST" "${ARGV_SNIPPET//@CONTAINER@/$CONTAINER}"
  printf '  ssh %s %s\n' "$HOST" "${MOUNT_SNIPPET//@CONTAINER@/$CONTAINER}"
  printf '  ssh %s %s\n' "$HOST" "${CONFIG_SNIPPET//@MODELDIR@/<the mount source it just read>}"
  printf '  read  %s/IaC/ansible/group_vars/spark.yml + the spark-ai compose template (local)\n\n' "$IAC"
  printf '# nothing else. No engine request, no timed number, no mutate verb — which is exactly\n'
  printf '# why this script needs no Rule 0 guard and needle-window.sh beside it does.\n\n'
  print_iac_line
  printf '\n'
  print_ab
}

# ---------------------------------------------------------------------------
# --self-test — fixtures only. Nothing here touches a host: the far-side door goes through
# PREFLIGHT_SSH_CMD, the checkpoint comes from a written-out fixture config.json, and a PATH
# tripwire proves `ssh` itself was never executed in any arm. THAT is the assertion that makes
# "a legal read from any session" checkable rather than claimed.
# ---------------------------------------------------------------------------
run_self_test() {
  local t fails=0 rc out cmdlog d cfg_mm cfg_txt cfg_odd trip
  t="$(mktemp -d)"
  local self="$SELF_DIR/$SELF_NAME"

  # A fixture tree with the real compose-template shape, so the IaC line the script prints is
  # read out of a tree and not recited from this file.
  mkdir -p "$t/repo/IaC/ansible/group_vars" "$t/repo/IaC/ansible/templates/docker_services/spark-ai" "$t/bin"
  cat > "$t/repo/IaC/ansible/group_vars/spark.yml" <<'YML'
spark_llm_profile: reasoning
spark_llm_profiles:
  reasoning:
    max_model_len: 262144
    args_extra: []
YML
  cat > "$t/repo/IaC/ansible/templates/docker_services/spark-ai/docker-compose.yml.j2" <<'J2'
{% set command_extra = [] %}
{% if profile.never_evict_prompt %}{%   set command_extra = command_extra + ['--never-evict-kv-cache-prompt-includes', profile.never_evict_prompt | to_json] %}{% endif %}
{% set command_extra = command_extra + profile.args_extra | default([]) %}
    command:
{% for a in command_extra %}
      - {{ a }}
{% endfor %}
J2

  # Two checkpoints: one multimodal, one text-only. And one that is not a config at all.
  cfg_mm="$t/config-mm.json"; cfg_txt="$t/config-txt.json"; cfg_odd="$t/config-odd.json"
  cat > "$cfg_mm" <<'JSON'
{ "architectures": ["Qwen4ExpForConditionalGeneration"],
  "vision_config": { "depth": 27, "hidden_size": 1152, "out_hidden_size": 2560 } }
JSON
  cat > "$cfg_txt" <<'JSON'
{ "architectures": ["Qwen3MoeForCausalLM"], "num_hidden_layers": 48 }
JSON
  printf '{ "something_else": true }\n' > "$cfg_odd"

  cmdlog="$t/commands.log"; : > "$cmdlog"
  trip="$t/ssh-was-called"; : > "$trip"

  # The fake box. Reads only; it answers the three commands this script is allowed to send and
  # fails loud on anything else. FAKE_ARGV is how an arm puts a specific engine on the box.
  cat > "$t/bin/fake-host" <<'FIX'
#!/usr/bin/env bash
cmd="$(cat)"
printf '%s\n' "$cmd" >> "${FAKE_LOG:?}"
case "$cmd" in
  *'.State.Running'*) printf '%s\n' "true 2026-10-22T09:00:00Z restarts=0" ;;
  *'.Config.Cmd'*)    printf '%s\n' "${FAKE_ARGV:---model /model --served-model-name spark/m --max-model-len 262144 --api-key REDACTED-IN-FIXTURE}" ;;
  *'.Mounts'*)        printf '%s\n' "/mnt/spark_nvme/models/Qwen3.8-Flash-Next-AWQ" ;;
  *'config.json'*)    printf '%s\n' '{"architectures": ["Qwen4ExpForConditionalGeneration"], "vision_config": {"depth": 27}}' ;;
  *) printf 'fake-host: unhandled command: %s\n' "$cmd" >&2; exit 9 ;;
esac
FIX
  chmod +x "$t/bin/fake-host"

  # The tripwire: any real `ssh` from any arm lands here and reddens the run.
  cat > "$t/bin/ssh" <<FIX
#!/usr/bin/env bash
printf '%s\n' "ssh \$*" >> "$trip"
exit 99
FIX
  chmod +x "$t/bin/ssh"

  ok()  { printf '  ok:   %s\n' "$1"; }
  bad() { printf '  FAIL: %s\n' "$1"; fails=$((fails + 1)); }
  want() { if printf '%s\n' "$out" | grep -qF -- "$1"; then ok "$2"; else bad "$2 (wanted \"$1\": $(printf '%s' "$out" | tail -3))"; fi; }
  nohave() { if printf '%s\n' "$out" | grep -qF -- "$1"; then bad "$2 — the text \"$1\" appeared"; else ok "$2"; fi; }

  drive() {
    out="$(PATH="$t/bin:$PATH" FAKE_LOG="$cmdlog" PREFLIGHT_SSH_CMD="$t/bin/fake-host" \
      PREFLIGHT_IAC="$t/repo" REPO="$t/repo" PI_PROVIDER=spark PI_MODEL=spark/qwen3.8-flash-next \
      bash "$self" "$@" 2>&1)" && rc=0 || rc=$?
  }

  echo "case (a): a multimodal fixture config reads MULTIMODAL — and it does that from a spark-served seat"
  drive --config-file "$cfg_mm"
  [ "$rc" = 0 ] && ok "the pre-flight runs (rc 0) under PI_PROVIDER=spark — it takes no timed number" \
    || bad "spark-served rc=$rc, want 0 (this script must NOT carry a Rule 0 guard)"
  want "MULTIMODAL" "the checkpoint verdict names the architecture"
  want "Qwen4ExpForConditionalGeneration" "and quotes the architecture it read"
  nohave "Rule 0" "no Rule 0 refusal — a config/argv read is legal from any session"
  [ "$(wc -l < "$cmdlog")" -gt 0 ] && ok "the live-command read still ran (the argv half needs the box)" \
    || bad "no far-side read happened, so question 2 was never answered"
  drive                     # no --config-file: the checkpoint half must come from the BOX's mount
  [ "$rc" = 0 ] && ok "the box route completes" || bad "box route rc=$rc: $(printf '%s' "$out" | tail -3)"
  want "MULTIMODAL" "and the architecture read from the box reads MULTIMODAL too"
  grep -qF '.Mounts' "$cmdlog" \
    && ok "the config path came from the container's mount source — derived, never typed" \
    || bad "no mount read happened, so the config path was guessed"

  echo "case (b): an absent --limit-mm-per-prompt reads 'ViT loaded', a set JSON form reads 'not loaded'"
  : > "$cmdlog"
  drive --config-file "$cfg_mm"
  want "LOADED — the vision tower AND the mm processor cache are resident" "an unset limit reads as the ViT being loaded"
  want "NOT SET — default 999 per modality" "and says the default it inferred that from"
  want "The win is MEMORY, not speed" "the flat-decode caveat is printed, not left to memory"
  drive --config-file "$cfg_mm" --dry-run
  [ "$rc" = 0 ] && ok "--dry-run exits 0" || bad "--dry-run rc=$rc"
  : > "$cmdlog"
  FAKE_ARGV='--model /model --served-model-name spark/m --max-model-len 262144 --limit-mm-per-prompt {"image": 0, "video": 0} --api-key REDACTED-IN-FIXTURE' \
    drive --config-file "$cfg_mm"
  [ "$rc" = 0 ] && ok "the JSON zeroed form is accepted (rc 0)" || bad "rc=$rc: $(printf '%s' "$out" | tail -3)"
  want "NOT loaded — the zeroed limit is live" "and the ViT verdict flips with the flag"
  want "#21943" "and it still demands the module-skip be measured on this fork, not assumed"

  echo "case (c): the comma form is refused — in its own emitted command, with a mutation arm for teeth"
  nohave "image=0,video=0" "the comma form is never printed as an option"
  want '--limit-mm-per-prompt ' "the flag is printed"
  want '"image": 0, "video": 0}' "and its value is the JSON object, braces and quoting intact"
  want "≡ \`--language-model-only\`" "and names its documented equivalent"
  : > "$cmdlog"
  FAKE_ARGV='--model /model --served-model-name spark/m --limit-mm-per-prompt image=0,video=0 --api-key REDACTED-IN-FIXTURE' \
    drive --config-file "$cfg_mm"
  [ "$rc" = 4 ] && ok "a live comma form exits 4 — the guard fires on a real argv, not on a typo" \
    || bad "comma-form arm rc=$rc, want 4: $(printf '%s' "$out" | tail -3)"
  want "SYNTAX REFUSED" "the refusal names what it refused"
  want "#39687" "and cites the upstream defect that makes it a defect"
  nohave "image=0,video=0" "even the refusal does not reproduce the broken form"

  echo "case (d): no arm shelled out to a host — the PATH tripwire was never touched"
  [ "$(wc -l < "$trip")" -eq 0 ] && ok "ssh was never executed in $(wc -l < "$cmdlog") recorded far-side command(s)" \
    || bad "the arms really shelled out: $(head -1 "$trip")"
  [ "$(grep -cE 'docker (restart|stop|rm|kill|run)|systemctl|reboot|sed -i|ansible-playbook|curl' "$cmdlog")" -eq 0 ] \
    && ok "no mutate verb and no request reached the transport" \
    || bad "a mutate verb or request reached the transport: $(grep -nE 'docker (restart|stop|rm|kill|run)|systemctl|reboot|sed -i|ansible-playbook|curl' "$cmdlog" | head -2)"

  echo "case (e): the A/B and the IaC line are printed, and the 400 consequence is a leg"
  drive --config-file "$cfg_mm"
  want "400 on arm B" "the A/B carries the multimodal leg and its expected status"
  want "200 on arm A" "and the same leg's expectation on the live arm"
  want "image part a hard" "and states the consequence it is there to catch"
  want "C2 decode WITHIN NOISE" "the A/B says decode is expected FLAT, not improved"
  want "separate** row (KV or margin)" "and that the freed GiB is spent as another row, never this one"
  want "spark_llm_profiles.<profile>.args_extra:" "the IaC line names the key an owner edits"
  printed_path="$(printf '%s\n' "$out" | grep -oE '[^ `]+IaC/ansible/group_vars/spark\.yml' | head -1)"
  { [ -n "$printed_path" ] && [ -r "$printed_path" ]; } \
    && ok "the IaC path it prints is a real readable file ('$printed_path')" \
    || bad "the printed IaC path is not a readable file — a wrong-cased folder prints a file that does not exist ('$printed_path')"
  want "templates/docker_services/spark-ai/docker-compose.yml.j2" "and the template that renders it"
  want "for a in command_extra" "quoting the render line READ from the tree"
  want "to_json" "and the tree's own precedent for a value containing spaces"
  want "RE-CREATES" "and that applying is an owner-window act this script never takes"
  snap="$(cd "$t/repo" && find . -type f -exec md5sum {} + | sort)"
  drive --config-file "$cfg_mm"
  snap2="$(cd "$t/repo" && find . -type f -exec md5sum {} + | sort)"
  [ "$snap" = "$snap2" ] && ok "the tree is byte-identical after two runs — this pre-flight changes nothing" \
    || bad "the pre-flight modified the tree"

  echo "case (f): a read that did not happen is never a verdict"
  drive --config-file "$cfg_txt"
  [ "$rc" = 0 ] && ok "a text-only checkpoint is a verdict, not an error" || bad "rc=$rc"
  want "TEXT-ONLY" "it reads TEXT-ONLY"
  want "N/A — a text-only checkpoint has no vision tower" "and the ViT question resolves to moot"
  drive --config-file "$cfg_odd"
  [ "$rc" = 1 ] && ok "a config with no architectures key exits 1 — UNKNOWN is not TEXT-ONLY" || bad "rc=$rc, want 1"
  want "UNKNOWN" "and it says UNKNOWN"
  drive --config-file "$t/no-such-config.json"
  [ "$rc" = 1 ] && ok "an unreadable config file is refused, not guessed" || bad "rc=$rc, want 1"
  drive --not-a-flag
  [ "$rc" = 2 ] && ok "an unknown flag is refused with rc 2" || bad "rc=$rc, want 2"

  echo "case (g): an engine that is not running is measured, not assumed"
  cat > "$t/bin/fake-stop-host" <<'FIX'
#!/usr/bin/env bash
printf '%s\n' "false exited"
FIX
  chmod +x "$t/bin/fake-stop-host"
  out="$(PATH="$t/bin:$PATH" FAKE_LOG="$cmdlog" PREFLIGHT_SSH_CMD="$t/bin/fake-stop-host" \
    PREFLIGHT_IAC="$t/repo" REPO="$t/repo" bash "$self" --config-file "$cfg_mm" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 6 ] && ok "a container that is not running exits 6 naming the container" || bad "rc=$rc, want 6"
  want "not running" "and the message says what it measured"

  rm -rf "$t"
  if [ "$fails" = 0 ]; then echo "SELF-TEST OK"; return 0; fi
  printf 'SELF-TEST FAILED: %s assertion(s)\n' "$fails"; return 1
}

if [ "$TEST" = 1 ]; then run_self_test; exit $?; fi
if [ "$DRY" = 1 ]; then run_dry; exit 0; fi
run_main
