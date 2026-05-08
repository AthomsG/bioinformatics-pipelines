#!/bin/bash

###############################################################################
# STAGE 2: Build Shared MMseqs2 Cluster Database
###############################################################################
# Concatenates all predicted genes and creates a shared cluster database
# Input: .genes.faa files from Stage 1
# Output: MMseqs2 database and cluster representatives
###############################################################################

set -euo pipefail

log() {
    echo "[$(date '+%F %T')] $*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SLURM_SUBMIT_DIR:-$(dirname "$SCRIPT_DIR")}" 
OUTPUT_GENES="${PROJECT_ROOT}/output/mmseqs_clustering/genes"
SHARED_DB="${PROJECT_ROOT}/output/mmseqs_clustering/shared_db"
TMP_DIR="${PROJECT_ROOT}/output/mmseqs_clustering/.tmp"

mkdir -p "${SHARED_DB}" "${TMP_DIR}"

module load MMseqs2/18-8cc5c-gompi-2025b

log "Starting Stage 2: Build MMseqs2 Cluster Database"

###############################################################################
# Concatenate all predicted genes into single FASTA file
###############################################################################

ALL_GENES_FASTA="${SHARED_DB}/all_genes.faa"

if [ -f "${ALL_GENES_FASTA}" ]; then
    log "Using existing concatenated genes file: ${ALL_GENES_FASTA}"
else
    log "Concatenating all gene predictions..."
    cat "${OUTPUT_GENES}"/*.genes.faa > "${ALL_GENES_FASTA}"
    log "  Created: ${ALL_GENES_FASTA}"
fi

###############################################################################
# Create MMseqs2 database
###############################################################################

DB_NAME="${SHARED_DB}/all_genes_db"

if [ -f "${DB_NAME}.dbtype" ]; then
    log "MMseqs2 database already exists"
else
    log "Creating MMseqs2 database from concatenated genes..."
    mmseqs createdb "${ALL_GENES_FASTA}" "${DB_NAME}"
    log "  Created database: ${DB_NAME}"
fi

###############################################################################
# Cluster at 90% identity
###############################################################################

CLUSTER_DB="${SHARED_DB}/all_genes_clustered"

if [ -f "${CLUSTER_DB}.dbtype" ]; then
    log "Cluster database already exists"
else
    log "Clustering sequences at 90% identity..."
    mmseqs cluster "${DB_NAME}" "${CLUSTER_DB}" "${TMP_DIR}" \
        --min-seq-id 0.9 \
        --cov-mode 1 \
        -c 0.8
    log "  Created cluster database: ${CLUSTER_DB}"
fi

###############################################################################
# Create representative sequence database from clustering
###############################################################################

CLUSTER_REP_DB="${SHARED_DB}/cluster_rep_db"

if [ -f "${CLUSTER_REP_DB}.dbtype" ]; then
    log "Cluster representative database already exists"
else
    log "Creating representative sequence database from clustering results..."
    mmseqs result2repseq "${DB_NAME}" "${CLUSTER_DB}" "${CLUSTER_REP_DB}"
    log "  Created database: ${CLUSTER_REP_DB}"
fi

###############################################################################
# Create index for faster searching
###############################################################################

log "Creating index for cluster representative database..."
mmseqs createindex "${CLUSTER_REP_DB}" "${TMP_DIR}"

rm -rf "${TMP_DIR}"

log "Stage 2 COMPLETE: Shared cluster database built"
