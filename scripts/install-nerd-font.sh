#!/usr/bin/env bash
# =====================================================================
# install-nerd-font.sh — place and PROVE the pinned Nerd Font family the seat
#   TUI's icons come from (nerd-fonts release, HD-1110). Debian/WSL side; the
#   Windows side is scripts/win/install-nerd-font.ps1.
#
# WHY THIS IS NOT JUST `apt install fonts-...`
# --------------------------------------------
# The Debian apt font packages carry NO private-use Nerd glyphs (they are the unpatched
# families, or a different patch level than the pin) — the patched fonts ship only from the
# nerd-fonts releases. So the pin IS the release tag (`nerd_fonts_version`), the asset is
# `$FAMILY.tar.xz`, and it lands in the per-user font dir (`~/.local/share/fonts/…`), which
# needs no root and survives a host rebuild via this script.
#
# WHERE THE FONT ACTUALLY MATTERS (read this before concluding the seat leg is useless)
# ------------------------------------------------------------------------------------
# A font changes what a TERMINAL rasterises. On the WSL seat, and on every box reached over
# SSH, the terminal runs on the machine you type from — so the leg that buys glyphs is the
# Windows one, and the Debian leg buys them only where something on that box draws text
# itself. The Debian leg is still worth having (a seat that ever grows a GUI or a `fc-list`
# consumer gets the right family, and `fc-list` is the effectiveness probe that makes this
# script able to fail), but the doc says so out loud instead of letting a seat's green check
# imply that someone can SEE the icons: docs/pi-harness.md §5a.
#
# PROOF MODEL
#           --check compares three things, and each can fail on its own:
#   1. the installed release == the pin          (a stale font after a pin bump)
#   2. a per-file sha256 manifest of the dir     (a swapped/edited/half-extracted install;
#                                                 nerd-fonts ships no per-asset checksum, so
#                                                 the manifest is what makes the tag load-bearing)
#   3. `fc-list` actually lists the family       (the EFFECTIVE half — absent fontconfig is a
#                                                 printed SKIP, never a pass)
#
# MODES
#   --check (default)  report OK / DRIFT / MISSING / STALE / UNVERIFIABLE. MISSING/STALE/
#                      UNVERIFIABLE exit 1; a hash DRIFT is report-only unless --strict —
#                      the contract of sync-extensions.sh / pi-tui-config.sh.
#   --check --strict   exit 1 on a hash drift too (gate use).
#   --push             download the pinned asset (cached under ~/.cache/nerd-fonts), extract
#                      into the font dir, write the manifest, run fc-cache. A current, verified
#                      install downloads NOTHING.
#   --self-test        sandboxed canaries over a fabricated font dir. LIMIT, stated: the
#                      download leg is NOT in the self-test (it would need the network) — the
#                      canaries prove the VERDICT logic, and a live --push is the evidence for
#                      the fetch. That limit is the script's, not the gate's.
#
# Env (sandbox hooks only): REPO, NERD_FONT_DIR (default
# $HOME/.local/share/fonts/<family>-Nerd-Font), NERD_FONT_CACHE (default
# $HOME/.cache/nerd-fonts), NERD_FCCACHE / NERD_FCLIST (command overrides; the self-test
# uses them to breed the SKIP and the ineffective-install states).
#
# Owning rule: docs/pi-harness.md §5a · CONVENTIONS §7 (the release pin lives in versions.yml).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
VERSIONS="$REPO/IaC/ansible/group_vars/all/versions.yml"

