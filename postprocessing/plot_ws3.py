#!/usr/bin/env python3
"""Python port of plot_ws3.m + waveSeparation.m + solveDispersionEquation.m (numerical wave gauges, by CCMR).

Reads the free-surface contours in fs/ (from postProcess2.py), samples the surface elevation at
four gauges, and runs the two-gauge (Goda) separation to get incident/reflected/transmitted amplitudes.

Usage:  python plot_ws3.py [case_dir]      (default: current folder)
The wave period and depth are read from <case>/constant/waveProperties (inletCoeffs), so the
same script works for every case in a sweep; the values below are only fallbacks.
Writes, in the case folder: filter_fs_x12.png, filter_fs_x34.png, separation_x12.png,
separation_x34.png, outparams_T<T>.txt

The MATLAB indexing is reproduced exactly (time of file i is (i-1)*dt, 1-based window indices),
so the numbers should match plot_ws3.m. nlinfit is replaced by linear least squares, which gives
the same coefficients because the fit model is linear in its parameters.
"""
import glob
import os
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy.interpolate import CubicSpline

# output file timestep
dt = 1 / 40

# wave params
T = 0.8      # wave period
h = 0.625    # water depth

# structure dimensions, only used for the b/L and d/L outputs
b = 0.3      # plate spacing
d = 0.1      # plate draft

# separation params
t1 = 30      # initial time
nwaves = 5

# wave gauge locations
x1 = 7
x3 = 15
delta_wg = 0.2
x2 = x1 + delta_wg
x4 = x3 + delta_wg

tol = 1e-4   # wave gauge tolerance


def read_inlet(entry, default):
    """Read a scalar entry (period, depth, height) from inletCoeffs in constant/waveProperties."""
    try:
        text = open("constant/waveProperties").read()
    except OSError:
        return default
    inlet = text[text.find("inletCoeffs"):]
    m = re.search(rf"^\s*{entry}\s+([0-9.eE+-]+)\s*;", inlet, re.M)
    return float(m.group(1)) if m else default


def solve_dispersion_equation(h, T, L0):
    g = 9.81
    L = g * T * T * np.tanh(2 * np.pi / L0 * h) / 2 / np.pi
    while abs(L - L0) > 0.00001:
        L0 = L
        L = g * T * T * np.tanh(2 * np.pi / L0 * h) / 2 / np.pi
    return L


def model_matrix(t, sigma):
    # same terms (and order) as modelfun in waveSeparation.m
    return np.column_stack([
        np.cos(sigma * t), np.sin(sigma * t),
        np.cos(2 * sigma * t), np.sin(2 * sigma * t),
        np.sin(3 * sigma * t), np.cos(3 * sigma * t),
        np.sin(4 * sigma * t), np.cos(4 * sigma * t),
        np.sin(5 * sigma * t), np.cos(5 * sigma * t),
        np.ones_like(t),
    ])


def wave_separation(time, wg1, wg2, delta_L, m, n, T, h, plot_file):
    sigma = 2 * np.pi / T
    L = solve_dispersion_equation(h, T, 1)
    k = 2 * np.pi / L
    dt = time[1] - time[0]
    Ai, Ar, Cr = [], [], []
    ii = m
    while ii <= n:
        index1 = round(ii * T / dt)          # 1-based, as in MATLAB
        index2 = round((ii + 4) * T / dt)
        t = time[index1 - 1:index2]
        eta1 = wg1[index1 - 1:index2]
        eta2 = wg2[index1 - 1:index2]
        M = model_matrix(t, sigma)
        c1 = np.linalg.lstsq(M, eta1, rcond=None)[0]
        c2 = np.linalg.lstsq(M, eta2, rcond=None)[0]
        A1, B1 = c1[0], c1[1]
        A2, B2 = c2[0], c2[1]

        plt.figure()
        plt.plot(t, eta1, "kx", t, M @ c1, "k-", t, eta2, "rx", t, M @ c2, "r-")
        plt.legend([r"$\eta_1$ raw", r"$\eta_1$ fit", r"$\eta_2$ raw", r"$\eta_2$ fit"])
        plt.xlabel("time [s]")
        plt.ylabel(r"$\eta$ [m]")
        plt.savefig(plot_file, dpi=150, bbox_inches="tight")
        plt.close()

        X1 = (A2 - A1 * np.cos(k * delta_L) - B1 * np.sin(k * delta_L)) ** 2 + (B2 + A1 * np.sin(k * delta_L) - B1 * np.cos(k * delta_L)) ** 2
        X2 = (A2 - A1 * np.cos(k * delta_L) + B1 * np.sin(k * delta_L)) ** 2 + (B2 - A1 * np.sin(k * delta_L) - B1 * np.cos(k * delta_L)) ** 2
        Ai.append(1 / 2 / abs(np.sin(k * delta_L)) * np.sqrt(X1))   # incident wave amplitude
        Ar.append(1 / 2 / abs(np.sin(k * delta_L)) * np.sqrt(X2))   # reflected wave amplitude
        Cr.append(Ar[-1] / Ai[-1])                                   # reflection coefficient
        ii += 1
    return np.array(Ai), np.array(Ar), np.array(Cr)


