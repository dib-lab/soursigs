rule run_fastq_dump:
    output: "outputs/signatures/SRR900186.sig"
    shell: """
        mkdir -p outputs/signatures
        bin/fastq-dump -A SRR900186 -Z | sourmash compute -f -o {output} -
    """

rule download_runinfo:
    output: "outputs/info/transcriptomic.csv"
    shell: """
        mkdir -p outputs/info
        #wget -O ./query_results.csv 'http://trace.ncbi.nlm.nih.gov/Traces/sra/sra.cgi?save=efetch&db=sra&rettype=runinfo&term="Homo sapiens"[Organism] AND "cancer"[All Fields] AND "cluster_public"[prop] AND "strategy wgs"[Properties]'
        wget -O ./outputs/info/transcriptomic.csv 'http://trace.ncbi.nlm.nih.gov/Traces/sra/sra.cgi?save=efetch&db=sra&rettype=runinfo&term="TRANSCRIPTOMIC"[LibrarySource]'
    """
rule download_sratookit:
    output: "bin/fastq-dump"
    shell: """
        mkdir -p bin
        cd bin
        wget https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/2.8.0/sratoolkit.2.8.0-centos_linux64.tar.gz
        tar xf sratoolkit.2.8.0-centos_linux64.tar.gz
        mv sratoolkit.2.8.0-centos_linux64/bin/* .
        rm -rf sratoolkit.2.8.0-centos_linux64*
    """

