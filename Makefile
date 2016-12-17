SHELL := /bin/bash

ARN := 'arn:aws:lambda:us-west-2:087752545277:function:dev-soursigs-r-ComputeHelloworld-DKSQ2BU607MQ:current'

URL := 'http://sra-download.ncbi.nlm.nih.gov/srapub/SRR1300443'
PAYLOAD := '{"key1":"value1", "key2":"value2", "key3":"value3"}'

local:
	echo $(PAYLOAD) | gordon run compute.helloworld

run:
	aws --cli-read-timeout 0 \
        lambda invoke \
	--function-name '$(ARN)' \
	--log-type Tail \
	--payload '$(PAYLOAD)' \
	output.txt \
	| jq -r .LogResult | base64 --decode

iam_permissions:
	echo "aws command"

sync:
#	rsync -avzP . lambda:soursigs/
	rsync -avzP lambda:soursigs/ .

run_worker:
	source iam/soursigs_sqs && /home/chick/.virtualenvs/soursigs/bin/celery -A soursigs worker

run_workers:
	for f in $$(seq 0 31); do docker run --env-file iam/soursigs_sqs.env -d luizirber/soursigs:c1; done;

.PHONY: iam_permissions