pin() {
  local v
  v="$(grep -E "^${1}:" "$VERSIONS" 2>/dev/null | head -1 | sed -E 's/^[^:]+:[[:space:]]*"?([^"#]*)"?.*/\1/' | tr -d '[:space:]')"
  [ -n "$v" ] || { err "pin '$1' missing from IaC/ansible/group_vars/all/versions.yml — add it there, do not hardcode it here"; exit 1; }
  printf '%s' "$v"
}
err()  { printf 'install-nerd-font: %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

REL="$(pin nerd_fonts_version)"
FAMILY="$(pin nerd_fonts_family)"
DIR="${NERD_FONT_DIR:-$HOME/.local/share/fonts/${FAMILY}-Nerd-Font}"
CACHE="${NERD_FONT_CACHE:-$HOME/.cache/nerd-fonts}"
STAMP="$DIR/.installed-from"
MANIFEST="$DIR/.sha256manifest"
FCCACHE="${NERD_FCCACHE:-fc-cache}"
FCLIST="${NERD_FCLIST:-fc-list}"

MODE="check"; STRICT=0
usage() {
  cat <<'EOF'
usage: install-nerd-font.sh [--check [--strict]] | --push | --self-test

  --check          (default) installed release vs the pin + the sha256 manifest + fc-list
  --check --strict exit 1 on a hash drift too (gate use)
  --push           fetch/extract the pinned release asset into the user font dir (idempotent)
  --self-test      sandboxed canaries (fabricated font dir; no network)
EOF
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --strict)    STRICT=1 ;;
    --push)      MODE="push" ;;
    --self-test) MODE="selftest" ;;
    --help|-h)   usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

release_of() { sed -n 's/^release=//p' "$STAMP" 2>/dev/null | head -1; }
manifest_ok() {
  [ -f "$MANIFEST" ] || return 2
  ( cd "$DIR" && sha256sum -c --quiet "$MANIFEST" ) >/dev/null 2>&1
}
write_manifest() {
  ( cd "$DIR" && find . -type f ! -name '.sha256manifest' ! -name '.installed-from' -print0 \
      | LC_ALL=C sort -z | xargs -0 sha256sum ) > "$MANIFEST" || return 1
  printf 'release=%s\nsource=%s\n' "$REL" "https://github.com/ryanoasis/nerd-fonts/releases/download/${REL}/${FAMILY}.tar.xz" > "$STAMP"
}

# The effective half: does the font CONFIGURATION know this family? Absent fontconfig is a
# printed SKIP — a SKIP is not a pass (the same rc contract as install-tmux-conf.sh).
probe_fc() {
  if ! have "$FCLIST"; then info "fc-list: SKIP (no fontconfig here) — the file is placed, its EFFECTIVENESS is unproven"; return 2; fi
  if "$FCLIST" 2>/dev/null | grep -qi -- "$FAMILY"; then info "fc-list      OK — '$FAMILY' is known to fontconfig"; return 0; fi
  err "fc-list: '$FAMILY' is NOT listed — the files are on disk but the font is not usable (ran fc-cache? is the dir a font dir?)"
  return 1
}

do_check() {
  local rc=0 state fc
  info "pin      $FAMILY $REL"
  info "font dir $DIR"
  if [ ! -d "$DIR" ] || [ ! -f "$STAMP" ]; then
    err "MISSING: no installed $FAMILY at $DIR — run 'install-nerd-font.sh --push'"
    return 1
  fi
  if [ ! -f "$MANIFEST" ]; then
    err "UNVERIFIABLE: $DIR has no .sha256manifest — this install was not made by this script (or predates it), so nothing here can say the files are the release's. --push rewrites it from the pinned asset."
    return 1
  fi
  if [ "$(release_of)" != "$REL" ]; then
    err "STALE: installed release '$(release_of)' != pin '$REL' — --push converges it"
    rc=1
  fi
  manifest_ok; state=$?
  case "$state" in
    0) info "manifest   OK — every font file hashes as recorded" ;;
    2) err "UNVERIFIABLE: the manifest is unreadable"; rc=1 ;;
    *) err "DRIFT: a font file in $DIR does not match the manifest (edited, swapped, or half-extracted)"
       if [ "$STRICT" -eq 1 ]; then rc=1; else info "reported, not failed (add --strict for the gate form)"; fi ;;
  esac
  probe_fc; fc=$?
  [ "$fc" -eq 1 ] && rc=1
  [ "$fc" -eq 2 ] && info "NOTE: the effectiveness arm was SKIPPED above — this is not a proven-working font, only a proven-placed one"
  [ "$rc" -eq 0 ] && info "OK: $FAMILY $REL installed and verified"
  return "$rc"
}

