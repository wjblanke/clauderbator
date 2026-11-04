#!/bin/sh
# Turn a photo into a tiled poster you print at home and tape together.
#
# usage: ./rasterbate.sh <image> <poster width in inches> <output> [jpeg] [color] [preview] [enlarge]
#
#   <output>   a .pdf file (Letter pages), or a folder when "jpeg" is given (4x6" photos at 300 dpi)
#   jpeg       make 4x6" photo prints instead of Letter pages
#   color      dots keep the photo's colours instead of black halftone dots
#   preview    a single big page showing the whole poster (PDF only, for checking the look)
#   enlarge    skip the dots: just enlarge the photo itself and tile it (macOS Swift / CoreImage)
#
# The poster height follows from the photo's aspect ratio. Dot spacing defaults to 0.15 in;
# set DOT=0.2 (etc.) in the environment to change it.
#
# Requires macOS (sips, swift for "enlarge") and python3. No third-party packages.
set -eu

if [ $# -lt 3 ]; then
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

IMG=$1; POSTER_W=$2; OUT=$3; shift 3
HERE=$(cd "$(dirname "$0")" && pwd)
DOT=${DOT:-0.15}
MODE=dots; OPTS=""
for o in "$@"; do
    case $o in
        enlarge) MODE=enlarge ;;
        jpeg|color|preview) OPTS="$OPTS $o" ;;
        *) echo "rasterbate.sh: unknown option '$o'" >&2; exit 1 ;;
    esac
done
[ -f "$IMG" ] || { echo "rasterbate.sh: no such image: $IMG" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rasterbate.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Normalise to an 8-bit sRGB PNG no larger than 760 px on its long side. This is the input
# png2grid.py averages into dots, and its pixel size also gives us the aspect ratio.
sips -s format png -Z 760 "$IMG" --out "$TMP/mid.png" >/dev/null
W=$(sips -g pixelWidth  "$TMP/mid.png" | awk '/pixelWidth/  {print $2}')
H=$(sips -g pixelHeight "$TMP/mid.png" | awk '/pixelHeight/ {print $2}')

# poster height from the aspect ratio; grid of dots at ~DOT inch spacing
SIZES=$(python3 -I -c '
import sys
w, h, pw, dot = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
ph = round(pw * h / w, 2)
print(ph, max(1, round(pw / dot)), max(1, round(ph / dot)))
' "$W" "$H" "$POSTER_W" "$DOT")
read -r POSTER_H COLS ROWS <<EOF
$SIZES
EOF
export POSTER_W POSTER_H
echo "poster ${POSTER_W} x ${POSTER_H} in"

if [ "$MODE" = enlarge ]; then
    case $OPTS in *color*|*preview*) echo "rasterbate.sh: 'enlarge' ignores color/preview" >&2 ;; esac
    case $OPTS in *jpeg*) J=jpeg ;; *) J= ;; esac
    swift "$HERE/enlarge.swift" "$IMG" "$OUT" $J
else
    python3 -I "$HERE/png2grid.py" "$TMP/mid.png" "$TMP/grid.txt" "$COLS" "$ROWS" >/dev/null
    # shellcheck disable=SC2086
    python3 -I "$HERE/rasterbate.py" "$TMP/grid.txt" "$OUT" $OPTS
fi
