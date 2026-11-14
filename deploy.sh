#!/usr/bin/env bash
# Personal site deploy (runs ON THE SERVER): builds /opt/personal-site/site and copies dist/ to the live
# folder /opt/rossettilab/sites/eddy (edoardorossetti.eu). Caddy serves files directly: no restart, no reload.
#
#   deploy.sh status            build, show what differs from live + what changed ON the server since last deploy
#   deploy.sh apply             build → checks → show changes → confirm → backup → copy → verify live
#   deploy.sh apply --yes       same, no confirmation prompt
#   deploy.sh rollback          restore the latest backup (never ledger.json / corrections.json)
#
# Never touched: ledger.json + corrections.json (n8n writes them live), og.png (legacy, unused), *.bak*.
# No Caddy, n8n or docker changes.
set -euo pipefail

SRC=/opt/personal-site/site
LIVE=/opt/rossettilab/sites/eddy
BACKUPS=/opt/personal-site-backups
MANIFEST=$BACKUPS/live.md5          # checksums of managed live files right after the last deploy
PY=/opt/venv/bin/python             # has Pillow
URL=https://edoardorossetti.eu/
TS=$(date +%Y%m%d-%H%M%S)

die(){ echo "✗ $*" >&2; exit 1; }
ok(){ echo "✓ $*"; }
usage(){ sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

# Excluded = never copied AND never deleted on the live side.
F=(--exclude='/ledger.json' --exclude='/corrections.json' --exclude='/og.png' --exclude='*.bak*' --exclude='.DS_Store')

build(){
  rm -rf "$SRC/dist" "$SRC/out"
  local live_lastmod; live_lastmod=$(grep -o '<lastmod>[^<]*' "$LIVE/sitemap.xml" 2>/dev/null | cut -c10- || true)
  (cd "$SRC" && SITEMAP_LASTMOD="$live_lastmod" "$PY" -I build.py >/dev/null) || die "build.py failed: nothing deployed"
  rm -rf "$SRC/__pycache__"
  # sitemap date moves only when the page itself changes
  if ! cmp -s "$SRC/dist/index.html" "$LIVE/index.html"; then
    sed -i "s|<lastmod>[^<]*</lastmod>|<lastmod>$(date +%F)</lastmod>|" "$SRC/dist/sitemap.xml"
  fi
  local h="$SRC/dist/index.html"
  grep -q 'stats.rossettilab.store/insights.js' "$h" || die "Umami snippet missing from index.html: nothing deployed"
  grep -q 'window.ER_CONFIG' "$h" || die "ER_CONFIG (fix API) missing from index.html: nothing deployed"
  ! grep -q '{{' "$h" || die "unreplaced {{placeholder}} in index.html: nothing deployed"
  [ "$(stat -c %s "$h")" -gt 100000 ] || die "index.html suspiciously small: nothing deployed"
  ok "built + checks ok (Umami, fix API, placeholders)"
}

changes(){ rsync -rlc --delete --dry-run --itemize-changes "${F[@]}" "$SRC/dist/" "$LIVE/" \
             | grep -E '^(\*deleting|[<>c]f|cd\+)' || true; }

live_sums(){ (cd "$LIVE" && find . -type f ! -name ledger.json ! -name corrections.json ! -name og.png \
               ! -name '*.bak*' -print0 | sort -z | xargs -0 md5sum); }

server_drift(){
  [ -f "$MANIFEST" ] || { echo "(no manifest yet: first deploy)"; return 0; }
  diff <(cat "$MANIFEST") <(live_sums) | grep '^>' | awk '{print "  " $3}' || true
}

verify_live(){
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' "$URL")
  [ "$code" = 200 ] || die "$URL returned $code: run deploy.sh rollback"
  curl -s "$URL" | cmp -s - "$LIVE/index.html" || echo "! served page differs from file (cache?): check by hand"
  ok "$URL 200, $(grep -o 'v1\.[0-9.]*' "$LIVE/index.html" | tail -1) live"
}

cmd=${1:-status}; yes=${2:-}
[ -d "$SRC" ] || die "$SRC missing"
mkdir -p "$BACKUPS"; chmod 700 "$BACKUPS"

case $cmd in
  status)
    build
    echo "== Would change on live (desktop → server):"; C=$(changes); echo "${C:-  nothing}"
    echo "== Changed on the server since last deploy (would be OVERWRITTEN):"
    D=$(server_drift); echo "${D:-  nothing}" ;;

  apply)
    build
    C=$(changes); [ -n "$C" ] || { ok "live already matches, nothing to do"; exit 0; }
    D=$(server_drift)
    if [ -n "$D" ] && [ "$D" != "(no manifest yet: first deploy)" ]; then
      echo "These live files changed on the server since your last deploy:"; echo "$D"
      die "someone edited live directly: fold the change into site/ first (download.sh), then upload again"
    fi
    echo "== Changes:"; echo "$C"
    if [ "$yes" != "--yes" ]; then read -rp "Apply to live? [y/N] " a; [ "$a" = y ] || die "aborted"; fi
    tar -C "$(dirname "$LIVE")" -czf "$BACKUPS/eddy-$TS.tar.gz" "$(basename "$LIVE")"
    ok "backup $BACKUPS/eddy-$TS.tar.gz"
    rsync -rlc --inplace --delete --chmod=D755,F644 "${F[@]}" "$SRC/dist/" "$LIVE/"
    live_sums > "$MANIFEST"
    verify_live ;;

  rollback)
    B=$(ls -1t "$BACKUPS"/eddy-*.tar.gz 2>/dev/null | head -1); [ -n "$B" ] || die "no backup"
    [ "$yes" = "--yes" ] || { read -rp "Restore $B? [y/N] " a; [ "$a" = y ] || die "aborted"; }
    T=$(mktemp -d); tar -C "$T" -xzf "$B"
    rsync -rlc --inplace --delete "${F[@]}" "$T/eddy/" "$LIVE/"; rm -rf "$T"
    live_sums > "$MANIFEST"
    ok "restored $B"; verify_live ;;

  *) usage ;;
esac
