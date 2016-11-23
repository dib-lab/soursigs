import os

import pandas as pd
t = pd.read_csv("outputs/info/transcriptomic.csv")

INPUTS = t.sort_values(by='size_MB')['Run']

#SRR900186

rule all:
    input: expand("outputs/signatures/{SRA_IDS}.sig", SRA_IDS=INPUTS)

rule run_fastq_dump:
    output: "outputs/signatures/{SRA_ID}.sig"
    params: SRA_ID="{SRA_ID}"
    shell: """
        mkdir -p outputs/signatures
        set -o pipefail
        bin/fastq-dump -A {params.SRA_ID} -Z | sourmash compute -f -o {output} -
    """

rule download_runinfo:
    output: "outputs/info/transcriptomic.csv"
    shell: """
        mkdir -p outputs/info
        wget -O {output}.full 'http://trace.ncbi.nlm.nih.gov/Traces/sra/sra.cgi?save=efetch&db=sra&rettype=runinfo&term="TRANSCRIPTOMIC"[LibrarySource]'
        head -n -1 {output}.full > {output}
        rm {output}.full
    """
    #wget -O ./query_results.csv 'http://trace.ncbi.nlm.nih.gov/Traces/sra/sra.cgi?save=efetch&db=sra&rettype=runinfo&term="Homo sapiens"[Organism] AND "cancer"[All Fields] AND "cluster_public"[prop] AND "strategy wgs"[Properties]'

rule download_sratoolkit:
    output: "bin/fastq-dump"
    shell: """
        mkdir -p bin
        cd bin
        wget https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/2.8.0/sratoolkit.2.8.0-centos_linux64.tar.gz
        tar xf sratoolkit.2.8.0-centos_linux64.tar.gz
        mv sratoolkit.2.8.0-centos_linux64/bin/* .
        rm -rf sratoolkit.2.8.0-centos_linux64*
    """

rule download_ipfs:
    output: "bin/ipfs"
    shell: """
        mkdir -p bin
        cd bin
        wget https://dist.ipfs.io/go-ipfs/v0.4.4/go-ipfs_v0.4.4_linux-amd64.tar.gz
        tar xf go-ipfs_v0.4.4_linux-amd64.tar.gz
        mv go-ipfs/ipfs .
        rm -rf go-ipfs*
    """

rule update_ipfs:
    shell: """
        cd outputs
        ../bin/ipfs name publish $(../bin/ipfs add -r signatures/ | tail -1 | cut -d " " -f2)
    """

rule check_downloaded:
    run:
        from glob import glob

        completed = pd.Series([os.path.basename(f).replace(".sig", "")
                               for f in glob("outputs/signatures/*.sig")])

        tt = t.set_index('Run')

        print("{0:,.2f} MB, {1}/{2} runs ({3:.2f} %)".format(
            tt.loc[completed]['size_MB'].sum(),
            len(completed), len(tt),
            len(completed) / len(tt) * 100))
