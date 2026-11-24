#!/usr/bin/env bash
# Renders a Mermaid (.mmd) file to PNG with headless Chrome (macOS/Linux
# counterpart of render-diagram.ps1). Pass 1 renders the SVG and reads its
# size; pass 2 screenshots the SVG alone at that size, so no cropping is needed.
# Usage: harness/render-diagram.sh <input.mmd> <output.png> [scale]
set -euo pipefail
in="$1"; out="$2"; scale="${3:-2}"
chrome="${CHROME:-}"
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
         google-chrome chromium chromium-browser microsoft-edge; do
  [ -n "$chrome" ] && break
  if [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; then chrome="$c"; fi
done
[ -n "$chrome" ] || { echo "Chrome/Edge not found (set CHROME=...)" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
cat > "$tmp/render.html" <<EOF
<!doctype html><html><head><meta charset="utf-8">
<style>body{margin:0;background:#fff;font-family:'Apple SD Gothic Neo','Malgun Gothic','Noto Sans CJK KR',sans-serif}</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js"></script>
</head><body><pre class="mermaid">$(esc < "$in")</pre>
<script>mermaid.initialize({startOnLoad:true,theme:'default',themeVariables:{fontSize:'22px',fontFamily:"'Apple SD Gothic Neo','Malgun Gothic','Noto Sans CJK KR',sans-serif"},flowchart:{htmlLabels:true,nodeSpacing:40,rankSpacing:70}});</script>
</body></html>
EOF
run() { "$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
  --user-data-dir="$tmp/profile" --virtual-time-budget=10000 "$@" 2>/dev/null; }

# Pass 1: rendered DOM -> the <svg> element and its viewBox size.
run --dump-dom "file://$tmp/render.html" > "$tmp/dom.html"
svg=$(python3 -c 'import re,sys;d=open(sys.argv[1]).read();m=re.search(r"<svg.*?</svg>",d,re.S);print(m.group(0) if m else "")' "$tmp/dom.html")
[ -n "$svg" ] || { echo "Mermaid did not render $in" >&2; exit 1; }
read -r w h < <(python3 -c 'import re,sys,math;v=re.search(r"viewBox=\"([^\"]+)\"",sys.argv[1]).group(1).split();print(math.ceil(float(v[2]))+32,math.ceil(float(v[3]))+32)' "$svg")

# Pass 2: screenshot the SVG alone at its own size.
{ printf '<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:#fff;font-family:%s}svg{display:block;margin:16px;max-width:none!important;width:%spx;height:%spx}</style></head><body>' \
    "'Apple SD Gothic Neo','Malgun Gothic','Noto Sans CJK KR',sans-serif" "$((w-32))" "$((h-32))"
  printf '%s' "$svg"; printf '</body></html>'; } > "$tmp/shot.html"
rm -f "$out"
run --force-device-scale-factor="$scale" --window-size="$w,$h" --screenshot="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")" "file://$tmp/shot.html"
[ -s "$out" ] || { echo "Chrome did not write $out" >&2; exit 1; }
echo "Saved $out (${w}x${h} @${scale}x)"
