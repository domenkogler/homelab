#!/usr/bin/env python3
"""image-pin-probe.py — registry probe behind every `*_version` pin in versions.yml.

> **Role:** utility (read-only, network). NOT part of `validate-all.sh` — the repo gate stays
> offline-safe; this script is what a version-refresh session runs to *derive* the values.
> **Linked from:** `scripts/README.md`, `docs/deployment-renovate.md` (manual pin refresh).

Why it exists: Renovate is the intended bump path (`docs/deployment-renovate.md`) but is not yet
pointed at this repo (HD-264 tail — `RENOVATE_REPOSITORIES` is still `domen/test`), so a refresh is
performed by hand. "By hand" without a probe is how a doc/comment claims a tag that the registry
does not have — the `db_backup_version: 4.1.100` case found on 2026-10-08: the pin is a 404 on the
registry, Docker Hub carries exactly one tag (`latest`), and every gate stayed green because no
gate looks the tag up. This script makes the claim "registry-verified" reproducible.

Rules it encodes (owner rule 2026-10-08, mirrors `renovate.json` `stabilityDays: 3`):
  * newest STABLE release whose PUBLICATION date is at least `--days` (default 3) old;
  * prerelease/flavoured tags (alpha/beta/rc/nightly/dev/unstable/enterprise/fips/…) are not
    "stable"; for official images the *registry push* date is a rebuild date, so the upstream
    release feed (GitHub releases) supplies the date instead;
  * a pin whose value carries a `sha256` digest is never suggested for change (CONVENTIONS §7 —
    the digest is the load-bearing pin and a tag bump there needs the re-bench that owns it).

Usage:
  scripts/image-pin-probe.py                 # table: current / newest-eligible / newest-any
  scripts/image-pin-probe.py --verify        # + does the CURRENT pin exist in the registry?
  scripts/image-pin-probe.py --days 7 --json
"""
from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
import os
import re
import sys
import urllib.request
from urllib.parse import urljoin

DEFAULT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir,
                            'IaC', 'ansible', 'group_vars', 'all', 'versions.yml')
CACHE = os.path.join(os.environ.get('XDG_CACHE_HOME', os.path.expanduser('~/.cache')), 'homelab-pin-probe')
UA = {'User-Agent': 'homelab-image-pin-probe/1.0'}
SEM = r'(?P<v>\d+\.\d+\.\d+)'
LS = r'(?P<v>\d+\.\d+\.\d+(?:\.\d+)?(?:-ls\d+)?)'
PRERE = re.compile(r'alpha|beta|rc|preview|nightly|snapshot|canary|unstable|debug|enterprise|fips', re.I)

