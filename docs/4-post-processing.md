# 4. Post-processing

## Copy results back

Pack the case on Koa, leaving out the decomposed copy:

```bash
cd ~/koa_scratch/openfoam && tar --exclude='processors*' --exclude='processor[0-9]*' -czf MyCase.tar.gz MyCase
```

From your own machine (Linux, macOS or WSL), download and unpack it:

```bash
scp <uh-username>@koa.its.hawaii.edu:~/koa_scratch/openfoam/MyCase.tar.gz . && tar -xzf MyCase.tar.gz
```

Writing fields often (for example, every 0.025 s) can produce tens of GB. Check the size first with
`du -sh MyCase` on Koa.

## ParaView: reading the results

Open the case's `.foam` file (create an empty one with `touch case.foam` if there isn't one) and
set **Case Type = Reconstructed Case**.

ParaView can't read the collated `processors<N>/` folder, so **Decomposed Case** won't work for these
runs. Any ParaView Python script that uses `CaseType="Decomposed Case"` needs this change:

```python
foam = OpenFOAMReader(FileName=foam_file, CaseType="Reconstructed Case")
```

## Headless ParaView on Linux/WSL (no admin rights needed)

If you can't install ParaView normally, `postprocessing/setup_paraview_linux.sh` sets up a headless
build in `~/apps`. It renders in software, so it needs no display or GPU.

```bash
KOA_OpenFOAM/postprocessing/setup_paraview_linux.sh
```

It installs:
- ParaView 5.13.3 (OSMesa build), which provides `pvbatch` and `pvpython`
- three system libraries ParaView expects, unpacked from Ubuntu packages without installing them
- `ffmpeg` (through pip) for videos, and numpy/scipy/matplotlib for the analysis script

To run `pvbatch` yourself:

```bash
export LD_LIBRARY_PATH=~/apps/pvdeps/root/usr/lib/x86_64-linux-gnu
~/apps/ParaView-5.13.3-osmesa-MPI-Linux-Python3.10-x86_64/bin/pvbatch my_script.py case.foam
```

## Wave-gauge analysis (`plot_ws3.py`)

`postprocessing/plot_ws3.py` samples the free surface at numerical wave gauges and separates the
incident and reflected waves with the two-gauge (Goda) method. It's a Python port of the MATLAB
scripts `plot_ws3.m`, `waveSeparation.m` and `solveDispersionEquation.m`, and gives the same results.

1. **Extract the free surface** (the alpha.water = 0.5 contour) at every output time into `fs/`, one
   CSV file per time, with columns x, y. A ParaView Python script that slices the 2-D case, contours
   `alpha.water` at 0.5, and saves each time with `SaveData` does this. Run it with `pvbatch`.
2. **Run the analysis:**
   ```bash
   ~/apps/venv-analysis/bin/python KOA_OpenFOAM/postprocessing/plot_ws3.py MyCase
   ```

The script reads the wave period and depth from the case's `constant/waveProperties`. The gauge
positions, structure dimensions (used for b/L and d/L) and analysis window (start time and number of
periods) are set at the top of the script. Edit them for your setup.

It writes, in the case folder:
- `outparams_T<T>.txt`: T, L, ai (incident amplitude), Cr (reflection), Ct (transmission), CL
  (loss), CLn, b/L, d/L
- `filter_fs_x12.png`, `filter_fs_x34.png`: the gauge time series
- `separation_x12.png`, `separation_x34.png`: the raw gauge data with the fitted curves

**Sanity checks:**
- `ai` should be close to H/2 (half the wave height in `waveProperties`). If it's noticeably low, the
  mesh may be damping the wave between the wave maker and the gauges.
- In `separation_*.png`, the raw points should sit on the fitted curves.
- In `filter_fs_*.png`, the signal should be steady well before the analysis window starts.

## Videos

`postprocessing/make_video.sh` renders `alpha.water` to an MP4:

```bash
KOA_OpenFOAM/postprocessing/make_video.sh MyCase full       # whole domain, vertical scale x20
KOA_OpenFOAM/postprocessing/make_video.sh MyCase zoom       # zoomed region, vertical scale x4
KOA_OpenFOAM/postprocessing/make_video.sh MyCase full 4     # every 4th output time (faster preview)
```

Videos are saved to `MyCase/videos/`. Rendering takes about 1–2 seconds per frame with 4 renderers
in parallel. The views (x range, vertical centre, vertical exaggeration, image size) are defined in
`VIEWS` at the top of `postprocessing/render_frames.py`. Set the `zoom` x range to the region you're
interested in.

## Comparing two runs

`scripts/compare_runs.py` compares the internal fields of two runs at every time they have in
common. It reads both ascii and binary files.

```bash
python3 KOA_OpenFOAM/scripts/compare_runs.py RunA RunB                 # alpha.water U p_rgh k omega nut
python3 KOA_OpenFOAM/scripts/compare_runs.py RunA RunB alpha.water     # just one field
```

Use it to check that a settings change, such as output format, core count or machine, doesn't
change the results. With many output times it can take an hour, so on Koa run it as a job:

```bash
sbatch -p shared -n 1 --mem=16G -t 4:00:00 -o compare-%j.out --wrap "python3 -u KOA_OpenFOAM/scripts/compare_runs.py RunA RunB"
```

If one run was written in ascii, expect differences at the level of its last written digit. The
script reports a match when every field agrees to within ascii rounding (relative difference below
1e-5).