def gauge(files, xa, xb):
    eta_a, eta_b = np.zeros(len(files)), np.zeros(len(files))
    for i, f in enumerate(files):
        dat = np.loadtxt(f, delimiter=",", skiprows=1, ndmin=2)
        if dat.size == 0:
            continue
        x, z = dat[:, 0], dat[:, 1]
        eta_a[i] = z[np.argmin(np.abs(x - xa))]
        eta_b[i] = z[np.argmin(np.abs(x - xb))]
    return eta_a, eta_b


def main():
    global T, h
    if len(sys.argv) > 1:
        os.chdir(sys.argv[1])
    T = read_inlet("period", T)
    h = read_inlet("depth", h)
    print(f"T = {T}, h = {h}")

    L = solve_dispersion_equation(h, T, 1)
    print(f"L/4 = {L / 4:.6f}")

    files = sorted(glob.glob("fs/fs*"))
    nt = len(files)
    ntar = np.arange(nt) * dt     # MATLAB's ntar(1:nt), i.e. time of file i is (i-1)*dt

    eta1, eta2 = gauge(files, x1, x2)
    eta3, eta4 = gauge(files, x3, x4)

    # drop empty readings, then spline back onto the full time base
    series = []
    for eta in (eta1, eta2, eta3, eta4):
        keep = np.abs(eta) > tol
        series.append((ntar[keep], eta[keep]))

    ylims = 0.08
    for (a, bb), name in (((0, 1), "filter_fs_x12.png"), ((2, 3), "filter_fs_x34.png")):
        plt.figure()
        plt.plot(*series[a])
        plt.plot(*series[bb])
        plt.ylim(-ylims, ylims)
        plt.savefig(name, dpi=150, bbox_inches="tight")
        plt.close()

    eta1fi, eta2fi, eta3fi, eta4fi = (CubicSpline(t, e)(ntar) for t, e in series)

    m = t1 / T
    D12 = x2 - x1
    D34 = x4 - x3

    print("Conducting wave separation with data fitting and Goda 2-point separation method...")
    Ai12, Ar12, Cr12 = wave_separation(ntar, eta1fi, eta2fi, D12, m, m, T, h, "separation_x12.png")
    Ai34, Ar34, Cr34 = wave_separation(ntar, eta3fi, eta4fi, D34, m, m, T, h, "separation_x34.png")

    Cr = np.mean(Ar12) / np.mean(Ai12)
    Ct = np.mean(Ai34) / np.mean(Ai12)
    ai = np.mean(Ai12)
    print(f"ai = {ai:.6f}")

    Cl = 1 - Cr ** 2 - Ct ** 2
    Cln = Cl / (2 * np.pi / L * ai) ** (2 / 3)
    bL = b / L
    dL = d / L

    fname = f"outparams_T{T:.2f}.txt"
    with open(fname, "w") as f:
        f.write("T\tL\tai\tCr\tCt\tCL\tCLn\tb/L\td/L\n")
        f.write("\t".join(f"{v:12.6f}" for v in (T, L, ai, Cr, Ct, Cl, Cln, bL, dL)) + "\n")
    print(open(fname).read())


if __name__ == "__main__":
    main()
