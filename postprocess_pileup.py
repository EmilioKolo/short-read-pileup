#!/usr/bin/env python3

import argparse
import pysam
import sys


DEPTH_CUTOFF = 10


def main():
    # Initialise argument parser
    p = argparse.ArgumentParser()
    # Get arguments into parser
    p.add_argument('--pileup', required=True)
    p.add_argument('--outdir', required=True)
    p.add_argument('--basename', required=False, default='sample')
    args = p.parse_args()

    # Go through pileup
    counts = 0
    with open(args.pileup) as fh:
        for _ in fh:
            counts += 1
    # Save counts to output file
    with open(f"{args.outdir}/{args.basename}.pileup_summary.txt", 'w') as out:
        out.write(f"lines_in_pileup\t{counts}\n")
    
    # Perform custom variant filtering
    custom_variant_filter(
        pileup_file=args.pileup,
        min_reads_N=20,
        output_file=f"{args.outdir}/{args.basename}.filtered_pileup.txt"
    )


def custom_variant_filter(pileup_file, min_reads_N, output_file):
    """
    Filters pileup records based on minimum read depth for an alternate 
    allele and annotates the variant fraction.
    
    Args:
        pileup_file (str): Path to the input pileup file
        min_reads_N (int): Minimum number of reads to call an ALT allele
        output_file (str): Path to the output annotated file
    """
    
    try:
        # Open the pileup file for reading
        pileup_in = pysam.VariantFile(pileup_file, 'r')
    except Exception as e:
        print(f"Error opening VCF file: {e}", file=sys.stderr)
        return
    
    # Open output file once
    with open(output_file, 'w') as out_fh:
        out_fh.write("CHROM\tPOS\tREF\tALT\tDP_Total\tDP_Alt\tFraction\n")

        for record in pileup_in:
            # Skip records without required info
            if 'I16' not in record.info or 'DP' not in record.info:
                continue

            chrom = record.chrom
            pos = record.pos
            ref = record.ref
            alts = ",".join(record.alts) if record.alts else "."
            total_depth = record.info['DP']
            i16_values = record.info['I16']
        
            if total_depth <= DEPTH_CUTOFF:
                continue

            ref_depth = i16_values[0] + i16_values[1]
            alt_depth = i16_values[2] + i16_values[3]

            if total_depth < (ref_depth + alt_depth):
                print(f"Warning: Depth mismatch: DP={total_depth} vs REF+ALT={ref_depth + alt_depth}", file=sys.stderr)
            
            # Apply Custom Filter (N reads)
            if alt_depth >= min_reads_N:
                used_depth = max(total_depth, (ref_depth + alt_depth))
                # Calculate Fraction
                fraction = alt_depth / used_depth if used_depth > 0 else 0.0
                
                # Output the Annotated Variant
                with open(output_file, 'a+') as out_fh:
                    out_fh.write(f"{chrom}\t{pos}\t{ref}\t{alts}\t{total_depth}\t{alt_depth}\t{fraction:.4f}\n")

    pileup_in.close()


if __name__ == '__main__':
    main()
