import io
import os
from subprocess import CalledProcessError

import numpy as np
import pandas as pd

PRJ_ROOT = next(shell("readlink -e .", iterable=True))
ipfs = os.path.join(PRJ_ROOT, 'bin', 'ipfs')

def inputs_from_runinfo(w):
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
#        "outputs/signatures/microbial/1m-then-trim/results",
        "outputs/signatures/microbial/syrah/results"

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
        from soursigs.tasks import compute, compute_syrah
        from celery.exceptions import TimeoutError

        if params.config == "1m-then-trim":
            job = compute.delay(params.SRA_ID)
        elif params.config == "syrah":
            job = compute_syrah.delay(params.SRA_ID)
        else:
            raise ValueError("Invalid config: {}".format(params.config))

        try:
            result = job.get(interval=60)
        except TimeoutError:
            # TODO: command took too long, retry?
            pass
        except CalledProcessError:
            # TODO: command failed, retry?
            pass
        else:
            with open(output[0], 'wt') as f:
                f.write(result)
        finally:
            job.forget()

rule compute_to_s3:
    input: "outputs/info/microbial.csv",
#    input: "outputs/info/{subset}.csv",
#    params:
#        subset="{subset}",
    run:
        from soursigs.tasks import compute_syrah_to_s3
        import ipfsapi

        ipfs = ipfsapi.connect()

        subset = 'microbial'
        # Download file list from ipfs,
        node = ipfs.ls('/ipns/minhash.oxli.org/{}/syrah'.format(subset))
        sigs = {os.path.splitext(p['Name'])[0]
                for p in node['Objects'][0]['Links']}

        # load input from runinfo
        t = pd.read_csv(input[0], usecols=["Run"])

        # find what tasks are missing from input,
        missing = set(t['Run']) - sigs

        num_tasks = 10000
        for sig in missing:
            # send tasks to SQS
            compute_syrah_to_s3.delay(sig)
            num_tasks -= 1
            if num_tasks == 0:
                break

rule s3_to_ipfs:
    run:
        import ipfsapi
        from ipfsapi.exceptions import ErrorResponse
        from boto.s3.connection import S3Connection

        conn = S3Connection()
        bucket = conn.get_bucket("soursigs-done")
        ipfs = ipfsapi.connect()

        for item in bucket.list('sigs/'):
            sig = os.path.basename(item.key)
            if sig:
                sig_present = False
                sig_path = '/signatures/microbial/syrah/{}.sig'.format(sig)
                # check if sig is already present
                try:
                    ipfs.files_ls(sig_path)
                except ErrorResponse as e:
                    if 'file does not exist' in e.args:
                        # we can add the sig
                        sig_present = False
                    else:
                        # other error, reraise
                        raise e
                else:
                    sig_present = True

                if not sig_present:
                    # add to IPFS
                    ipfs.files_write(sig_path,
                                     io.BytesIO(item.get_contents_as_string()),
                                     create=True)
                    sig_present = True

                if sig_present:
                    # remove from S3
                    item.delete()

        # publish new root
        new_root = ipfs.files_stat('/signatures')['Hash']
        ipfs.name_publish(new_root)
        ipfs.pin_add(new_root, recursive=True)

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

rule update_ipfs_walk:
    run:
        import ipfsapi
        from ipfsapi.exceptions import ErrorResponse
        ipfs = ipfsapi.connect()

        os.chdir('outputs')
        for root, dirs, files in os.walk("signatures"):
            ipfs_path = os.path.join('/', root)
            present = {f['Name'] for f in ipfs.files_ls(ipfs_path)['Entries']}
            for f in files:
                if f not in present:
                    print('DEBUG: adding file {}/{}'.format(root, f))
                    with open(os.path.join(root, f), 'rb') as fp:
                        ipfs.files_write(os.path.join(ipfs_path, f),
                                         io.BytesIO(fp.read()),
                                         create=True)

        # publish new root
        new_root = ipfs.files_stat('/signatures')['Hash']
        ipfs.name_publish(new_root)
        ipfs.pin_add(new_root, recursive=True)


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

rule plot_speed:
    run:
        from datetime import datetime, timedelta, date, time
        for root, dirs, files in os.walk("outputs/signatures/microbial/syrah/", topdown=False):
            ctimes = [os.stat((os.path.join(root, name))).st_ctime for name in files]
        bottom = np.min(ctimes)
        top = np.max(ctimes)
        #offset = timedelta(hours=12)
        offset = timedelta(days=1)

        bottom = datetime.combine(date.fromtimestamp(bottom), time()).timestamp()
        bins = [datetime.fromtimestamp(bottom).timestamp()]
        c = bottom
        while c < top:
            next_day = datetime.fromtimestamp(c) + offset
            c = next_day.timestamp()
            bins.append(c)

        ctimes, bins = np.histogram(ctimes, bins)
        top = np.max(ctimes)
        sumall = np.sum(ctimes)
        width = 15 / top

        format_string = "{:10}|{:>10} | {:16} | {:16} | {:>6}"
        print(format_string.format(
               "date", "count", "histogram", "cumulative", "sigs/h"))
        print('-' * 68)

        cum = 0
        for c, b in zip(ctimes, bins):
            cum += c
            print(format_string.format(
                     datetime.fromtimestamp(b).strftime("%d %H:%M"),
                     c,
                     '*' * int(width * c),
                     '*' * int(cum / sumall * 15),
                     int(c / 24))
                 )

        print('-' * 68)
        print(format_string.format(
               "", sumall, "", sumall, int(sumall / (len(ctimes) * 24))))
