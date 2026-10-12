#!/usr/bin/env bash
# Renders the README tutorial (docs/tutorial.gif) from the app's real views with fake data:
# no real account or usage ever appears. Also produces build/tutorial/tutorial.mp4.
#   ./scripts/make-tutorial.sh        -> English (default)
#   ./scripts/make-tutorial.sh fr     -> French UI (docs/tutorial-fr.gif)
# Requires ffmpeg (brew install ffmpeg).
set -euo pipefail
cd "$(dirname "$0")/.."

LANG_CODE="${1:-en}"
case "$LANG_CODE" in
    en) LOCALE=en_US; SUFFIX="" ;;
    fr) LOCALE=fr_FR; SUFFIX="-fr" ;;
    *) echo "usage: $0 [en|fr]" >&2; exit 1 ;;
esac
command -v ffmpeg >/dev/null || { echo "ffmpeg not found (brew install ffmpeg)" >&2; exit 1; }

OUT="build/tutorial"
FRAMES="$OUT/frames-$LANG_CODE"
GIF="docs/tutorial${SUFFIX}.gif"
MP4="$OUT/tutorial${SUFFIX}.mp4"

echo "▸ swift build (debug: the renderer is excluded from release builds)"
swift build

echo "▸ Rendering frames ($LANG_CODE)"
rm -rf "$FRAMES"
# Fixed language, locale and time zone so the result doesn't depend on the machine.
TZ=UTC .build/debug/CopilotCredits --render-tutorial "$FRAMES" \
    -appLanguage "$LANG_CODE" -AppleLocale "$LOCALE" -AppleLanguages "($LANG_CODE)"

echo "▸ $GIF"
mkdir -p docs
ffmpeg -loglevel error -y -f concat -safe 0 -i "$FRAMES/frames.txt" \
    -vf "fps=20,scale=1520:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    "$GIF"

echo "▸ $MP4"
ffmpeg -loglevel error -y -f concat -safe 0 -i "$FRAMES/frames.txt" \
    -vf "fps=30,format=yuv420p" -c:v libx264 -crf 18 -movflags +faststart "$MP4"

ls -lh "$GIF" "$MP4" | awk '{print "✓", $NF, $5}'