do_push() {
  local asset="$FAMILY.tar.xz"
  # separate `local`s: one statement expands ${asset} BEFORE local has assigned it (set -u read
  # that as unbound — live 2026-10-08, the download leg died on its own URL line)
  local url="https://github.com/ryanoasis/nerd-fonts/releases/download/${REL}/${asset}"
  if [ -d "$DIR" ] && [ -f "$STAMP" ] && [ "$(release_of)" = "$REL" ] && manifest_ok; then
    info "current: $FAMILY $REL verified against its manifest — nothing to download"
    probe_fc; return $?
  fi
  require_cmds curl tar xz || return 1
  mkdir -p "$CACHE/$REL"
  if [ ! -f "$CACHE/$REL/$asset" ]; then
    info "fetching $asset ($REL)"
    curl -fsSL --retry 3 -o "$CACHE/$REL/$asset.part" "$url" || { err "download failed: $url"; rm -f "$CACHE/$REL/$asset.part"; return 1; }
    mv -f "$CACHE/$REL/$asset.part" "$CACHE/$REL/$asset"
  else
    info "using the cached $CACHE/$REL/$asset"
  fi
  mkdir -p "$DIR"
  local tmp; tmp="$(mktemp -d)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  tar -xJf "$CACHE/$REL/$asset" -C "$tmp" || { err "could not extract $asset"; return 1; }
  find "$tmp" -type f \( -name '*.ttf' -o -name '*.otf' \) -exec cp -f {} "$DIR/" \; || { err "no fonts in $asset"; return 1; }
  [ -n "$(find "$DIR" -type f \( -name '*.ttf' -o -name '*.otf' \) -print -quit)" ] \
    || { err "nothing landed in $DIR — the asset extracted but carried no .ttf/.otf"; return 1; }
  write_manifest || { err "could not write the manifest"; return 1; }
  if have "$FCCACHE"; then "$FCCACHE" -f >/dev/null 2>&1 && info "fc-cache -f ran" || info "fc-cache ran and failed (fontconfig present)"; else info "fc-cache: SKIP (no fontconfig) — files placed only"; fi
  do_check
}

require_cmds() { local c; for c in "$@"; do have "$c" || { err "missing '$c'"; return 1; }; done; return 0; }