# var -> (source, tag pattern, [, gh=upstream GitHub slug] [, pages] [, line] [, strip_v])
# `src` kinds: hub | ghcr | quay | codeberg | gh | npm | npmall | pypi | node | apt | tailscale
# Deliberately absent (never suggest a change): the digest-pinned `*_image` pins, the sha256
# artifact digests, and `spark_sglang_image` (empty pin IS the gate, HD-469).
SOURCES = {
    'traefik_version': dict(src=('hub', 'library/traefik'), pat=r'(?P<tag>v' + SEM + ')'),
    'certs_dumper_version': dict(src=('hub', 'ldez/traefik-certs-dumper'), pat=r'(?P<tag>v' + SEM + ')'),
    'crowdsec_bouncer_plugin_version': dict(src=('gh', 'maxlerebourg/crowdsec-bouncer-traefik-plugin'), pat=r'(?P<tag>v' + SEM + ')'),
    'crowdsec_version': dict(src=('hub', 'crowdsecurity/crowdsec'), pat=r'(?P<tag>v' + SEM + ')'),
    'crowdsec_web_ui_version': dict(src=('ghcr', 'theduffman85/crowdsec-web-ui'), gh='theduffman85/crowdsec-web-ui', pat=r'(?P<v>\d{4}\.\d+\.\d+)'),
    'authentik_version': dict(src=('ghcr', 'goauthentik/server'), gh='goauthentik/authentik', pat=r'(?P<v>\d+\.\d+\.\d+)'),
    'headscale_version': dict(src=('hub', 'headscale/headscale'), pat=SEM),
    'headplane_version': dict(src=('ghcr', 'tale/headplane'), gh='tale/headplane', pat=SEM),
    'keepalived_version': dict(src=('hub', 'osixia/keepalived'), pat=SEM),
    'tuwunel_version': dict(src=('hub', 'jevolk/tuwunel'), pat=r'(?P<tag>v' + SEM + ')'),
    'bazarr_version': dict(src=('hub', 'linuxserver/bazarr'), pat=r'(?P<v>\d+\.\d+\.\d+(?:-ls\d+)?)'),
    'jellyfin_version': dict(src=('hub', 'jellyfin/jellyfin'), pat=SEM, pages=8),
    'lidarr_version': dict(src=('hub', 'linuxserver/lidarr'), pat=LS),
    'prowlarr_version': dict(src=('hub', 'linuxserver/prowlarr'), pat=LS),
    'radarr_version': dict(src=('hub', 'linuxserver/radarr'), pat=r'(?P<v>\d+\.\d+\.\d+(?:-ls\d+)?)'),
    'sabnzbd_version': dict(src=('hub', 'linuxserver/sabnzbd'), pat=r'(?P<v>\d+\.\d+\.\d+(?:-ls\d+)?)'),
    'sonarr_version': dict(src=('hub', 'linuxserver/sonarr'), pat=LS),
    'qbittorrent_version': dict(src=('hub', 'linuxserver/qbittorrent'), pat=r'(?P<v>\d+\.\d+\.\d+(?:-ls\d+)?)'),
    'seerr_version': dict(src=('hub', 'seerr/seerr'), pat=r'(?P<tag>v' + SEM + ')'),
    'seerrng_version': dict(src=('hub', 'snapetech/seerrng'), pat=r'(?P<tag>v' + SEM + ')'),
    'recyclarr_version': dict(src=('ghcr', 'recyclarr/recyclarr'), gh='recyclarr/recyclarr', pat=SEM),
    'flaresolverr_version': dict(src=('ghcr', 'flaresolverr/flaresolverr'), gh='flaresolverr/flaresolverr', pat=r'(?P<tag>v' + SEM + ')'),
    'navidrome_version': dict(src=('hub', 'deluan/navidrome'), pat=SEM),
    'aurral_version': dict(src=('ghcr', 'lklynet/aurral'), gh='lklynet/aurral', pat=SEM),
    'slskd_version': dict(src=('hub', 'slskd/slskd'), pat=SEM),
    'tube_archivist_version': dict(src=('hub', 'bbilly1/tubearchivist'), pat=r'(?P<tag>v' + SEM + ')'),
    'tube_archivist_es_version': dict(src=('hub', 'bbilly1/tubearchivist-es'), pat=SEM, line=r'^8\.'),
    'tube_archivist_redis_version': dict(src=('hub', 'library/redis'), pat=r'(?P<v>\d+\.\d+\.\d+)-alpine'),
    'lidarr_ydl_version': dict(src=('hub', 'angrido/lidarr-downloader'), pat=SEM, pages=1),
    'profilarr_version': dict(src=('ghcr', 'dictionarry-hub/profilarr'), gh='dictionarry-hub/profilarr', pat=SEM),
    'sunshine_version': dict(src=('hub', 'lizardbyte/sunshine'), pat=r'(?P<v>v\d{4}\.\d+\.\d+)-ubuntu-24\.04'),
    'technitium_version': dict(src=('hub', 'technitium/dns-server'), pat=SEM),
    'pihole_version': dict(src=('hub', 'pihole/pihole'), pat=r'(?P<v>\d{4}\.\d+\.\d+)'),
    'dozzle_version': dict(src=('hub', 'amir20/dozzle'), pat=r'(?P<tag>v' + SEM + ')'),
    'homepage_version': dict(src=('ghcr', 'gethomepage/homepage'), gh='gethomepage/homepage', pat=r'(?P<tag>v' + SEM + ')'),
    'metabase_version': dict(src=('hub', 'metabase/metabase'), pat=r'(?P<v>v?\d+\.\d+\.\d+(?:\.\d+)?)'),
    'signal_cli_rest_api_version': dict(src=('hub', 'bbernhard/signal-cli-rest-api'), pat=r'(?P<v>\d+\.\d+)'),
    'secured_signal_api_version': dict(src=('ghcr', 'codeshelldev/secured-signal-api'), gh='codeshelldev/secured-signal-api', pat=r'(?P<tag>v' + SEM + ')'),
    'renovate_version': dict(src=('ghcr', 'renovatebot/renovate'), gh='renovatebot/renovate', pat=SEM),
    'element_web_version': dict(src=('ghcr', 'element-hq/element-web'), gh='element-hq/element-web', pat=r'(?P<tag>v' + SEM + ')'),
    'actual_budget_version': dict(src=('hub', 'actualbudget/actual-server'), pat=SEM),
    'gluetun_version': dict(src=('hub', 'qmcgaw/gluetun'), pat=r'(?P<tag>v' + SEM + ')'),
    'ollama_version': dict(src=('hub', 'ollama/ollama'), pat=r'(?P<v>\d+\.\d+\.\d+)-rocm'),
    'docling_version': dict(src=('quay', 'docling-project/docling-serve-cpu'), pat=r'(?P<tag>v' + SEM + ')'),
    'litellm_version': dict(src=('ghcr', 'berriai/litellm'), gh='BerriAI/litellm', pat=r'(?P<v>v?\d+\.\d+\.\d+)(?:-stable)?'),
    'openwebui_version': dict(src=('hub', 'openwebui/open-webui'), pat=SEM),
    'openclaw_version': dict(src=('ghcr', 'openclaw/openclaw'), gh='openclaw/openclaw', pat=r'(?P<v>\d{4}\.\d+\.\d+)'),
    'dsh_version': dict(src=('hub', 'runzhliu/deepseek-harness'), pat=r'(?P<v>\d+\.\d+\.\d+)(?:-rc\.\d+)?', pages=2),
    'pairdrop_version': dict(src=('hub', 'linuxserver/pairdrop'), pat=r'(?P<v>\d+\.\d+\.\d+(?:-ls\d+)?)'),
    'stirling_pdf_version': dict(src=('hub', 'frooodle/s-pdf'), pat=r'(?P<v>\d+\.\d+\.\d+)-fat'),
    'db_backup_version': dict(src=('hub', 'tiredofit/db-backup'), pat=SEM, pages=2),
    'forgejo_version': dict(src=('codeberg', 'forgejo/forgejo'), pat=r'v?(?P<v>\d+\.\d+\.\d+)', strip_v=True),
    'grafana_version': dict(src=('hub', 'grafana/grafana'), pat=SEM, pages=3),
    'kopia_version': dict(src=('hub', 'kopia/kopia'), pat=r'(?P<v>0\.\d+\.\d+)'),
    'n8n_version': dict(src=('hub', 'n8nio/n8n'), pat=SEM),
    'immich_version': dict(src=('ghcr', 'immich-app/immich-server'), gh='immich-app/immich', pat=r'(?P<tag>v' + SEM + ')'),
    'opencloud_version': dict(src=('hub', 'opencloudeu/opencloud-rolling'), pat=SEM),
    'zipline_version': dict(src=('ghcr', 'diced/zipline'), gh='diced/zipline', pat=SEM),
    'zipline_db_version': dict(src=('hub', 'library/postgres'), gh='postgresql/postgresql', pat=r'(?P<v>1[4-9]\.\d+)-alpine'),
    'litellm_db_version': dict(src=('hub', 'library/postgres'), gh='postgresql/postgresql', pat=r'(?P<v>1[4-9]\.\d+)-alpine'),
    'onlyoffice_pg_version': dict(src=('hub', 'library/postgres'), gh='postgresql/postgresql', pat=r'(?P<v>1[4-9]\.\d+)-alpine'),
    'authentik_db_version': dict(src=('hub', 'library/postgres'), gh='postgresql/postgresql', pat=r'(?P<v>1[4-9]\.\d+)-alpine'),
    'authentik_redis_version': dict(src=('hub', 'library/redis'), gh='redis/redis', pat=r'(?P<v>\d+\.\d+\.\d+)-alpine'),
    'immich_valkey_version': dict(src=('hub', 'valkey/valkey'), pat=r'(?P<v>\d+\.\d+\.\d+)'),
    'profilarr_parser_version': dict(src=('ghcr', 'dictionarry-hub/profilarr-parser'), gh='dictionarry-hub/profilarr', pat=SEM),
    'forgejo_db_version': dict(src=('hub', 'library/postgres'), gh='postgresql/postgresql', pat=r'(?P<v>1[4-9]\.\d+)-alpine'),
    'onlyoffice_version': dict(src=('hub', 'onlyoffice/documentserver'), pat=r'(?P<v>\d+\.\d+\.\d+(?:\.\d+)?)'),
    'onlyoffice_redis_version': dict(src=('hub', 'library/redis'), gh='redis/redis', pat=r'(?P<v>\d+\.\d+\.\d+)-alpine'),
    'onlyoffice_rabbitmq_version': dict(src=('hub', 'library/rabbitmq'), gh='rabbitmq/rabbitmq-server', pat=r'(?P<v>\d+\.\d+\.\d+)-alpine', strip_v=False),
    'victoria_metrics_version': dict(src=('hub', 'victoriametrics/victoria-metrics'), pat=r'(?P<tag>v' + SEM + ')'),
    'victoria_logs_version': dict(src=('hub', 'victoriametrics/victoria-logs'), pat=r'(?P<tag>v' + SEM + ')'),
    'blackbox_exporter_version': dict(src=('hub', 'prom/blackbox-exporter'), pat=r'(?P<tag>v' + SEM + ')'),
    'mcp_victoriametrics_version': dict(src=('ghcr', 'victoriametrics-community/mcp-victoriametrics'), gh='victoriametrics-community/mcp-victoriametrics', pat=r'(?P<tag>v' + SEM + ')'),
    'mcp_victorialogs_version': dict(src=('ghcr', 'victoriametrics-community/mcp-victorialogs'), gh='victoriametrics-community/mcp-victorialogs', pat=r'(?P<tag>v' + SEM + ')'),
    'tailscale_version': dict(src=('hub', 'tailscale/tailscale'), pat=r'(?P<tag>v' + SEM + ')'),
    'tailscale_host_version': dict(src=('gh', 'tailscale/tailscale'), pat=r'v(?P<v>\d+\.\d+\.\d+)', strip_v=True),
    'homelable_version': dict(src=('ghcr', 'pouzor/homelable-backend'), gh='pouzor/homelable', pat=SEM),
    'rustdesk_server_version': dict(src=('hub', 'rustdesk/rustdesk-server-s6'), pat=SEM),
    'routeros_api_version': dict(src=('pypi', 'routeros-api'), pat=SEM),
    'qdrant_version': dict(src=('hub', 'qdrant/qdrant'), pat=r'(?P<tag>v' + SEM + ')'),
    'home_assistant_version': dict(src=('ghcr', 'home-assistant/home-assistant'), gh='home-assistant/core', pat=r'(?P<v>\d{4}\.\d+\.\d+)'),
    'alloy_version': dict(src=('apt',), pat=r'(?P<v>\d+\.\d+\.\d+)(?:-\d+)?'),
    'pi_dev_node_version': dict(src=('node',), major=24, pat=r'(?P<v>24\.\d+\.\d+)'),
    'pi_host_node_version': dict(src=('node',), major=22, pat=r'(?P<v>22\.\d+\.\d+)'),
    'pi_dev_npm_version': dict(src=('npmall', '@earendil-works/pi-coding-agent'), pat=r'(?P<v>\d+\.\d+\.\d+)'),
    'pi_host_npm_version': dict(src=('npmall', '@earendil-works/pi-coding-agent'), pat=r'(?P<v>\d+\.\d+\.\d+)'),
    'pi_web_access_version': dict(src=('npmall', 'pi-web-access'), pat=r'(?P<v>\d+\.\d+\.\d+)'),
    'pi_web_ui_version': dict(src=('npmall', 'pi-web-ui'), pat=r'(?P<v>\d+\.\d+\.\d+)'),
    'pi_host_web_npm_version': dict(src=('npm', '@ygncode/pi-web', 'beta'), pat=r'(?P<v>\d+\.\d+\.\d+)(?:-beta\.\d+)?'),
}

