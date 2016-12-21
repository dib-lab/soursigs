import os


def inputs_from_runinfo(w):
    import pandas as pd
    t = pd.read_csv("outputs/info/{subset}.csv".format(**w),
                     usecols=["Run", "size_MB"])

    #SRR900186
    INPUTS = t['Run']
    #INPUTS = t.sort_values(by='size_MB')['Run']
    #INPUTS = (t.sort_values(by='size_MB')['Run']
    #           .head(1))
    #           .sample(1000))

    return expand("outputs/signatures/{subset}/{config}/{SRA_IDS}.sig",
                  subset=w.subset,
                  config=w.config,
                  SRA_IDS=INPUTS)

rule all:
    input:
        "outputs/info/transcriptomic.csv",
        "outputs/info/microbial.csv",
        "outputs/signatures/microbial/1m-then-trim/results"

rule microbial_signatures:
    input: inputs_from_runinfo
    output: 'outputs/signatures/{subset}/{config}/results'
    shell: "touch {output}"

rule run_fastq_dump:
    output: "outputs/signatures/{subset}/{config}/{SRA_ID}.sig"
    params:
        SRA_ID="{SRA_ID}",
        subset="{subset}",
        config="{config}"
    run:
        from soursigs.tasks import compute
        job = compute.delay(params.SRA_ID)
        result = job.get()
        with open(output[0], 'wt') as f:
            f.write(result)

rule download_microbial_runinfo:
    output: "outputs/info/microbial.csv"
    shell: """
        mkdir -p outputs/info
        wget -O {output}.full 'http://trace.ncbi.nlm.nih.gov/Traces/sra/sra.cgi?save=efetch&db=sra&rettype=runinfo&term=(("biomol dna"[Properties] NOT amplicon[All Fields])) AND "bacteria"[orgn:__txid2] NOT metagenome'
        #wget -O {output}.full 'http://trace.ncbi.nlm.nih.gov/Traces/sra/sra.cgi?save=efetch&db=sra&rettype=runinfo&term="microbial"[All Fields] AND "biomol dna"[Properties]'
        head -n -1 {output}.full > {output}
        rm {output}.full
    """

rule download_transcriptomic_runinfo:
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

        print("{0:,.2f} MB ({4:.2f}) %, {1}/{2} runs ({3:.2f} %)".format(
            tt.loc[completed]['size_MB'].sum(),
            len(completed), len(tt),
            len(completed) / len(tt) * 100,
            tt.loc[completed]['size_MB'].sum() / tt['size_MB'].sum() * 100))
