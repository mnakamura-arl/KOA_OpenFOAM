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

The T0.8 case is about 11 GB compressed and 17 GB unpacked, mostly from 1,600 `alpha.water` writes.

## ParaView: reading the results

Open the case's `.foam` file (create an empty one with `touch case.foam` if there isn't one) and
set **Case Type = Reconstructed Case**.

ParaView can't read the collated `processors24/` folder, so **Decomposed Case** won't work for these
runs. That includes `postProcess2.py`, which needs this line changed:

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
~/apps/ParaView-5.13.3-osmesa-MPI-Linux-Python3.10-x86_64/bin/pvbatch postProcess2.py case.foam
```

## Wave-gauge analysis (`plot_ws3.py`)

`postprocessing/plot_ws3.py` is a Python port of the lab's `plot_ws3.m`, `waveSeparation.m` and
`solveDispersionEquation.m`. It gives the same numbers without MATLAB.

1. Extract the free surface (the alpha = 0.5 contour) at every output time into `fs/`:
   ```bash
   cd MyCase && pvbatch postProcess2.py case.foam      # about 50 min for 1,600 times
   ```
2. Run the analysis:
   ```bash
   ~/apps/venv-analysis/bin/python KOA_OpenFOAM/postprocessing/plot_ws3.py MyCase
   ```

It reads the wave period and depth from the case's `constant/waveProperties`, samples the gauges at
x = 7, 7.2, 15 and 15.2 m, and runs the two-gauge separation on 4 periods starting at t = 30 s. It
writes `outparams_T<T>.txt` (T, L, ai, Cr, Ct, CL, CLn, b/L, d/L) and plots of the gauge records and
fits. Gauge positions, the plate geometry and the analysis window are set at the top of the script.

T0.8 result: **ai = 0.004496 m** (target H/2 = 0.0045 m), Cr = 0.884, Ct = 0.291.

**Sanity checks for a new case:**
- `ai` ≈ H/2 means the wave maker produces the intended wave. If it comes out low, the mesh may be
  damping the wave.
- `separation_x12.png` should show the raw points sitting on the fitted curves.
- `filter_fs_x12.png` should be steady well before the analysis window (t = 30 s).

## Videos

`postprocessing/make_video.sh` renders `alpha.water` to an MP4:

```bash
KOA_OpenFOAM/postprocessing/make_video.sh MyCase full       # whole flume, vertical scale x20
KOA_OpenFOAM/postprocessing/make_video.sh MyCase plates     # close-up of the plates, x4
KOA_OpenFOAM/postprocessing/make_video.sh MyCase full 4     # every 4th frame (faster preview)
```

Videos are saved to `MyCase/videos/`. At 4 parallel renderers, the full T0.8 run (1,600 frames)
takes 30–45 minutes. The view framing (x range, exaggeration, image size) is set in `VIEWS` at the
top of `render_frames.py`. Adjust it for a different geometry.

## Comparing two runs

`scripts/compare_runs.py` compares the internal fields of two runs at every time they have in
common. It reads both ascii and binary files.

```bash
python3 KOA_OpenFOAM/scripts/compare_runs.py RunA RunB                 # alpha.water U p_rgh k omega nut
python3 KOA_OpenFOAM/scripts/compare_runs.py RunA RunB alpha.water     # just one field
```

Use it to verify that a settings change (output format, core count, Koa vs workstation) doesn't
change the results. With 1,600 times it takes 30–60 minutes, so on Koa run it as a job:

```bash
sbatch -p shared -n 1 --mem=16G -t 4:00:00 -o compare-%j.out --wrap "python3 -u KOA_OpenFOAM/scripts/compare_runs.py RunA RunB"
```