# ---------------------------------------------------------------- HTTP + cache
def _get(url, headers=None, binary=False):
    os.makedirs(CACHE, exist_ok=True)
    cp = os.path.join(CACHE, hashlib.sha1(url.encode()).hexdigest())
    if os.path.exists(cp) and dt.datetime.now().timestamp() - os.path.getmtime(cp) < 6 * 3600:
        raw = open(cp, 'rb').read()
    else:
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={**UA, **(headers or {})}), timeout=45) as r:
                raw = r.read()
        except Exception as e:                                    # noqa: BLE001 - a probe says what it saw
            return {'err': f'{type(e).__name__}:{getattr(e, "code", "")}'}
        open(cp, 'wb').write(raw)
        import time
        time.sleep(0.1)
    return {'body': raw if binary else raw.decode('utf-8', 'replace')}


def _jget(url, headers=None):
    r = _get(url, headers)
    if 'err' in r:
        return {'err': r['err']}
    try:
        return json.loads(r['body'])
    except Exception as e:                                        # noqa: BLE001
        return {'err': f'json:{e}'}


def _iso(s):
    if not s:
        return None
    try:
        d = dt.datetime.fromisoformat(str(s).replace('Z', '+00:00'))
        return d.replace(tzinfo=dt.timezone.utc) if d.tzinfo is None else d
    except Exception:                                             # noqa: BLE001
        return None


