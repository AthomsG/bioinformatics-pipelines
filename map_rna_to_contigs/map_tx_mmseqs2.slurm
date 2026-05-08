#!/bin/bash
#SBATCH --job-name=mmseqs_master
#SBATCH --time=00:10:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G

###############################################################################
# MASTER ORCHESTRATOR: MMseqs2 Gene Clustering & Transcriptomics Mapping
###############################################################################
# Orchestrates all stages sequentially with SLURM dependencies:
# Stage 1: Gene Prediction (Prodigal) - parallelized
# Stage 2: Build Shared Cluster Database - sequential (after Stage 1)
# Stage 3: Map Reads to Clusters - parallelized (after Stage 2)
###############################################################################

set -euo pipefail

log() {
    echo "[$(date '+%F %T')] $*"
}

PROJECT_ROOT="${SLURM_SUBMIT_DIR:-$(pwd)}"
SRC_DIR="${PROJECT_ROOT}/src"
TAR_FILE="/lisc/data/work/dome/pollak/liors/data/challenges/JMF-2508-04/JMF-2508-04_reads.tar.gz"

log "Inspecting ${TAR_FILE} for Metatranscriptomic Samples"

RNA_SAMPLE_COUNT=$(tar -tzf "${TAR_FILE}" | grep -c 'QC.interleave.fastq.gz')

mkdir -p "${PROJECT_ROOT}/logs" \
    "${PROJECT_ROOT}/output/mmseqs_clustering/genes" \
    "${PROJECT_ROOT}/output/mmseqs_clustering/shared_db" \
    "${PROJECT_ROOT}/output/mapping_results"

log "Starting Master Orchestrator for MMseqs2 Workflow"

###############################################################################
# STAGE 1: Gene Prediction using Prodigal (parallelized across samples)
###############################################################################

log "Submitting Stage 1: Gene Prediction (Prodigal)..."

STAGE1_JOB=$(sbatch \
    --job-name="stage1_prodigal" \
    --output="${PROJECT_ROOT}/logs/stage1_%j.out" \
    --error="${PROJECT_ROOT}/logs/stage1_%j.err" \
    --time=02:00:00 \
    --cpus-per-task=1 \
    --mem=4G \
    --array=0-9 \
    "${SRC_DIR}/01_predict_genes.sh" \
    | awk '{print $NF}')

log "Stage 1 Job ID: ${STAGE1_JOB}"

###############################################################################
# STAGE 2: Build MMseqs2 Cluster Database (depends on Stage 1)
###############################################################################

log "Submitting Stage 2: Build Cluster Database..."

# Add for full pipeline: 
# --dependency=afterok:${STAGE1_JOB} \
STAGE2_JOB=$(sbatch \
    --job-name="stage2_clustering" \
    --output="${PROJECT_ROOT}/logs/stage2_%j.out" \
    --error="${PROJECT_ROOT}/logs/stage2_%j.err" \
    --time=00:15:00 \
    --cpus-per-task=8 \
    --mem=16G \
    "${SRC_DIR}/02_build_clusters.sh" \
    | awk '{print $NF}')

log "Stage 2 Job ID: ${STAGE2_JOB} (depends on Stage 1: ${STAGE1_JOB})"

###############################################################################
# STAGE 3: Map Reads to Clusters (depends on Stage 2)
###############################################################################

log "Submitting Stage 3: Map Reads and Generate Statistics..."

# Array job for all metatranscriptomic samples in the tar
STAGE3_JOB=$(sbatch \
    --job-name="stage3_mapping" \
    --output="${PROJECT_ROOT}/logs/stage3_%A_%a.out" \
    --error="${PROJECT_ROOT}/logs/stage3_%A_%a.err" \
    --dependency=afterok:${STAGE2_JOB} \
    --time=10:00:00 \
    --cpus-per-task=8 \
    --mem=32G \
    --array=0-$((RNA_SAMPLE_COUNT - 1)) \
    "${SRC_DIR}/03_map_and_stats.sh" \
    | awk '{print $NF}')

log "Stage 3 Job ID: ${STAGE3_JOB} (depends on Stage 2: ${STAGE2_JOB})"

###############################################################################
# Summary
###############################################################################

log ""
log "Workflow submitted successfully!"
log "Job dependencies:"
log "  Stage 1 (Prodigal):       ${STAGE1_JOB}"
log "  Stage 2 (Clustering):     ${STAGE2_JOB} → depends on Stage 1"
log "  Stage 3 (Mapping):        ${STAGE3_JOB} → depends on Stage 2"
log ""
log "Monitor progress with:"
log "  squeue -u \$USER"
log "  tail -f ${PROJECT_ROOT}/logs/stage*.out"
log ""