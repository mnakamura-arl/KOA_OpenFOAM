#!/bin/bash
# One-time setup of the post-processing tools on a Linux machine or WSL, without sudo:
#   - ParaView 5.13.3 headless (OSMesa) build: pvbatch/pvpython render without a display or GPU
#   - the Mesa/JPEG/TBB libraries it needs, unpacked from Ubuntu packages (no install)
#   - ffmpeg (via pip) for encoding videos
#   - numpy/scipy/matplotlib for plot_ws3.py
# Everything goes in ~/apps (override with APPS=/some/dir).
set -euo pipefail

APPS=${APPS:-$HOME/apps}
PV=ParaView-5.13.3-osmesa-MPI-Linux-Python3.10-x86_64
mkdir -p "$APPS"
cd "$APPS"

if [ ! -d "$PV" ]; then
    echo "== downloading ParaView (~600 MB)"
    curl -sSL -o pv.tar.gz "https://www.paraview.org/files/v5.13/$PV.tar.gz"
    tar -xzf pv.tar.gz && rm pv.tar.gz
fi

# Libraries the ParaView build expects from the system. apt-get download needs no sudo.
# On Ubuntu releases older than 26.04 the GL API package is libglapi-mesa instead of libglapi-amber.
missing=$(LD_LIBRARY_PATH=$APPS/pvdeps/root/usr/lib/x86_64-linux-gnu ldd "$PV/lib/libOSMesa.so" "$PV/lib/libtiff.so" "$PV/lib/libOpenImageDenoise.so" | grep -c "not found" || true)
if [ "$missing" -gt 0 ]; then
    echo "== fetching missing libraries"
    mkdir -p pvdeps/debs && cd pvdeps/debs
    glapi=libglapi-amber
    apt-cache show "$glapi" > /dev/null 2>&1 || glapi=libglapi-mesa
    apt-get download "$glapi" libjpeg62 libtbb12
    for d in *.deb; do dpkg-deb -x "$d" ../root; done
    cd "$APPS"
fi

[ -d venv-ffmpeg ] || { python3 -m venv venv-ffmpeg && venv-ffmpeg/bin/pip install -q imageio-ffmpeg; }
[ -d venv-analysis ] || { python3 -m venv venv-analysis && venv-analysis/bin/pip install -q numpy scipy matplotlib; }

echo "== testing"
export LD_LIBRARY_PATH=$APPS/pvdeps/root/usr/lib/x86_64-linux-gnu
"$PV/bin/pvbatch" --version
echo "Setup done. pvbatch is at $APPS/$PV/bin/pvbatch"
echo "Before running pvbatch yourself:  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
