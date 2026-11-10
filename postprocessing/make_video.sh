#!/bin/bash
# Render a case's alpha.water field to an MP4 with headless ParaView (no display or GPU needed).
# Run setup_paraview_linux.sh once first.
#
# Usage:  postprocessing/make_video.sh <case_dir> [full|zoom] [stride] [nparts]
#   full    whole domain, vertical scale x20 (default)
#   zoom    close-up of a region, vertical scale x4 (set its x range in VIEWS in render_frames.py)
#   stride  use every Nth output time (default 1). Video plays at 40/stride frames per second
#           (real time when fields are written every 0.025 s; set FPS=... to override)
#   nparts  number of pvbatch copies to run at once (default 4; each needs ~2 GB RAM)
#
# Output: <case_dir>/videos/<case>_<view>.mp4
set -euo pipefail

CASE=$(cd "$1" && pwd)
VIEW=${2:-full}
STRIDE=${3:-1}
NPARTS=${4:-4}

HERE=$(cd "$(dirname "$0")" && pwd)
APPS=${APPS:-$HOME/apps}
PVBATCH=$APPS/ParaView-5.13.3-osmesa-MPI-Linux-Python3.10-x86_64/bin/pvbatch
export LD_LIBRARY_PATH=$APPS/pvdeps/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
FFMPEG=$("$APPS/venv-ffmpeg/bin/python" -c "import imageio_ffmpeg as f; print(f.get_ffmpeg_exe())")

FOAM=$(ls "$CASE"/*.foam 2>/dev/null | head -1)
if [ -z "$FOAM" ]; then
    FOAM=$CASE/case.foam
    touch "$FOAM"
fi

FRAMES=$CASE/videos/frames_$VIEW
FPS=${FPS:-$((40 / STRIDE))}
mkdir -p "$FRAMES"
rm -f "$FRAMES"/frame_*.png

echo "== $(date)  rendering $VIEW view of $CASE with $NPARTS copies"
for p in $(seq 0 $((NPARTS - 1))); do
    "$PVBATCH" "$HERE/render_frames.py" "$FOAM" "$FRAMES" --view "$VIEW" --stride "$STRIDE" \
        --part "$p" --nparts "$NPARTS" > "$FRAMES/render_$p.log" 2>&1 &
done
wait

OUT=$CASE/videos/$(basename "$CASE")_$VIEW.mp4
echo "== $(date)  encoding"
"$FFMPEG" -y -loglevel error -framerate "$FPS" -i "$FRAMES/frame_%05d.png" \
    -c:v libx264 -pix_fmt yuv420p -crf 20 "$OUT"
ls -lh "$OUT"
echo "== $(date)  done (frames are in $FRAMES and can be deleted)"
