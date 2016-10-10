from contextlib import closing
from StringIO import StringIO
import json

import requests
import screed
import sourmash_lib
from sourmash_lib import signature


def handler(event, context):
    print("Received Event: " + json.dumps(event, indent=2))

    # TODO: parse args from event
    args = {
      'protein': True,
      'n': 500,
      'k': 31,
#      'url': 'http://athyra.oxli.org/~luizirber/missing.fa',
      'url': 'http://athyra.oxli.org/~luizirber/reads_lt_90.fasta',
      'email': 'soursigs@luizirber.org',
    }

    print("Creating estimators")
    E = sourmash_lib.Estimators(ksize=args['k'],
                                n=args['n'],
                                protein=args['protein'])

    print("Opening file")
    with closing(requests.get(args['url'], stream=True)) as r:
        for n, record in enumerate(screed.fasta.fasta_iter(r.raw)):
            if n % 500 == 0:
                print("%d reads" % n)
            if args['protein']:
                E.mh.add_protein(record.sequence)
            else:
                E.add_sequence(record.sequence)

    print("Outputing signature")
    sig = signature.SourmashSignature(
        args['email'],
        E,
        filename=args['url'])

    out = StringIO("")
    signature.save_signatures([sig], out)

    return out.getvalue()
