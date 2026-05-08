#!/bin/bash

###############################################################################
# STAGE 3: Map Reads to Clusters and Generate Statistics
###############################################################################
# For each sample: extracts RNA reads, maps to cluster database,
# and calculates per-read similarity scores and mapping statistics
# Input: MMseqs2 cluster database, RNA reads from tar file
# Output: Per-sample mapping statistics TSV
###############################################################################

set -euo pipefail

log() {
    echo "[$(date '+%F %T')] $*"
}

# Get parameters (prefer CLI arg, fall back to SLURM array ID)
SAMPLE_IDX="${1:-${SLURM_ARRAY_TASK_ID:-}}"
if [ -z "${SAMPLE_IDX}" ]; then
    log "ERROR: Must provide SAMPLE_IDX as first argument or set SLURM_ARRAY_TASK_ID"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SLURM_SUBMIT_DIR:-$(dirname "$SCRIPT_DIR")}" 
TAR_FILE="/lisc/data/work/dome/pollak/liors/data/challenges/JMF-2508-04/JMF-2508-04_reads.tar.gz"
SHARED_DB="${PROJECT_ROOT}/output/mmseqs_clustering/shared_db"
MAPPING_RESULTS="${PROJECT_ROOT}/output/mapping_results"
TMP_DIR="${PROJECT_ROOT}/output/.tmp_${SAMPLE_IDX}"

mkdir -p "${MAPPING_RESULTS}" "${TMP_DIR}"

module load MMseqs2/18-8cc5c-gompi-2025b
module load seqtk/1.5-GCC-14.3.0

log "Starting Stage 3: Map Reads and Generate Statistics (Sample ${SAMPLE_IDX})"

###############################################################################
# Get sample information
###############################################################################

mapfile -t RNA_SAMPLES < <(
    tar -tzf "${TAR_FILE}" \
        | grep 'QC.interleave.fastq.gz' \
        | sed 's#.*/##' \
        | sed 's/\.QC.interleave.fastq.gz$//' \
        | sort -u
)

RNA_SAMPLE="${RNA_SAMPLES[$SAMPLE_IDX]}"

INNER="JMF-2508-04_reads/${RNA_SAMPLE}.QC.interleave.fastq.gz"
RNA_FASTA="${TMP_DIR}/${RNA_SAMPLE}.fa"
RNA_DB="${TMP_DIR}/${RNA_SAMPLE}_db"
SEARCH_RESULTS="${TMP_DIR}/${RNA_SAMPLE}_search_results"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

log "RNA Sample: ${RNA_SAMPLE}"
log "Total RNA samples available: ${#RNA_SAMPLES[@]}"

###############################################################################
# Extract and convert RNA reads to FASTA
###############################################################################

log "Extracting RNA reads from tar..."
if command -v seqtk >/dev/null 2>&1; then
    log "Using seqtk for FASTQ to FASTA conversion"
    tar -xOzf "${TAR_FILE}" "${INNER}" | zcat | seqtk seq -A > "${RNA_FASTA}" 2>/dev/null || {
        log "ERROR: Could not extract or convert reads"
        exit 1
    }
else
    log "seqtk not found; using awk for FASTQ to FASTA conversion"
    tar -xOzf "${TAR_FILE}" "${INNER}" | zcat | awk 'NR%4==1{print ">" substr($0,2)} NR%4==2{print}' > "${RNA_FASTA}" 2>/dev/null || {
        log "ERROR: Could not extract or convert reads"
        exit 1
    }
fi

TOTAL_READS=$(grep -c "^>" "${RNA_FASTA}" || echo 0)
log "  Extracted ${TOTAL_READS} reads"

###############################################################################
# Create MMseqs2 database from RNA reads
###############################################################################

log "Creating MMseqs2 database from reads..."
mmseqs createdb "${RNA_FASTA}" "${RNA_DB}"

###############################################################################
# Search reads against cluster representative database
###############################################################################

CLUSTER_REP_DB="${SHARED_DB}/cluster_rep_db"

log "Mapping reads to cluster representative database..."
mmseqs search "${RNA_DB}" "${CLUSTER_REP_DB}" "${SEARCH_RESULTS}" "${TMP_DIR}" \
    --max-seqs 1 \
    --alignment-mode 2 \
    -e 0.001

###############################################################################
# Convert search results to TSV with alignment details
###############################################################################

log "Extracting alignment details..."
mmseqs convertalis "${RNA_DB}" "${CLUSTER_REP_DB}" "${SEARCH_RESULTS}" "${MAPPING_RESULTS}/${RNA_SAMPLE}_alignments.tsv" \
    --format-output "query,target,pident,nident,mismatch,gapopen,evalue,bits"

log "Stage 3 COMPLETE for ${RNA_SAMPLE}"
log "  Alignments saved to: ${MAPPING_RESULTS}/${RNA_SAMPLE}_alignments.tsv"