def _vkey(s):
    n = [int(x) for x in re.findall(r'\d+', s or '')]
    return tuple((n + [0] * 8)[:8])


# ---------------------------------------------------------------- registries
def hub_tags(repo, pages=3):
    out, err = [], None
    for p in range(1, pages + 1):
        d = _jget(f'https://hub.docker.com/v2/repositories/{repo}/tags?page_size=100&ordering=last_updated&page={p}')
        if 'err' in d:
            return out, d['err']
        out += [(r['name'], _iso(r.get('tag_last_pushed') or r.get('last_updated'))) for r in d.get('results', [])]
        if not d.get('next'):
            break
    return out, err


def _ghcr_token(repo):
    d = _jget(f'https://ghcr.io/token?scope=repository:{repo}:pull&service=ghcr.io')
    return d.get('token')


def ghcr_tags(repo):
    tok = _ghcr_token(repo)
    if not tok:
        return [], 'no ghcr token (repo likely absent)'
    out, url, guard = [], f'https://ghcr.io/v2/{repo}/tags/list?n=1000', 0
    while url and guard < 30:
        guard += 1
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={**UA, 'Authorization': 'Bearer ' + tok}), timeout=45) as r:
                body, link = r.read(), r.headers.get('Link')
        except Exception as e:                                    # noqa: BLE001
            return out, f'{type(e).__name__}:{getattr(e, "code", "")}'
        d = json.loads(body)
        out += [(t, None) for t in d.get('tags', [])]
        m = re.search(r'<([^>]+)>;\s*rel="?next"?', link or '')
        url = urljoin('https://ghcr.io/', m.group(1)) if m else None
    return out, None


