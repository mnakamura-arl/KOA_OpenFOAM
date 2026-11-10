# 5. Building the image

You only need this to change what's inside the container, for example a different OpenFOAM version
or a newer waves2Foam. Otherwise, pull the published image (see [Getting started](1-getting-started.md)).

## What's in it

`container/waves2foam-2206.def`:

- **Base:** `opencfd/openfoam-dev:2206`, the official ESI OpenFOAM v2206 image with compilers and headers
- **Adds:** `subversion git gfortran make libgsl-dev`
- **waves2Foam:** checked out from SVN at revision **r2157**
  (`https://svn.code.sf.net/p/openfoam-extend/svn/trunk/Breeder_1.6/other/waves2Foam`) and compiled
  into `/opt/waves2Foam`, including its Fortran third-party parts (LAPACK, SPARSKIT2, OceanWave3D)
- **`/opt/foam-env.sh`:** loads OpenFOAM and puts the waves2Foam binaries and libraries on the path
- **Build check:** the build fails if `waveFoam`, `setWaveParameters`, `setWaveField`,
  `waveGaugesNProbes` or `libwaves2Foam.so` is missing

## Build on Koa

```bash
cd ~/koa_scratch/openfoam/KOA_OpenFOAM/container && sbatch build_image.slurm
tail -f build_image-<jobid>.out
```

This takes 20–40 minutes and produces `waves2foam-2206.sif` (374 MB). The job keeps Apptainer's
cache and temp files on the node's local `/tmp`, because unpacking the image on Lustre scratch is
extremely slow.

The compile prints many `warning:` lines (deprecated APIs, unused variables). They're harmless. A
real failure shows `error:` or `BUILD FAILED`.

## Changing versions

- **Another OpenFOAM release:** change `From: opencfd/openfoam-dev:2206` and every `openfoam2206`
  path. waves2Foam provides solvers for specific versions (`applications/solvers/solvers<version>_PLUS`),
  so check that one exists for the release you want.
- **Another waves2Foam revision:** change `-r 2157` in the `svn checkout` line.

## Publishing

The image is published to the GitHub Container Registry as an ORAS artifact, which Apptainer can
push and pull directly.

1. Create a GitHub token (classic) with the `write:packages` scope.
2. On a Koa compute node, log in. Paste the token at the password prompt:
   ```bash
   apptainer registry login --username <github-user> oras://ghcr.io
   # older Apptainer: apptainer remote login --username <github-user> oras://ghcr.io
   ```
3. Push with a tag that names both versions:
   ```bash
   apptainer push waves2foam-2206.sif oras://ghcr.io/<github-user>/waves2foam:v2206-r2157
   ```
4. New packages are private. To make one public, go to **GitHub → Packages → waves2foam → Package
   settings → Change visibility → Public**.

The image is for Apptainer/Singularity (HPC). Running it with Docker on a laptop would need a
separate Dockerfile build.

OpenFOAM and waves2Foam are GPL-licensed. Keep the `.def` file with the published image, so the
build is reproducible.
