# MMseqs2 Workflow Scripts

## Overview
Four scripts orchestrate the MMseqs2 gene clustering and transcriptomics mapping workflow:

### 1. `phase1_predict_genes.sh`
**Purpose**: Predict open reading frames (ORFs) from all 10 contig assemblies using Prodigal  
**Input**: `assembly_primary.fa` from each sample in `../myloasm_assemblies/`  
**Output**: Protein FASTA files (`.genes.faa`) to `../output/mmseqs_clustering/genes/`  
**Called by**: Master SLURM script

### 2. `phase2_build_clusters.sh`
**Purpose**: Build a shared MMseqs2 cluster database from all predicted genes  
**Input**: All `.genes.faa` files from Phase 1  
**Process**:
  - Concatenate all protein sequences into single FASTA
  - Create MMseqs2 database
  - Cluster at 90% sequence identity
  - Extract and index cluster representatives  
**Output**: 
  - `all_genes.faa` — concatenated proteins
  - `all_genes_clustered/` — MMseqs2 cluster database
  - `cluster_rep_db/` — indexed representative sequences
  - `cluster_rep.fa` — FASTA of representatives  
**Output location**: `../output/mmseqs_clustering/shared_db/`  
**Called by**: Master SLURM script (depends on Phase 1)

### 3. `phase3_4_map_and_stats.sh`
**Purpose**: Map RNA reads to cluster database and generate per-sample statistics  
**Input**:
  - RNA reads from tar file: `/lisc/data/work/dome/pollak/liors/data/challenges/JMF-2508-04/JMF-2508-04_reads.tar.gz`
  - Cluster database from Phase 2  
**Process**:
  - Extract RNA reads for one sample from tar archive
  - Convert FASTQ to FASTA
  - Create MMseqs2 database from reads
  - Search reads against cluster representatives
  - Extract per-read alignment details (identity %, E-value, etc.)
  - Parse results and calculate statistics  
**Output**: Per-sample TSV file with mapping statistics  
**Output location**: `../output/mapping_results/{SAMPLE}_mapping_stats.tsv`  
**Called by**: Master SLURM script as array job (indices 0-9, depends on Phase 2)  
**Parameters**: 
  - `$1` — SAMPLE_IDX: array index (0-9) for which sample to process

### 4. `parse_mmseqs_output.py`
**Purpose**: Parse MMseqs2 alignment TSV and calculate mapping statistics  
**Input**: MMseqs2 alignment file with per-read similarity scores  
**Output**: Statistics TSV with:
  - `sample_name` — RNA sample identifier
  - `total_reads` — total number of reads
  - `mapped_reads` — reads with at least one match
  - `percent_mapped` — percentage of reads mapped (%)
  - `avg_similarity` — average percent identity (0–1)
  - `min_similarity` — minimum percent identity observed
  - `max_similarity` — maximum percent identity observed
  - `num_alignments` — total number of alignments found  
**Called by**: `phase3_4_map_and_stats.sh`  
**Parameters**:
  - `--alignments FILE` — MMseqs2 alignment TSV output
  - `--total-reads N` — total number of reads in sample
  - `--output FILE` — output statistics file
  - `--sample-name STR` — sample identifier for output

## Execution Flow

```
Master SLURM Script (map_tx_mmseqs2.slurm)
  │
  ├─→ Phase 1: Prodigal (parallel on all samples)
  │   └─ Outputs: *.genes.faa in output/mmseqs_clustering/genes/
  │
  ├─→ Phase 2: Build Clusters (sequential, waits for Phase 1)
  │   ├─ Concatenate genes
  │   ├─ Cluster at 90% identity
  │   └─ Outputs: cluster DB in output/mmseqs_clustering/shared_db/
  │
  └─→ Phase 3+4: Map & Stats (parallel array job 0-9, waits for Phase 2)
      ├─ Map each sample's reads to cluster DB
      ├─ Calculate similarity distribution
      └─ Outputs: *.mapping_stats.tsv in output/mapping_results/
```

## Key Features

- **Modularity**: Each phase is a standalone bash script
- **Parallelization**: Phase 1 and Phase 3+4 run in parallel; Phase 2 is sequential
- **SLURM Dependencies**: Master script uses `--dependency=afterok` to chain jobs
- **Logging**: Each phase logs to separate files for troubleshooting
- **Cleanup**: Temporary files automatically removed after each sample
- **Statistics**: Per-sample similarity and mapping metrics extracted for plotting
