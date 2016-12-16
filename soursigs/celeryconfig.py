import os

CELERY_RESULT_BACKEND = 'celery_s3.backends.S3Backend'

CELERY_S3_BACKEND_SETTINGS = {
    'aws_access_key_id': os.environ['AWS_ACCESS_KEY_ID'],
    'aws_secret_access_key': os.environ['AWS_SECRET_ACCESS_KEY'],
    'bucket': 'soursigs-results',
}

CELERY_TASK_SERIALIZER = 'json'
CELERY_ACCEPT_CONTENT = ['json', 'yaml']
CELERY_RESULT_SERIALIZER = 'json'

CELERY_ENABLE_REMOTE_CONTROL = False
CELERY_SEND_EVENTS = False

CELERY_ENABLE_UTC = True
CELERY_DISABLE_RATE_LIMITS = True
BROKER_TRANSPORT_OPTIONS = {
 'queue_name_prefix': 'soursigs-',
 'visibility_timeout': 3600, # seconds
 'wait_time_seconds': 20,  # Long polling
}

import snakemake

snakemake.shell.executable('/bin/bash')
snakemake.shell.prefix('set -o pipefail; ')
