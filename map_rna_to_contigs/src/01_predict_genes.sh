#!/bin/bash

###############################################################################
# PHASE 1: Gene Prediction from Contigs using Prodigal
###############################################################################
# Predicts open reading frames (ORFs) from all contig assemblies
# Input: assembly_primary.fa from each sample
# Output: .genes.faa (protein sequences) to output/mmseqs_clustering/genes/
###############################################################################

set -euo pipefail

log() {
    echo "[$(date '+%F %T')] $*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SLURM_SUBMIT_DIR:-$(dirname "$SCRIPT_DIR")}" 
ASSEMBLY_BASE="${PROJECT_ROOT}/../myloasm_assemblies"
OUTPUT_GENES="${PROJECT_ROOT}/output/mmseqs_clustering/genes"

TASK_ID="${SLURM_ARRAY_TASK_ID:-}"

mkdir -p "${OUTPUT_GENES}" "${PROJECT_ROOT}/logs"

module load prodigal/2.6.3-GCCcore-14.2.0

if [ -z "${TASK_ID}" ]; then
    log "ERROR: Phase 1 must run as a SLURM array job"
    exit 1
fi

log "Starting Phase 1: Gene Prediction (task ${TASK_ID})"

###############################################################################
# Find all assemblies and run Prodigal in parallel
###############################################################################

mapfile -t DNA_DIRS < <(
    find "${ASSEMBLY_BASE}" -maxdepth 1 -mindepth 1 -type d -name "JMF-2508-04-*B-ONT" | sort
)

DNA_DIR="${DNA_DIRS[$TASK_ID]}"
DNA_SAMPLE="$(basename "${DNA_DIR}")"
ASSEMBLY="${DNA_DIR}/assembly_primary.fa"
OUTPUT_FAA="${OUTPUT_GENES}/${DNA_SAMPLE}.genes.faa"

if [ ! -f "${ASSEMBLY}" ]; then
    log "ERROR: Assembly not found at ${ASSEMBLY}"
    exit 1
fi

if [ -f "${OUTPUT_FAA}" ]; then
    log "Already exists: ${OUTPUT_FAA}"
    exit 0
fi

log "Processing ${DNA_SAMPLE}..."
prodigal -i "${ASSEMBLY}" -a "${OUTPUT_FAA}" -p meta > /dev/null 2>&1
log "  Completed: ${OUTPUT_FAA}"
log "Phase 1 COMPLETE for task ${TASK_ID}"
