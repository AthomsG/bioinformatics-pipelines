#!/usr/bin/env python3

###############################################################################
# HELPER: Parse MMseqs2 Alignment Output and Generate Statistics
###############################################################################
# Extracts per-read similarity scores from MMseqs2 search results
# and calculates mapping statistics
# Output: TSV with columns: sample_name, similarity_score, percent_mapped
###############################################################################

import argparse
import sys
from collections import defaultdict


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Parse MMseqs2 alignment output and generate statistics"
    )
    parser.add_argument(
        "--alignments",
        required=True,
        help="MMseqs2 alignment TSV file"
    )
    parser.add_argument(
        "--total-reads",
        type=int,
        required=True,
        help="Total number of reads in the sample"
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output statistics TSV file"
    )
    parser.add_argument(
        "--sample-name",
        required=True,
        help="Sample name for output"
    )
    return parser.parse_args()


def parse_alignments(alignments_file):
    """
    Parse MMseqs2 alignment TSV file.
    Expected columns: query, target, pident, nident, mismatch, gapopen, 
                      gapext, evalue, bits
    Returns: list of (query_id, pident) tuples where pident is percent identity
    """
    alignments = []
    try:
        with open(alignments_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                fields = line.split('\t')
                if len(fields) >= 3:
                    query = fields[0]
                    # pident is percent identity (0-100)
                    try:
                        pident = float(fields[2]) / 100.0  # Convert to 0-1 range
                        alignments.append((query, pident))
                    except ValueError:
                        continue
    except FileNotFoundError:
        print(f"ERROR: Alignment file not found: {alignments_file}", file=sys.stderr)
        sys.exit(1)
    
    return alignments


def calculate_statistics(alignments, total_reads):
    """
    Calculate mapping statistics.
    Returns: dict with stats
    """
    # Count unique mapped reads
    mapped_reads = set(query for query, _ in alignments)
    num_mapped = len(mapped_reads)
    
    # Calculate percent mapped
    percent_mapped = (num_mapped / total_reads * 100) if total_reads > 0 else 0
    
    # Calculate similarity statistics
    similarities = [pident for _, pident in alignments]
    
    if similarities:
        avg_similarity = sum(similarities) / len(similarities)
        min_similarity = min(similarities)
        max_similarity = max(similarities)
    else:
        avg_similarity = 0
        min_similarity = 0
        max_similarity = 0
    
    return {
        'num_reads': total_reads,
        'num_mapped': num_mapped,
        'percent_mapped': percent_mapped,
        'avg_similarity': avg_similarity,
        'min_similarity': min_similarity,
        'max_similarity': max_similarity,
        'num_alignments': len(alignments)
    }


def write_statistics(output_file, sample_name, stats):
    """
    Write statistics to output TSV file.
    Writes both summary and per-bin similarity data.
    """
    try:
        with open(output_file, 'w') as f:
            # Write header
            f.write("metric\tvalue\n")
            
            # Write summary statistics
            f.write(f"sample_name\t{sample_name}\n")
            f.write(f"total_reads\t{stats['num_reads']}\n")
            f.write(f"mapped_reads\t{stats['num_mapped']}\n")
            f.write(f"percent_mapped\t{stats['percent_mapped']:.2f}\n")
            f.write(f"avg_similarity\t{stats['avg_similarity']:.4f}\n")
            f.write(f"min_similarity\t{stats['min_similarity']:.4f}\n")
            f.write(f"max_similarity\t{stats['max_similarity']:.4f}\n")
            f.write(f"num_alignments\t{stats['num_alignments']}\n")
    except IOError as e:
        print(f"ERROR: Could not write to {output_file}: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    args = parse_arguments()
    
    # Parse alignments
    alignments = parse_alignments(args.alignments)
    
    # Calculate statistics
    stats = calculate_statistics(alignments, args.total_reads)
    
    # Write output
    write_statistics(args.output, args.sample_name, stats)
    
    print(f"Statistics written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