def ghcr_has(repo, tag):
    acc = 'application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'
    try:
        with urllib.request.urlopen(urllib.request.Request(f'https://ghcr.io/v2/{repo}/manifests/{tag}',
              headers={**UA, 'Authorization': 'Bearer ' + (_ghcr_token(repo) or ''), 'Accept': acc}, method='HEAD'), timeout=45) as r:
            return r.status == 200
    except Exception:                                             # noqa: BLE001
        return False


def ghcr_tag_date(repo, tag):
    """Publish date of one ghcr tag: index → manifest → config blob (Range-read for "created")."""
    tok = _ghcr_token(repo)
    acc = 'application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'
    man = _jget(f'https://ghcr.io/v2/{repo}/manifests/{tag}', {'Authorization': 'Bearer ' + (tok or ''), 'Accept': acc})
    if 'err' in man:
        return None
    if 'manifests' in man and man['manifests']:
        child = next((m for m in man['manifests'] if m.get('platform', {}).get('architecture') == 'amd64'), man['manifests'][0])
        if 'org.opencontainers.image.created' in child.get('annotations', {}):
            return _iso(child['annotations']['org.opencontainers.image.created'])
        man = _jget(f'https://ghcr.io/v2/{repo}/manifests/{child["digest"]}', {'Authorization': 'Bearer ' + (tok or ''), 'Accept': acc})
    for a in (man.get('annotations'), man.get('metadata', {}).get('annotations')):
        if a and 'org.opencontainers.image.created' in a:
            return _iso(a['org.opencontainers.image.created'])
    cfg = man.get('config', {}).get('digest')
    if not cfg:
        return None
    r = _get(f'https://ghcr.io/v2/{repo}/blobs/{cfg}', {'Authorization': 'Bearer ' + (tok or ''), 'Range': 'bytes=0-40000'})
    m = re.search(r'"created"\s*:\s*"([^"]+)"', r.get('body', '')[:45000]) if 'body' in r else None
    return _iso(m.group(1)) if m else None


