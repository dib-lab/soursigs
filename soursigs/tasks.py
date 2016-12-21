from tempfile import NamedTemporaryFile

from . import app


@app.task
def compute(sra_id):
    from snakemake import shell
    with NamedTemporaryFile('w+t') as f:
        shell('fastq-dump -A {sra_id} -Z | '
              'head -4000000 | '
              'trim-low-abund.py -M 1e9 -k 21 -V -Z 10 -C 3 - -o - | '
              'sourmash compute -f -k 21 --dna - -o {output} --name {sra_id}'
              .format(sra_id=sra_id, output=f.name))
        f.seek(0)
        return f.read()
