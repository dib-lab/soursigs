from tempfile import NamedTemporaryFile

from . import app


@app.task
def compute(sra_id):
    from snakemake import shell
    with NamedTemporaryFile('w+t') as f:
        shell('fastq-dump -A {sra_id} -Z | sourmash compute -f -o {output} -'
              .format(sra_id=sra_id, output=f.name))
        f.seek(0)
        return f.read()
