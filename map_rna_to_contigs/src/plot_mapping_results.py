#!/usr/bin/env python3
"""Generate per-sample plots from MMseqs2 alignment TSVs.

Produces:
- similarity threshold (x) vs mapped reads (y)
- similarity (pident) histogram
- optional coverage histogram (if coverage column present)

Place plots under `output/plots` by default.
"""

## Run from root directory with: python3 src/plot_mapping_results.py --mapping-dir output/mapping_results --plots-dir output/plots
from __future__ import annotations

import argparse
import os
import re
from pathlib import Path
from typing import Iterable, List, Optional

import matplotlib.pyplot as plt
import numpy as np
from tqdm import tqdm


def parse_alignments(path: Path):
    """Parse pident values and attempt to extract coverage from target string.

    Returns (pidents, coverages) where coverages may be empty if not found.
    """
    pidents: List[float] = []
    coverages: List[float] = []
    depth_re = re.compile(r"depth-([0-9]+(?:-[0-9]+)*)")
    with path.open("r") as fh:
        for line in tqdm(fh, desc=f"Reading {path.name}", unit="lines"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 3:
                continue
            # parse pident
            try:
                p = float(parts[2])
            except Exception:
                continue
            pidents.append(p)

            # try extract coverage from target field (parts[1])
            target = parts[1] if len(parts) > 1 else ""
            m = depth_re.search(target)
            if m:
                nums = [int(x) for x in m.group(1).split("-") if x.isdigit()]
                if nums:
                    # use mean of reported depths as proxy coverage
                    cov = float(sum(nums)) / len(nums)
                    coverages.append(cov)
    return pidents, coverages


# maybe_extract_coverage no longer needed; coverage parsed from target string by parse_alignments


def plot_similarity_curve(pidents: np.ndarray, total_reads: Optional[int], outpath: Path) -> None:
    # thresholds 0..100
    thresholds = np.arange(0, 101)
    counts = np.array([(pidents >= t).sum() for t in thresholds])
    # ensure no zeros for plotting on log scale
    counts_plot = np.maximum(counts, 1)
    fig, ax = plt.subplots(figsize=(4, 3))
    ax.step(thresholds, counts_plot, where="post")
    ax.set_xlabel("Similarity (percent identity)")
    ax.set_ylabel("Mapped reads")
    ax.set_yscale("log")
    # set y-limits to focus view: bottom = one-tenth of smallest non-zero count
    nonzero = counts[counts > 0]
    if nonzero.size > 0:
        ymin = max(1.0, float(nonzero.min()) / 10.0)
        ymax = float(counts.max()) * 1.1
        ax.set_ylim(bottom=ymin, top=ymax)
    else:
        ax.set_ylim(bottom=1)
    # remove top and right spines
    ax.spines["right"].set_visible(False)
    ax.spines["top"].set_visible(False)
    fig.tight_layout()
    fig.savefig(outpath, dpi=150)
    plt.close(fig)


def plot_histogram(data: np.ndarray, xlabel: str, outpath: Path, bins: int = 50) -> None:
    fig, ax = plt.subplots(figsize=(4, 3))
    counts, edges = np.histogram(data, bins=bins)
    ax.bar(edges[:-1], counts, width=np.diff(edges), align='edge', edgecolor='white')
    ax.set_xlabel(xlabel)
    ax.set_ylabel("Count")
    ax.set_yscale("log")
    nonzero = counts[counts > 0]
    if nonzero.size > 0:
        ymin = max(1.0, float(nonzero.min()) / 10.0)
        ymax = float(counts.max()) * 1.1
        ax.set_ylim(bottom=ymin, top=ymax)
    else:
        ax.set_ylim(bottom=1)
    ax.spines["right"].set_visible(False)
    ax.spines["top"].set_visible(False)
    fig.tight_layout()
    fig.savefig(outpath, dpi=150)
    plt.close(fig)


def find_total_reads(mapping_dir: Path, sample_name: str) -> Optional[int]:
    # Accept a companion file {sample}_total_reads.txt if present
    f = mapping_dir / f"{sample_name}_total_reads.txt"
    if f.exists():
        try:
            return int(f.read_text().strip())
        except Exception:
            return None
    return None


def main(argv: Optional[List[str]] = None) -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--mapping-dir", default="output/mapping_results", help="directory with *_alignments.tsv files")
    p.add_argument("--plots-dir", default="output/plots", help="directory to write plots")
    p.add_argument("--min-mapped", type=int, default=1, help="skip samples with fewer mapped reads than this")
    args = p.parse_args(argv)

    mapping_dir = Path(args.mapping_dir)
    plots_dir = Path(args.plots_dir)
    plots_dir.mkdir(parents=True, exist_ok=True)

    files = sorted(mapping_dir.glob("*_alignments.tsv"))
    if not files:
        print(f"No alignment files found in {mapping_dir}")
        return

    for path in files:
        sample = path.name.replace("_alignments.tsv", "")
        pidents, covs = parse_alignments(path)
        if not pidents:
            print(f"No pident values for {sample}, skipping")
            continue
        pidents_arr = np.array(pidents)

        total_reads = find_total_reads(mapping_dir, sample)

        if pidents_arr.size < args.min_mapped:
            print(f"Sample {sample} has only {pidents_arr.size} mapped reads, skipping")
            continue

        # similarity threshold curve (absolute counts)
        out_curve = plots_dir / f"{sample}_similarity_vs_mapped.png"
        plot_similarity_curve(pidents_arr, total_reads, out_curve)

        # similarity histogram
        out_hist = plots_dir / f"{sample}_pident_hist.png"
        plot_histogram(pidents_arr, "Percent identity (pident)", out_hist, bins=50)

        # coverage histogram if coverage info extracted from target names
        if covs:
            cov_arr = np.array(covs)
            out_cov = plots_dir / f"{sample}_coverage_hist.png"
            plot_histogram(cov_arr, "Coverage (mean depth)", out_cov, bins=50)

        print(f"Wrote plots for {sample} → {plots_dir}")


if __name__ == "__main__":
    main()