def quay_tags(repo):
    out, url = [], f'https://quay.io/api/v1/repository/{repo}/tag/?limit=250&only_active=true'
    for _ in range(12):
        d = _jget(url)
        if 'err' in d:
            return out, d['err']
        out += [(t['name'], dt.datetime.fromtimestamp(t['start_ts'], dt.timezone.utc) if t.get('start_ts') is not None
                 else _iso(t.get('last_modified'))) for t in (d.get('labels') or d.get('tags') or [])]
        nxt = d.get('next_page') or (str(int(d.get('page', 1)) + 1) if d.get('has_additional') else None)
        if not nxt:
            break
        url = f'https://quay.io/api/v1/repository/{repo}/tag/?limit=250&only_active=true&page={nxt}'
    return out, None


_REL = {}


def gh_releases(slug):
    if slug in _REL:
        return _REL[slug]
    out, err = {}, None
    for p in (1, 2):
        d = _jget(f'https://api.github.com/repos/{slug}/releases?per_page=100&page={p}')
        if isinstance(d, dict) and 'err' in d:
            err = d['err']
            break
        for r in (d if isinstance(d, list) else []):
            if not r.get('draft') and not r.get('prerelease') and r.get('tag_name'):
                out.setdefault(r['tag_name'], _iso(r.get('published_at')))
        if isinstance(d, list) and len(d) < 100:
            break
    _REL[slug] = (out, err)
    return _REL[slug]


def codeberg_releases(slug, n=30):
    d = _jget(f'https://codeberg.org/api/v1/repos/{slug}/releases?limit={n}')
    if isinstance(d, dict) and 'err' in d:
        return {}, d['err']
    return {r['tag_name']: _iso(r.get('published_at')) for r in d if not r.get('draft') and not r.get('prerelease')}, None


def npm_versions(pkg):
    d = _jget('https://registry.npmjs.org/' + pkg.replace('/', '%2F'))
    if 'err' in d:
        return {}, {}, d['err']
    return d.get('dist-tags', {}), {k: _iso(v) for k, v in d.get('time', {}).items() if k not in ('created', 'modified')}, None


def node_versions(major):
    d = _jget('https://nodejs.org/dist/index.json')
    if not isinstance(d, list):
        return {}, d.get('err', 'nodejs.org index err')
    return {r['version'].lstrip('v'): _iso(r.get('date')) for r in d if r['version'].lstrip('v').startswith(f'{major}.')}, None


def apt_alloy_versions():
    d = _get('https://apt.grafana.com/dists/stable/main/binary-amd64/Packages.gz', binary=True)
    if 'err' in d:
        return {}, d['err']
    txt = gzip.decompress(d['body']).decode('utf8', 'replace')
    vers = [re.search(r'^Version: (\S+)', b, re.M).group(1) for b in txt.split('\n\n') if b.startswith('Package: alloy')]
    rel, e = gh_releases('grafana/alloy')
    dates = {k.lstrip('v') + '-1': v for k, v in rel.items()}
    return {v: dates.get(v) or _iso(v) for v in vers}, e


