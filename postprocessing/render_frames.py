# Render alpha.water frames of a 2-D waves2Foam case with headless ParaView.
#
# Usage:
#   pvbatch render_frames.py <case.foam> <outdir> [--view full|zoom] [--stride N] [--part I --nparts N]
#
# --view full    whole domain, vertical scale x20 (default)
# --view zoom    close-up of a region (set its x range in VIEWS), vertical scale x4
# --stride N     render every Nth output time (default 1)
# --part/--nparts  render only frames where index % nparts == part (for running several copies at once)

import argparse
import os
import re

from paraview.simple import *

# Edit these for your geometry: x range shown [m], vertical centre of the view [m] (before
# exaggeration), vertical exaggeration, and image size [px]. "full" uses the mesh's x extent when
# x is None. The still-water level is y = 0 and y points up.
VIEWS = {
    "full": dict(x=None, yc=-0.045, scale=20.0, size=(1920, 480)),
    "zoom": dict(x=(9.4, 10.9), yc=-0.045, scale=4.0, size=(1920, 1080)),
}

p = argparse.ArgumentParser()
p.add_argument("foam")
p.add_argument("outdir")
p.add_argument("--view", choices=VIEWS, default="full")
p.add_argument("--stride", type=int, default=1)
p.add_argument("--part", type=int, default=0)
p.add_argument("--nparts", type=int, default=1)
args = p.parse_args()
v = VIEWS[args.view]
os.makedirs(args.outdir, exist_ok=True)

# Reader: merged (reconstructed) time folders, alpha.water only
foam = OpenFOAMReader(FileName=os.path.abspath(args.foam))
foam.CaseType = "Reconstructed Case"
foam.MeshRegions = ["internalMesh"]
foam.CellArrays = ["alpha.water"]
foam.Createcelltopointfiltereddata = 1
foam.UpdatePipelineInformation()
times = list(foam.TimestepValues)[::args.stride]
foam.UpdatePipeline(times[0])
bounds = foam.GetDataInformation().GetBounds()
zmin, zmax = bounds[4:6]
if v["x"] is None:
    v["x"] = (bounds[0], bounds[1])
zmid = 0.5 * (zmin + zmax)

# The case is 2-D (one cell thick in z): cut through the middle, then stretch vertically
sl = Slice(Input=foam)
sl.SliceType = "Plane"
sl.SliceType.Origin = [10.0, 0.0, zmid]
sl.SliceType.Normal = [0.0, 0.0, 1.0]
stretched = Transform(Input=sl)
stretched.Transform.Scale = [1.0, v["scale"], 1.0]
surface = Contour(Input=stretched, ContourBy=["POINTS", "alpha.water"], Isosurfaces=[0.5])

view = CreateView("RenderView")
view.ViewSize = list(v["size"])
view.OrientationAxesVisibility = 0
view.UseColorPaletteForBackground = 0
view.Background = [0.15, 0.15, 0.17]   # solid structures are holes in the mesh, so they show as this colour

water = Show(stretched, view)
ColorBy(water, ("CELLS", "alpha.water"))
lut = GetColorTransferFunction("alpha.water")
lut.RGBPoints = [0.0, 0.93, 0.95, 0.98,
                 0.5, 0.45, 0.68, 0.90,
                 1.0, 0.10, 0.35, 0.65]
lut.RescaleOnVisibilityChange = 0
lut.AutomaticRescaleRangeMode = "Never"
water.SetScalarBarVisibility(view, False)

line = Show(surface, view)
line.ColorArrayName = ["POINTS", ""]
line.AmbientColor = line.DiffuseColor = [0.0, 0.0, 0.0]
line.LineWidth = 2.0

label = Text()
label_disp = Show(label, view)
label_disp.WindowLocation = "Upper Left Corner"
label_disp.FontSize = 22 if v["size"][1] < 700 else 30
label_disp.Color = [1.0, 1.0, 1.0]

# Camera: looking along -z with parallel projection, framed on the chosen x range
x0, x1 = v["x"]
xc, yc = 0.5 * (x0 + x1), v["yc"] * v["scale"]
w, h = v["size"]
view.CameraParallelProjection = 1
view.CameraPosition = [xc, yc, zmid + 10.0]
view.CameraFocalPoint = [xc, yc, zmid]
view.CameraViewUp = [0.0, 1.0, 0.0]
view.CameraParallelScale = 0.5 * (x1 - x0) * h / w

def inlet(entry):
    """period/height from inletCoeffs in constant/waveProperties, or None."""
    try:
        text = open(os.path.join(os.path.dirname(os.path.abspath(args.foam)), "constant", "waveProperties")).read()
    except OSError:
        return None
    m = re.search(rf"^\s*{entry}\s+([0-9.eE+-]+)\s*;", text[text.find("inletCoeffs"):], re.M)
    return float(m.group(1)) if m else None


period, height = inlet("period"), inlet("height")
waves = f"T = {period:g} s, H = {height * 1000:g} mm    " if period and height else ""
caption = f"{waves}vertical scale x{v['scale']:g}"
for i, t in enumerate(times):
    if i % args.nparts != args.part:
        continue
    label.Text = f"t = {t:6.3f} s    {caption}"
    view.ViewTime = t
    SaveScreenshot(os.path.join(args.outdir, f"frame_{i:05d}.png"), view, ImageResolution=list(v["size"]))
    print(f"[{args.view}] frame {i + 1}/{len(times)}  t = {t}", flush=True)