self_test() {
  local tmp fails=0
  tmp="$(mktemp -d 2>/dev/null)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  mk_fake() {   # a verified install of the PINNED release, made the same way --push makes it
    mkdir -p "$1"
    printf 'fake-font-outline' > "$1/${FAMILY}-Regular.ttf"
    printf 'fake-font-bold'    > "$1/${FAMILY}-Bold.ttf"
    ( cd "$1" && find . -type f ! -name '.sha256manifest' ! -name '.installed-from' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum ) > "$1/.sha256manifest"
    printf 'release=%s\nsource=test\n' "$REL" > "$1/.installed-from"
  }
  run_at() { local d="$1"; shift
    NERD_FONT_DIR="$d" NERD_FONT_CACHE="$d/.cache" NERD_FCLIST="$FAKE_FCLIST" \
      bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "$@" >/dev/null 2>&1; }

  # fc-list is faked everywhere: a real fontconfig on the runner has never seen the sandbox
  # dir, so a real fc-list would make the effectiveness arm test nothing (and would make
  # canary 1 depend on the host). "known" = the family is listed; absent = not on PATH.
  printf '#!/bin/sh\necho "%s: style=Regular\n"\nexit 0\n' "$FAMILY" > "$tmp/fc-known"
  chmod +x "$tmp/fc-known"
  FAKE_FCLIST="$tmp/fc-known"

  # 1. rest (verified install of the pinned release) -> GREEN, and --push downloads nothing.
  mk_fake "$tmp/rest"; mkdir -p "$tmp/rest/.cache/$REL"; printf 'CACHED' > "$tmp/rest/.cache/$REL/$FAMILY.tar.xz"
  if run_at "$tmp/rest" --check --strict; then info "rest-state       GREEN"; else err "canary: a verified install failed its own check"; fails=$((fails+1)); fi
  printf 'DO-NOT-RE-DOWNLOAD' > "$tmp/rest/.cache/$REL/$FAMILY.tar.xz"
  run_at "$tmp/rest" --push
  cmp -s "$tmp/rest/.cache/$REL/$FAMILY.tar.xz" <(printf 'DO-NOT-RE-DOWNLOAD') \
    && cmp -s "$tmp/rest/${FAMILY}-Regular.ttf" <(printf 'fake-font-outline') \
    && info "push-idempotent  GREEN (a current install fetched nothing)" \
    || { err "canary: --push re-ran the fetch over a verified install"; fails=$((fails+1)); }

  # 2. a font file edited/swapped under a correct stamp -> the manifest must catch it.
  printf 'trojan' >> "$tmp/rest/${FAMILY}-Bold.ttf"
  if run_at "$tmp/rest" --check --strict; then err "canary passed: a swapped font file stayed green"; fails=$((fails+1)); else info "manifest-canary  caught"; fi

  # 3. stale release (the pin moved, the seat did not) -> RED.
  mk_fake "$tmp/stale"; printf 'release=v0.0.1\nsource=test\n' > "$tmp/stale/.installed-from"
  if run_at "$tmp/stale" --check --strict; then err "canary passed: a stale release stayed green"; fails=$((fails+1)); else info "stale-release    caught"; fi

  # 4. no manifest (a hand-installed font dir) -> UNVERIFIABLE, i.e. never a silent pass.
  mk_fake "$tmp/nomanifest"; rm -f "$tmp/nomanifest/.sha256manifest"
  if run_at "$tmp/nomanifest" --check --strict; then err "canary passed: an unverifiable install stayed green"; fails=$((fails+1)); else info "no-manifest      caught"; fi

  # 5. absent fontconfig -> the effectiveness arm must report a SKIP, not a pass: the file legs
  #    still say OK, so the SCRIPT has to be the one that refuses to claim effectiveness.
  mk_fake "$tmp/nofc"
  out="$(NERD_FONT_DIR="$tmp/nofc" NERD_FCLIST="$tmp/absent-fc-list" bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --check 2>&1)"
  case "$out" in
    *"effectiveness arm was SKIPPED"*) info "skip-honest      GREEN (a SKIP is printed, not passed)" ;;
    *) err "canary: an absent fontconfig read as a proven-working font"; fails=$((fails+1)) ;;
  esac
  FAKE_FCLIST="$tmp/fc-known"

  # 6. missing install -> RED, with the --push remediation.
  if run_at "$tmp/absent" --check --strict; then err "canary passed: a MISSING font dir stayed green"; fails=$((fails+1)); else info "missing-canary   caught"; fi

  # 7. THE PUSH LEG, OFFLINE. A fabricated release archive is pre-seeded in the cache, so --push
  #    runs fetch-skip → extract → manifest → check with no network. Without this arm the entire
  #  --push path (the half that actually installs a font) would be untested by this file.
  # The probe must be REAL: `tar -cJf /dev/null -C /dev/null` fails on a host that has both
  # (writing an archive of /dev/null is not a thing), which made this arm report SKIP on the
  # Win11 seat while the live download leg had worked an hour earlier (2026-10-08).
  if have tar && have xz && tar -cJf "$tmp/probe.tar.xz" -C "$tmp" probe.tar.xz 2>/dev/null || { printf x > "$tmp/p.txt"; tar -cJf "$tmp/probe.tar.xz" -C "$tmp" p.txt >/dev/null 2>&1; }; then
    mkdir -p "$tmp/arch" "$tmp/pushleg/.cache/$REL"
    printf 'archived-font-outline' > "$tmp/arch/${FAMILY}-Regular.ttf"
    tar -cJf "$tmp/pushleg/.cache/$REL/$FAMILY.tar.xz" -C "$tmp/arch" "$FAMILY-Regular.ttf"
    mkdir -p "$tmp/pushleg/fonts"
    printf 'release=v0.0.1\nsource=test\n' > "$tmp/pushleg/fonts/.installed-from"
    if NERD_FONT_DIR="$tmp/pushleg/fonts" NERD_FONT_CACHE="$tmp/pushleg/.cache" NERD_FCLIST="$FAKE_FCLIST" \
         bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --push >/dev/null 2>&1 \
       && NERD_FONT_DIR="$tmp/pushleg/fonts" NERD_FCLIST="$FAKE_FCLIST" \
            bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --check --strict >/dev/null 2>&1; then
      info "push-leg         GREEN (stale install converged from the cache, then verified)"
    else
      err "canary: --push could not converge a stale install from the cache"
      fails=$((fails+1))
    fi
  else
    info "push-leg         SKIP (no tar/xz here) — the install leg is unproven on this host"
  fi

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

case "$MODE" in
  selftest) self_test; exit $? ;;
  check)    do_check; exit $? ;;
  push)     do_push; exit $? ;;
esac