def tailscale_versions():
    d = _get('https://pkgs.tailscale.com/stable/')
    if 'err' in d:
        return {}, d['err']
    vers = sorted({m.group(1) for m in re.finditer(r'tailscale_(\d+\.\d+\.\d+)_amd64\.deb', d.get('body', ''))})
    rel, e = gh_releases('tailscale/tailscale')
    return {v: rel.get('v' + v) for v in vers}, e


# ---------------------------------------------------------------- existence
def exists(ref):
    """Does this exact reference exist in its registry right now? (True/False/None=undecidable)"""
    reg, _, rest = ref.partition('/')
    if reg in ('npm', 'pypi', 'apt', 'node'):
        return None, 'not a registry reference'
    repo, _, tag = rest.rpartition(':')
    if '@' in tag:
        tag = tag.split('@')[0]
    if not repo:
        repo, tag = rest, 'latest'
    if reg == 'docker.io' or reg == 'registry-1.docker.io':
        if '.' in repo.split('/')[0]:
            repo = repo.split('/', 1)[1]
        d = _jget(f'https://hub.docker.com/v2/repositories/{repo}/tags/{tag}')
        return (True, 'hub') if d.get('name') else (False, 'hub 404')
    if reg == 'ghcr.io':
        return ghcr_has(repo, tag), 'ghcr manifest'
    if reg == 'quay.io':
        tags, err = quay_tags(repo)
        return any(t == tag for t, _ in tags), 'quay list ' + (err or 'ok')
    return None, 'unhandled ' + reg


