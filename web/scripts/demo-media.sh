#!/usr/bin/env bash
# Turn the Playwright demo recording into docs/media/web-demo.mp4 and web-demo.gif.
# Run from anywhere after: cd web && npm run demo:video
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
web="$root/web"
media="$root/docs/media"
mkdir -p "$media"

webm="$(find "$web/test-results" -type f -name '*.webm' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)"
if [[ -z "${webm}" ]]; then
  echo "No .webm under web/test-results. Run: cd web && npm run demo:video" >&2
  exit 1
fi

timeline="$(find "$web/test-results" -type f -name 'demo-timeline.json' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2- || true)"

spans="$(python3 - "${timeline:-}" <<'PY'
import json, sys
path = sys.argv[1]
home = [0.4, 12.0]
routing = [36.0, 50.0]
if path:
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        home = [float(data["home"][0]), float(data["home"][1])]
        routing = [float(data["routing"][0]), float(data["routing"][1])]
    except (OSError, KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError):
        pass

def take(span, seconds):
    start, end = span
    length = max(0.0, end - start)
    return start, min(seconds, length)

home_ss, home_t = take(home, 11.5)
route_ss, route_t = take(routing, 12.0)
total = home_t + route_t
if total > 25:
    overflow = total - 23.5
    route_t = max(8.0, route_t - overflow)
    total = home_t + route_t
    if total > 25:
        home_t = max(8.0, home_t - (total - 23.5))
elif total < 20:
    extra = 20.0 - total
    route_room = max(0.0, (routing[1] - routing[0]) - route_t)
    add = min(extra, route_room)
    route_t += add
    extra -= add
    home_room = max(0.0, (home[1] - home[0]) - home_t)
    home_t += min(extra, home_room)
print(f"{home_ss:.3f} {home_t:.3f} {route_ss:.3f} {route_t:.3f}")
PY
)"
read -r home_ss home_t route_ss route_t <<<"$spans" || true
if [[ -z "${home_t:-}" || -z "${route_t:-}" ]]; then
  echo "Could not resolve highlight timings from: ${spans:-<empty>}" >&2
  exit 1
fi

echo "Source: $webm"
echo "Highlight: home ${home_ss}s +${home_t}s, routing ${route_ss}s +${route_t}s"

mp4="$media/web-demo.mp4"
gif="$media/web-demo.gif"

encode_mp4() {
  local crf="$1"
  ffmpeg -y -i "$webm" -an \
    -c:v libx264 -preset medium -crf "$crf" -pix_fmt yuv420p \
    -vf "scale=1280:-2:flags=lanczos" \
    -movflags +faststart \
    "$mp4"
}

encode_mp4 28
mp4_size="$(python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "$mp4")"
if [[ "$mp4_size" -ge 10000000 ]]; then
  echo "web-demo.mp4 is ${mp4_size} bytes at crf 28; re-encoding at crf 33"
  encode_mp4 33
fi

encode_gif() {
  local colors="$1"
  local filter
  filter="[0:v]split[v0][v1];"
  filter+="[v0]trim=start=${home_ss}:duration=${home_t},setpts=PTS-STARTPTS,fps=10,scale=800:-1:flags=lanczos[h];"
  filter+="[v1]trim=start=${route_ss}:duration=${route_t},setpts=PTS-STARTPTS,fps=10,scale=800:-1:flags=lanczos[r];"
  filter+="[h][r]concat=n=2:v=1:a=0,split[s0][s1];"
  filter+="[s0]palettegen=stats_mode=diff:max_colors=${colors}[p];"
  filter+="[s1][p]paletteuse=dither=floyd_steinberg:diff_mode=rectangle"
  ffmpeg -y -i "$webm" -filter_complex "$filter" -loop 0 "$gif"
}

colors=128
encode_gif "$colors"
gif_size="$(python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "$gif")"
while [[ "$gif_size" -ge 5000000 && "$colors" -gt 32 ]]; do
  colors=$((colors - 32))
  echo "web-demo.gif is ${gif_size} bytes; retrying palette with ${colors} colors"
  encode_gif "$colors"
  gif_size="$(python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "$gif")"
done

python3 - "$mp4" "$gif" <<'PY'
import os, sys
limits = {sys.argv[1]: 10_000_000, sys.argv[2]: 5_000_000}
failed = False
for path, limit in limits.items():
    size = os.path.getsize(path)
    print(f"{path}: {size} bytes (limit {limit})")
    if size >= limit:
        failed = True
if failed:
    raise SystemExit(1)
PY

ffprobe -v error -show_entries format=duration,size -of default=nw=1 "$mp4"
ffprobe -v error -show_entries format=duration,size -of default=nw=1 "$gif"
