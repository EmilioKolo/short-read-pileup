#!/usr/bin/env bash

# Define usage function
usage() {
    cat <<'EOF'
Usage: bash run_pipeline.sh -1 <R1.fastq[.gz]> [-2 <R2.fastq[.gz]>] -r <ref.fasta> -a <aligner> -o <outdir> [-t threads] [--regen_docker_image] [--no-user-map]

Aligners supported: bwa, minimap2, star
EOF
}

# Parse long options manually
REGEN_DOCKER_IMAGE=false
USER_MAP=true
TEMP_ARGS=()
for arg in "$@"; do
    case $arg in
        --regen_docker_image)
            REGEN_DOCKER_IMAGE=true
            ;;
        --no-user-map)
            USER_MAP=false
            ;;
        *)
            TEMP_ARGS+=("$arg")
            ;;
    esac
done
set -- "${TEMP_ARGS[@]}"

# Helper for macOS: define a portable realpath
realpath_fallback() {
    if command -v realpath >/dev/null 2>&1; then
        realpath "$1"
    else
        # macOS doesn't have realpath by default
        echo "$(cd "$(dirname "$1")"; pwd)/$(basename "$1")"
    fi
}

# Get command-line arguments
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

if [[ -z "$R1" || -z "$REF" || -z "$ALIGNER" || -z "$OUTDIR" ]]; then
    echo "Error: Missing required arguments."
    usage
    exit 2
fi

# Resolve directories and filenames
FASTQ_DIR=$(realpath_fallback "$(dirname "$R1")")
if [[ -n "$R2" ]]; then
    if [[ "$(realpath_fallback "$(dirname "$R2")")" != "$FASTQ_DIR" ]]; then
        echo "Error: R1 and R2 must be in the same directory."
        exit 1
    fi
fi

R1_FILENAME=$(basename "$R1")
R2_FILENAME=$(basename "$R2")
REF_DIR=$(realpath_fallback "$(dirname "$REF")")
REF_FILENAME=$(basename "$REF")
OUTDIR=$(realpath_fallback "$OUTDIR")

# Ensure Docker exists
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Please install Docker Desktop for Mac:"
    echo "  https://docs.docker.com/desktop/install/mac-install/"
    exit 1
fi

# Build Docker image if needed
if [[ "$REGEN_DOCKER_IMAGE" == "true" || "$(docker images -q short-read-pileup:latest 2> /dev/null)" == "" ]]; then
    echo "Building Docker image short-read-pileup:latest ..."
    docker build -t short-read-pileup:latest .
fi

mkdir -p "$OUTDIR"

echo "Parameters:"
echo "  R1: $R1_FILENAME"
[[ -n "$R2" ]] && echo "  R2: $R2_FILENAME" || echo "  R2: (not provided)"
echo "  Reference: $REF_FILENAME"
echo "  Aligner: $ALIGNER"
echo "  Outdir: $OUTDIR"
echo "  Threads: $THREADS"

# Optional user mapping flag
USER_FLAG=()
if [[ "$USER_MAP" == "true" ]]; then
    USER_FLAG=(--user "$(id -u):$(id -g)")
fi

# Run Docker
if [[ -n "$R2" ]]; then
    echo "Running paired-end pipeline..."
    docker run -it \
        -v "$FASTQ_DIR":/data/input/fastq \
        -v "$REF_DIR":/data/input/references \
        -v "$OUTDIR":/data/output \
        "${USER_FLAG[@]}" \
        short-read-pileup \
        -1 /data/input/fastq/"$R1_FILENAME" \
        -2 /data/input/fastq/"$R2_FILENAME" \
        -r /data/input/references/"$REF_FILENAME" \
        -a "$ALIGNER" -o /data/output -t "$THREADS"
else
    echo "Running single-end pipeline..."
    docker run -it \
        -v "$FASTQ_DIR":/data/input/fastq \
        -v "$REF_DIR":/data/input/references \
        -v "$OUTDIR":/data/output \
        "${USER_FLAG[@]}" \
        short-read-pileup \
        -1 /data/input/fastq/"$R1_FILENAME" \
        -r /data/input/references/"$REF_FILENAME" \
        -a "$ALIGNER" -o /data/output -t "$THREADS"
fi