# ---------------------------------------------------------------- selection
def pick(cfg, cutoff):
    src, pat = cfg['src'], cfg['pat']
    dates, err = {}, None
    if src[0] == 'hub':
        dates = dict(hub_tags(src[1], cfg.get('pages', 3))[0])
    elif src[0] == 'ghcr':
        dates = dict(ghcr_tags(src[1])[0])
    elif src[0] == 'quay':
        dates, err = quay_tags(src[1])
    elif src[0] == 'codeberg':
        dates, err = codeberg_releases(src[1])
    elif src[0] == 'gh':
        dates, err = gh_releases(src[1])
    elif src[0] == 'npm':
        dist, times, err = npm_versions(src[1])
        v = dist.get(src[2] if len(src) > 2 else 'latest')
        dates = {v: times.get(v)} if v else {}
    elif src[0] == 'npmall':
        _, dates, err = npm_versions(src[1])
    elif src[0] == 'pypi':
        d = _jget(f'https://pypi.org/pypi/{src[1]}/json')
        dates = {v: max([_iso(r.get('upload_time')) for r in rel if r.get('upload_time')] or [None])
                 for v, rel in (d.get('releases') or {}).items()}
    elif src[0] == 'node':
        dates, err = node_versions(cfg['major'])
    elif src[0] == 'apt':
        dates, err = apt_alloy_versions()
    elif src[0] == 'tailscale':
        dates, err = tailscale_versions()
    else:
        return None, None, 'unknown source ' + src[0]
    if src[0] == 'ghcr' and cfg.get('gh'):
        # A registry tag list can be 30k entries deep; the release feed is the candidate list.
        rel, e2 = gh_releases(cfg['gh'])
        if e2:
            err = (err or '') + f' {cfg["gh"]} releases: {e2}'
        rel = {k.split('/')[-1]: v for k, v in rel.items()}
        for t, d in rel.items():
            if t in dates:
                dates[t] = dates[t] or d
            elif t[1:] in dates:
                dates[t[1:]] = d
            elif ghcr_has(src[1], t):
                dates[t] = d
            elif ghcr_has(src[1], 'v' + t):
                dates['v' + t] = d
    if cfg.get('gh') and src[0] in ('hub', 'quay'):   # official images: push date = rebuild date
        rel, _e = gh_releases(cfg['gh'])
        rel = {k.split('/')[-1]: v for k, v in rel.items()}
        for t in list(dates):
            core = re.match(pat if pat.endswith('$') else pat + '$', t)
            if core and rel.get(core.group('v')) is not None:
                dates[t] = rel[core.group('v')]
    if not isinstance(dates, dict):
        dates = dict(dates)
    cand = []
    for t in dates:
        m = re.match(pat if pat.rstrip().endswith('$') else pat + r'$', t)
        if not m:
            continue
        core = m.groupdict().get('v') or m.groupdict().get('tag') or m.group(1)
        if PRERE.search(core) or re.search(r'\d[ab]\d+$', core):
            continue
        if cfg.get('line') and not re.match(cfg['line'], t):
            continue
        d0 = dates.get(t)
        if cfg.get('strip_v') and t.startswith('v'):
            t = t[1:]
        cand.append((t, core, d0))
    if src[0] == 'ghcr':
        cand = [(t, c, d or ghcr_tag_date(src[1], t)) for t, c, d in cand[:8]] + cand[8:]
    cand.sort(key=lambda x: (_vkey(x[1]), x[2] or dt.datetime.min.replace(tzinfo=dt.timezone.utc)), reverse=True)
    elig = [c for c in cand if c[2] and c[2] <= cutoff]
    return (elig[0] if elig else None), (cand[0] if cand else None), err


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--file', default=os.path.normpath(DEFAULT_ROOT))
    ap.add_argument('--days', type=int, default=3, help='stability hold, mirrors renovate.json stabilityDays')
    ap.add_argument('--verify', action='store_true', help='also probe whether the CURRENT pin exists upstream')
    ap.add_argument('--json', action='store_true')
    args = ap.parse_args()

    pins = {}
    for line in open(args.file, encoding='utf-8'):
        m = re.match(r'^([A-Za-z0-9_]+):\s*(.*?)\s*(?:#.*)?$', line)
        if m and (m.group(1).endswith('_version') or m.group(1).endswith('_image')):
            pins[m.group(1)] = m.group(2).strip('"').strip("'")

    now = dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(days=args.days)
    rows = {}
    for var, cur in sorted(pins.items()):
        cfg = SOURCES.get(var)
        if cfg is None:
            note = ('intentionally unset — an empty pin IS the gate (HD-469)' if cur == ''
                    else 'digest-pinned by design (CONVENTIONS §7)' if 'sha256' in cur or 'sha256' in var
                    else 'NOT IN THE SOURCE TABLE — add it to SOURCES if it is a registry pin')
            rows[var] = dict(cur=cur, skipped=note)
            continue
        elig, best, err = pick(cfg, cutoff)
        cur_ok = None
        if args.verify and cur and 'sha256' not in cur:
            ref = '/'.join([x for x in [cfg.get('ref', ''), cfg['src'][1] if cfg['src'][0] in ('hub', 'ghcr', 'quay') else ''] if x])
            reg = {'hub': 'docker.io', 'ghcr': 'ghcr.io', 'quay': 'quay.io'}.get(cfg['src'][0], '')
            cur_ok = exists(f'{reg}/{cfg["src"][1]}:{cur}') if reg else (None, 'feed check')
        rows[var] = dict(cur=cur, elig=elig[0] if elig else None, elig_date=str(elig[2].date()) if elig and elig[2] else None,
                         best=best[0] if best else None, best_date=str(best[2].date()) if best and best[2] else None,
                         err=err, exists=(list(cur_ok) if cur_ok else None))
    if args.json:
        print(json.dumps(rows, indent=1))
        return 0
    print(f'# cutoff: released on/before {cutoff.isoformat(timespec="minutes")} (hold {args.days}d)')
    print(f'{"VAR":34s} {"CURRENT":26s} {"NEWEST STABLE (>= hold)":30s} {"NEWEST ANY":22s} {"PIN EXISTS"}')
    for var, r in rows.items():
        if 'skipped' in r:
            print(f'{var:34s} {str(r["cur"])[:26]:26s} — {r["skipped"]}')
            continue
        e = f'{r["elig"]} @{r["elig_date"]}' if r['elig'] else '-'
        b = f'{r["best"]} @{r["best_date"]}' if r['best'] else '-'
        x = '' if not args.verify else ('yes' if r.get('exists') and r['exists'][0]
                                        else ('feed-only' if r.get('exists') is None or r['exists'][0] is None else 'NO — phantom pin'))
        print(f'{var:34s} {str(r["cur"])[:26]:26s} {e:30s} {b[:22]:22s} {x}{("  " + r["err"]) if r.get("err") else ""}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
