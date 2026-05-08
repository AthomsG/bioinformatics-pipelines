# MMseqs2 Workflow Scripts

## Overview

This folder contains the scripts for a stage-based MMseqs2 workflow that links metagenomic assemblies to metatranscriptomic reads.

Current data layout:

- 10 metagenomic assemblies in `../myloasm_assemblies/`
- 28 metatranscriptomic samples in `JMF-2508-04_reads.tar.gz`

The workflow is:

1. Predict genes from each metagenomic assembly with Prodigal.
2. Pool all predicted genes and cluster them with MMseqs2.
3. Map every metatranscriptomic sample to the shared cluster representative database.

## Scripts

### 1. `01_predict_genes.sh`

**Stage**: 1  
**Purpose**: Predict open reading frames from each metagenomic assembly with Prodigal.  
**Input**: `assembly_primary.fa` from each directory in `../myloasm_assemblies/`  
**Output**: Protein FASTA files in `../output/mmseqs_clustering/genes/` with the suffix `.genes.faa`  
**Execution**: SLURM array job over the 10 assemblies

### 2. `02_build_clusters.sh`

**Stage**: 2  
**Purpose**: Build a shared MMseqs2 cluster database from all predicted genes.  
**Input**: All `.genes.faa` files from Stage 1  
**Process**:

- concatenate all predicted protein sequences
- create an MMseqs2 database
- cluster sequences at 90% identity
- extract representative sequences with `mmseqs result2repseq`
- create an index for fast searching

**Output**:  
- `all_genes.faa` — concatenated protein FASTA  
- `all_genes_db*` — MMseqs2 database files  
- `all_genes_clustered*` — clustered database files  
- `cluster_rep_db*` — indexed representative-sequence database  

**Output location**: `../output/mmseqs_clustering/shared_db/`

### 3. `03_map_and_stats.sh`

**Stage**: 3  
**Purpose**: Map each metatranscriptomic sample to the cluster representative database.  
**Input**:

- RNA reads from `/lisc/data/work/dome/pollak/liors/data/challenges/JMF-2508-04/JMF-2508-04_reads.tar.gz`
- cluster representative database from Stage 2

**Process**:

- discover all RNA samples in the tar archive
- extract the matching interleaved FASTQ for each sample
- convert reads to FASTA
- create an MMseqs2 database for that sample
- search reads against the shared cluster representative database
- write alignment details with `mmseqs convertalis`

**Output**: Per-sample alignment TSV files  
**Output location**: `../output/mapping_results/{SAMPLE}_alignments.tsv`  
**Execution**: SLURM array job over all RNA samples in the tar

### 4. `plot_mapping_results.py`

**Purpose**: Create per-sample plots from the alignment TSV files.  
**Input**: `../output/mapping_results/*_alignments.tsv`  
**Output**: PNG plots in `../output/plots/`  
**Plots generated**:

- similarity threshold vs mapped reads
- percent identity distribution
- coverage distribution when coverage can be parsed from the target header

## Execution Flow

```text
Master SLURM Script (`map_tx_mmseqs2.slurm`)
  │
  ├─→ Stage 1: Prodigal on all 10 assemblies
  │   └─ Outputs: `../output/mmseqs_clustering/genes/*.genes.faa`
  │
  ├─→ Stage 2: Build shared MMseqs2 cluster database
  │   └─ Outputs: `../output/mmseqs_clustering/shared_db/cluster_rep_db*`
  │
  └─→ Stage 3: Map all 28 RNA samples from the tar archive
      └─ Outputs: `../output/mapping_results/{SAMPLE}_alignments.tsv`
```
