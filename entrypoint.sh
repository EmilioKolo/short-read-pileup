#!/usr/bin/env bash

set -euo pipefail


usage() {
    cat <<'EOF'
Usage: entrypoint.sh -1 <R1.fastq[.gz]> [-2 <R2.fastq[.gz]>] -r <ref.fasta> -a <aligner> -o <outdir> [-t threads]


Aligners supported: bwa, minimap2, star (read lengths must be <= 650 for star)
EOF
}


R1=""; R2=""; REF=""; ALIGNER=""; OUTDIR=""; THREADS=1
while getopts "1:2:r:a:o:t:h" opt; do
    case $opt in
        1) R1=$OPTARG;;
        2) R2=$OPTARG;;
        r) REF=$OPTARG;;
        a) ALIGNER=$OPTARG;;
        o) OUTDIR=$OPTARG;;
        t) THREADS=$OPTARG;;
        h) usage; exit 0;;
        *) usage; exit 1;;
    esac
done


[[ -z "$R1" || -z "$REF" || -z "$ALIGNER" || -z "$OUTDIR" ]] && { usage; exit 2; }
mkdir -p "$OUTDIR" && cd "$OUTDIR"

# Define reference in /tmp for indexing
REFNAME=$(basename "$REF")
cp "$REF" "/tmp/$REFNAME"
samtools faidx "/tmp/$REFNAME"

# Define basename for output files, from R1
BASENAME=$(basename "$R1" | sed 's/_R1.*//;s/\.fastq.*//;s/\.fq.*//')

case "$ALIGNER" in
    bwa)
        bwa index "/tmp/$REFNAME"
        if [[ -z "$R2" ]]; then
            bwa mem -t "$THREADS" "/tmp/$REFNAME" "$R1" | samtools view -bS - > /tmp/$BASENAME.unsorted.bam
        else
            bwa mem -t "$THREADS" "/tmp/$REFNAME" "$R1" "$R2" | samtools view -bS - > /tmp/$BASENAME.unsorted.bam
        fi;;
    minimap2)
        if [[ -z "$R2" ]]; then
            minimap2 -t "$THREADS" -ax sr --secondary=no --sam-hit-only "/tmp/$REFNAME" "$R1" | samtools view -bS - > /tmp/$BASENAME.unsorted.bam
        else
            minimap2 -t "$THREADS" -ax sr --secondary=no --sam-hit-only "/tmp/$REFNAME" "$R1" "$R2" | samtools view -bS - > /tmp/$BASENAME.unsorted.bam
        fi;;
    star)
        mkdir -p /tmp/star_index
        STAR --runThreadN "$THREADS" --runMode genomeGenerate --genomeDir /tmp/star_index --genomeFastaFiles "/tmp/$REFNAME"
        if [[ -z "$R2" ]]; then
            STAR --runThreadN "$THREADS" --genomeDir /tmp/star_index --readFilesIn "$R1" --outFileNamePrefix intermediate/star_ --outSAMtype BAM Unsorted
        else
            STAR --runThreadN "$THREADS" --genomeDir /tmp/star_index --readFilesIn "$R1" "$R2" --outFileNamePrefix intermediate/star_ --outSAMtype BAM Unsorted
        fi
        mv star_Aligned.out.bam /tmp/$BASENAME.unsorted.bam;;
    *) echo "Unsupported aligner: $ALIGNER" >&2; exit 3;;
esac

# Make directories for stats, qc and intermediate files
mkdir -p "$OUTDIR"/stats
mkdir -p "$OUTDIR"/qc
mkdir -p "$OUTDIR"/intermediate

# sort, index, and move outputs into output directory
samtools sort -@ "$THREADS" -o "$OUTDIR"/intermediate/$BASENAME.sorted.bam /tmp/$BASENAME.unsorted.bam
samtools index "$OUTDIR"/intermediate/$BASENAME.sorted.bam
samtools flagstat "$OUTDIR"/intermediate/$BASENAME.sorted.bam > "$OUTDIR"/stats/$BASENAME.flagstat.txt

# coverage stats
bedtools genomecov -ibam "$OUTDIR"/intermediate/$BASENAME.sorted.bam -d > "$OUTDIR"/stats/$BASENAME.coverage.perbase.txt || true
bedtools genomecov -ibam "$OUTDIR"/intermediate/$BASENAME.sorted.bam > "$OUTDIR"/stats/$BASENAME.coverage.summary.txt || true

# Get maximum coverage
MAX_COV=$(awk '{if($3>max) max=$3} END {if (max=="") max=0; print max}' "$OUTDIR"/stats/$BASENAME.coverage.perbase.txt 2>/dev/null || echo 0)
echo "Maximum coverage: $MAX_COV" > "$OUTDIR"/stats/$BASENAME.max_coverage.txt

# generate pileup
bcftools mpileup -d $MAX_COV -f "/tmp/$REFNAME" -o "$OUTDIR"/$BASENAME.pileup.txt "$OUTDIR"/intermediate/$BASENAME.sorted.bam

echo "Starting variant calling..."

# Call variants
bcftools mpileup -d $MAX_COV -f "/tmp/$REFNAME" \
    "$OUTDIR"/intermediate/$BASENAME.sorted.bam | \
    bcftools call -mv -Oz -o "$OUTDIR"/$BASENAME.raw.vcf.gz

# Second call
bcftools mpileup -Ou -d $MAX_COV \
    --fasta-ref "/tmp/$REFNAME" \
    "$OUTDIR"/intermediate/$BASENAME.sorted.bam \
| bcftools call -Am -Ov -o "$OUTDIR"/$BASENAME.snps.vcf
#    --min-BQ 30 --min-MQ 30 \
#    --indel-frac 0 --indel-bias 0 \
#    --pval-threshold 1

echo "Variant calling finished."

# Run QC
bash /opt/pipeline/qc.sh "$R1" "${R2:-}" "$OUTDIR"/qc

# Postprocess for pileup
python3 /opt/pipeline/postprocess_pileup.py --pileup "$OUTDIR"/$BASENAME.pileup.txt --outdir "$OUTDIR" --basename "$BASENAME"

echo "Pipeline finished."
