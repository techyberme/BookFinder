#!/usr/bin/env bash
# Re-captures live OPAC + Goodreads responses into the test fixtures directory.
# Mirrors the request sequence of backend/scraper.py (same headers, cookie jar, payloads).
# Usage: ios/Scripts/capture_fixtures.sh [output_dir]
set -euo pipefail

OUT="${1:-$(cd "$(dirname "$0")/.." && pwd)/ZahoriKit/Tests/ZahoriKitTests/Fixtures}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BASE="https://gestiona.comunidad.madrid"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
CURL=(curl -sS -L --max-time 25 -A "$UA"
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  -H "Accept-Language: es-ES,es;q=0.9,en;q=0.8")

# Opens a fresh OPAC session; prints the form action URL. Saves handshake pages when $1 = save.
open_session() {
  local jar="$WORK/jar_$RANDOM"
  : > "$jar"
  echo "$jar" > "$WORK/current_jar"
  "${CURL[@]}" -b "$jar" -c "$jar" -o "$WORK/entry.html" "$BASE/biblio_publicas/cgi-bin/abnetopac?ACC=101"
  local path
  path=$(grep -io 'URL=[^"'"'"']*' "$WORK/entry.html" | head -1 | cut -c5-)
  local session_url="$BASE$path"
  "${CURL[@]}" -b "$jar" -c "$jar" -o "$WORK/home.html" "$session_url"
  local adv_url="${session_url%%\?*}?ACC=120&FORM=2"
  "${CURL[@]}" -b "$jar" -c "$jar" -o "$WORK/adv.html" "$adv_url"
  if [[ "${1:-}" == save ]]; then
    cp "$WORK/entry.html" "$OUT/opac_session_entry.html"
    cp "$WORK/adv.html" "$OUT/opac_advanced_form.html"
  fi
  local action
  action=$(python3 -I -c 'import re,sys;m=re.search(r"<form[^>]*name=\"abnform\"[^>]*action=\"([^\"]+)\"",open(sys.argv[1],encoding="latin-1").read(),re.I);print(m.group(1) if m else "")' "$WORK/adv.html")
  if [[ -z "$action" ]]; then echo "$adv_url"; elif [[ "$action" == /* ]]; then echo "$BASE$action"; else echo "${adv_url%/*}/$action"; fi
}

# search <out_file> key=value...  (form-encoded as UTF-8, exactly like httpx data=)
search() {
  local out="$1"; shift
  local action; action=$(open_session)
  local jar; jar=$(cat "$WORK/current_jar")
  local args=()
  for kv in "$@"; do args+=(--data-urlencode "$kv"); done
  "${CURL[@]}" -b "$jar" -c "$jar" -o "$OUT/$out" -w '%{url_effective}\n' "${args[@]}" "$action" > "$OUT/$out.url"
  echo "$jar" > "$WORK/last_jar"
}

COMMON=(ACC=131 START=1 FORM=2 subcat=/ xsnlis=10 xssort=55088864)

open_session save > /dev/null

# Title + author, multiple editions -> results list
search opac_list_cien_anos.html "${COMMON[@]}" xsqf01= xsnf12=0 "xsqf12=Cien años de soledad" "xsqf03=García Márquez"
# First detail page from that list (same session)
detail=$(python3 -I -c 'import re,sys,html;m=re.search(r"href=\"([^\"]*ACC=165[^\"]*)\"",open(sys.argv[1],encoding="latin-1").read());print(html.unescape(m.group(1)) if m else "")' "$OUT/opac_list_cien_anos.html")
if [[ -n "$detail" ]]; then
  list_url=$(cat "$OUT/opac_list_cien_anos.html.url")
  if [[ "$detail" == /* ]]; then detail_url="$BASE$detail"; elif [[ "$detail" == http* ]]; then detail_url="$detail"; else detail_url="${list_url%/*}/$detail"; fi
  jar=$(cat "$WORK/last_jar")
  "${CURL[@]}" -b "$jar" -c "$jar" -o "$OUT/opac_detail_cien_anos.html" "$detail_url"
  echo "$detail_url" > "$OUT/opac_detail_cien_anos.html.url"
fi
# No results
search opac_no_results.html "${COMMON[@]}" xsqf01= xsnf12=0 xsqf12=xkqw7899zznonexistenttitle9999 xsqf03=
# Author only
search opac_author_rowling.html "${COMMON[@]}" xsqf01= xsnf12=4 "xsqf12=J K Rowling" "xsqf03=J K Rowling"
# Likely single-record hit -> direct detail page
search opac_single_result.html "${COMMON[@]}" xsqf01= xsnf12=0 "xsqf12=El infinito en un junco" "xsqf03=Irene Vallejo"

# Goodreads RSS (demo user from frontend/app.js)
curl -sS -L --max-time 25 -A "$UA" -H "Accept: application/rss+xml, application/xml, text/xml, */*" \
  -o "$OUT/goodreads_to_read.xml" "https://www.goodreads.com/review/list_rss/177587843?shelf=to-read"

ls -la "$OUT"
