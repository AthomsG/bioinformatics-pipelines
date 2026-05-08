#!/bin/bash
#SBATCH --job-name=mmseqs_master
#SBATCH --time=00:10:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G

###############################################################################
# MASTER ORCHESTRATOR: MMseqs2 Gene Clustering & Transcriptomics Mapping
###############################################################################
# Orchestrates all phases sequentially with SLURM dependencies:
# Phase 1: Gene Prediction (Prodigal) - parallelized
# Phase 2: Build Shared Cluster Database - sequential (after Phase 1)
# Phase 3+4: Map Reads to Clusters - parallelized (after Phase 2)
###############################################################################

set -euo pipefail

log() {
    echo "[$(date '+%F %T')] $*"
}

PROJECT_ROOT="${SLURM_SUBMIT_DIR:-$(pwd)}"
SRC_DIR="${PROJECT_ROOT}/src"

mkdir -p "${PROJECT_ROOT}/logs" \
    "${PROJECT_ROOT}/output/mmseqs_clustering/genes" \
    "${PROJECT_ROOT}/output/mmseqs_clustering/shared_db" \
    "${PROJECT_ROOT}/output/mapping_results"

log "Starting Master Orchestrator for MMseqs2 Workflow"

###############################################################################
# PHASE 1: Gene Prediction using Prodigal (parallelized across 10 samples)
# COMMENTED OUT - phase 1 already completed
###############################################################################

# log "Submitting Phase 1: Gene Prediction (Prodigal)..."
# 
# PHASE1_JOB=$(sbatch \
#     --job-name="phase1_prodigal" \
#     --output="${PROJECT_ROOT}/logs/phase1_%j.out" \
#     --error="${PROJECT_ROOT}/logs/phase1_%j.err" \
#     --time=02:00:00 \
#     --cpus-per-task=1 \
#     --mem=4G \
#     --array=0-9 \
#     "${SRC_DIR}/01_predict_genes.sh" \
#     | awk '{print $NF}')
# 
# log "Phase 1 Job ID: ${PHASE1_JOB}"

# Phase 1 skipped in this run. Comment if running phase 1
PHASE1_JOB="skipped"

###############################################################################
# PHASE 2: Build MMseqs2 Cluster Database (sequential, depends on Phase 1)
###############################################################################

log "Submitting Phase 2: Build Cluster Database..."

# Add for full pipeline: 
# --dependency=afterok:${PHASE1_JOB} \
PHASE2_JOB=$(sbatch \
    --job-name="phase2_clustering" \
    --output="${PROJECT_ROOT}/logs/phase2_%j.out" \
    --error="${PROJECT_ROOT}/logs/phase2_%j.err" \
    --time=00:15:00 \
    --cpus-per-task=8 \
    --mem=16G \
    "${SRC_DIR}/02_build_clusters.sh" \
    | awk '{print $NF}')

log "Phase 2 Job ID: ${PHASE2_JOB} (depends on Phase 1: ${PHASE1_JOB})"

###############################################################################
# PHASE 3: Map Reads to Clusters (parallelized, depends on Phase 2)
###############################################################################

log "Submitting Phase 3: Map Reads and Generate Statistics..."

# Array job for 10 samples (indices 0-9)
PHASE3_JOB=$(sbatch \
    --job-name="phase3_mapping" \
    --output="${PROJECT_ROOT}/logs/phase3_%A_%a.out" \
    --error="${PROJECT_ROOT}/logs/phase3_%A_%a.err" \
    --dependency=afterok:${PHASE2_JOB} \
    --time=10:00:00 \
    --cpus-per-task=8 \
    --mem=32G \
    --array=0-9 \
    "${SRC_DIR}/03_map_and_stats.sh" \
    | awk '{print $NF}')

log "Phase 3 Job ID: ${PHASE3_JOB} (depends on Phase 2: ${PHASE2_JOB})"

###############################################################################
# Summary
###############################################################################

log ""
log "Workflow submitted successfully!"
log "Job dependencies:"
log "  Phase 1 (Prodigal):       ${PHASE1_JOB}"
log "  Phase 2 (Clustering):     ${PHASE2_JOB} → depends on Phase 1"
log "  Phase 3 (Mapping):        ${PHASE3_JOB} → depends on Phase 2"
log ""
log "Monitor progress with:"
log "  squeue -u \$USER"
log "  tail -f ${PROJECT_ROOT}/logs/phase*.out"
log ""