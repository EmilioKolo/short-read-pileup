# Start with ubuntu 24.04
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
curl wget curl git unzip \
python3 python3-pip python3-setuptools python3-wheel \
samtools bcftools bedtools fastqc bwa minimap2 \
xxd ca-certificates zlib1g-dev libbz2-dev liblzma-dev \
libcurl4-openssl-dev libssl-dev pkg-config \
make gcc>=4.7.0 g++ bzip2 build-essential \
&& apt-get clean \
&& rm -rf /var/lib/apt/lists/*

# Install STAR
RUN wget -O /tmp/STAR.tar.gz https://github.com/alexdobin/STAR/archive/refs/tags/2.7.11b.tar.gz && \
    tar -xzf /tmp/STAR.tar.gz -C /opt && \
    cd /opt/STAR-2.7.11b/source && \
    make STAR && \
    cp STAR /usr/local/bin/ && \
    chmod +x /usr/local/bin/STAR && \
    rm -rf /tmp/STAR.tar.gz /opt/STAR-2.7.11b && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install pysam + numpy for postprocessing
RUN pip3 install --no-cache-dir --break-system-packages pysam numpy

RUN mkdir -p /opt/pipeline /data
RUN chmod -R 777 /opt/pipeline /data

# Set up working directory
WORKDIR /opt/pipeline
COPY entrypoint.sh qc.sh postprocess_pileup.py ./
RUN chmod +x entrypoint.sh qc.sh

ENTRYPOINT ["/opt/pipeline/entrypoint.sh"]
