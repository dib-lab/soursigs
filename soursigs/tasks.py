from subprocess import CalledProcessError
from tempfile import NamedTemporaryFile

from . import app


@app.task
def compute(sra_id):
    from snakemake import shell
    with NamedTemporaryFile('w+t') as f:
        try:
            shell('fastq-dump -A {sra_id} -Z | '
                  'head -4000000 | '
                  'trim-low-abund.py -M 1e8 -k 21 -V -Z 10 -C 3 - -o - | '
                  'sourmash compute -f -k 21 --dna - -o {output} --name {sra_id}'
                  .format(sra_id=sra_id, output=f.name))
        except CalledProcessError as e:
            # We ignore SIGPIPE, since it is informational (and makes sense,
            # it happens because `head` is closed and `fastq-dump` can't pipe
            # its output anymore. More details:
            # http://www.pixelbeat.org/programming/sigpipe_handling.html
            if e.returncode != 141:
                raise e

        f.seek(0)
        return f.read()
