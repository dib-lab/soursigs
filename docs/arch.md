Title: Minhashing all the things (part 1): microbial genomes
Date: 2016-12-28 12:00
Author: luizirber
Category: universidade
Slug: soursigs_arch_1

With the [MinHash][0] [craze][1] currently going on in the [lab][2],
we started discussing how to calculate signatures efficiently,
how to index them for search and also how to distribute them.
As a proof of concept I started implementing a system to read public data available on the [Sequence Read Archive][3],
as well as a variation of the [Sequence Bloom Tree][4] using Minhashes as leaves/datasets instead of the whole k-mer set (as Bloom Filters).

Since this is a PoC,
I also wanted to explore some solutions that allow maintaining the least amount of explicit servers:
I'm OK with offloading a queue system to [Amazon SQS][5] instead of maintaining a server running [RabbitMQ][6],
for example.
Even with all the DevOps movement you still can't ignore the Ops part,
and if you have a team to run your infrastructure,
good for you!
But I'm a grad student and the last thing I want to be doing is babysitting servers =]

## Going serverless: AWS Lambda

The first plan was to use [AWS Lambda][7] to calculate signatures.
Lambda is **TODO**
Despite all the promises,
it is a bit annoying to balance everything to make an useful Lambda,
so I used the [Gordon framework][8] to structure it.
I was pretty happy with it,
until I added our [MinHash package][9] and,
since it is a C++ extension,
needed to compile and send the resulting package to Lambda.
I was using my local machine for that,
but Lambda packaging is pretty much 'put all the Python files in one directory,
compress and upload it to S3',
which of course didn't work because I don't have the same library versions that [Amazon Linux][10] runs.
I managed to hack a [fix][11],
but it would be wonderful if Amazon adopted wheels and stayed more in line with the [Python Package Authority][12] solutions
(and hey, [binary wheels][13] even work on Linux now!).

Anyway,
after I deployed the Lambda function and tried to run it...
I fairly quickly realized that 5 minutes is far too short to calculate a signature.
This is not a CPU-bound problem,
it's just that we are downloading the data and network I/O is the bottleneck.
I think Lambda will still be a good solution together with [API Gateway][14]
for triggering calculations and providing other useful services despite the drawbacks,
but at this point I started looking for alternative architectures.

## Back to the comfort zone: Snakemake

Focusing on computing signatures first and thinking about other issues later,
I wrote a quick [Snakemake][15] rules file and started calculating signatures
for all the [transcriptomic][16] datasets I could find on the SRA.
Totaling 671 TB,
it was way over my storage capacity,
but since both the [SRA Toolkit][17] and [sourmash][9] have streaming modes,
I piped the output of the first as the input for the second and... voila!
We have a duct-taped but working system.
Again,
the issue becomes network bottlenecks:
the SRA seems to limit each IP to ~100 Mbps,
it would take 621 days to calculate everything.
Classes were happening during these development,
so I just considered it good enough and started running it in a 32-core server hosted at [Rackspace][22]
to at least have some signatures to play with.

## Offloading computation: Celery + Amazon SQS

With classes over,
we changed directions a bit:
instead of going through the transcriptomic dataset,
we decided to focus on microbial genomes,
especially all those unassembled ones on SRA.
There are 412k SRA IDs matching the [new search][32],
totalling 28 TB of data.
This is more manageable and we have storage to save it,
but since we want a scalable solution (something that would work with the 8 PB of data in the SRA,
for example),
I avoided downloading all the data beforehand and kept doing it in a streaming way.

I started to redesign the Snakemake solution:
first thing was to move the body of the rule to a [Celery task][18]
and use Snakemake to control what tasks to run and get the results,
but send the computation to a (local or remote) Celery worker.
I checked other work queue solutions,
but they were either too simple or required running specialized servers.
With Celery I managed to use [Amazon SQS][19] as a broker
(the queue of tasks to be executed,
in Celery parlance),
and [celery-s3][20] as the results backend.
While not an official part of Celery,
using S3 to keep results allowed to avoid deploying another service
(usually Celery uses redis or RabbitMQ for result backend).
I didn't configure it properly tho,
and ended up racking up \$200 in charges because I was querying S3 too much,
but my advisor thought it was [funny and mocked me on Twitter][21] (I don't mind,
he is the one paying the bill =P).
For initial tests I just ran the workers locally on the 32-core server,
but... What if the worker was easy to deploy,
and other people wanted to run additional workers?

### Docker workers

I wrote a [Dockerfile][23] with all the dependencies,
and made it available on [Docker hub][24].
I still need to provide credentials to access SQS and S3,
but now I can deploy workers anywhere,
even... on the [Google Cloud Platform][25].
They have a free trial with \$300 in credits,
so I used the [Container Engine][26] to deploy a Kubernetes cluster and run
workers under a [Replication Controller][27].

Just to keep track: we are posting Celery tasks from a Rackspace server
to Amazon SQS,
running workers inside Docker managed by Kubernetes on GCP,
putting results on Amazon S3
and finally reading the results on Rackspace and then posting it to [IPFS][28].
IPFS is the Interplanetary File System,
a decentralized solution to share data.
But more about this later!

### HPCC workers

Even with Docker workers running on GCP and the Rackspace server,
it was progressing slowly and,
while it wouldn't be terribly expensive to spin up more nodes on GCP,
I decided to go use the resources we already have:
the [MSU HPCC][29].
I couldn't run Docker containers there (HPC is wary of Docker,
but [we are trying to change that!]][30]),
so I used Conda to create a clean environment and used the [requirements][31]
file (coupled with some `PATH` magic) to replicate what I have inside the Docker container.
The Dockerfile was very useful,
because I mostly ran the same commands to recreate the environment.
Finally,
I wrote a [submission script][31] to start a job array with 40 jobs,
and after a bit of tuning I decided to use 12 Celery workers for each job,
totalling 480 workers.

This solution still requires a bit of babysitting,
especially when I was tuning how many workers to run per job,
but it achieved around 1600 signatures per hour,
leading to about 10 days to calculate for all 412k datasets.
Instead of downloading the whole dataset,
we are [reading the first million reads][34] and using our [streaming trimming][33]
solution to calculate the signatures
(and also to test if it is the best solution for this case).

### Clever algorithms are better than brute force?

While things were progressing,
Titus was using the [Sequence Bloom Tree + Minhash][37] code to categorize the new datasets into the 50k genomes in the [RefSeq] database,
but 99\% of the signatures didn't match anything.
After assembling a dataset that didn't match,
he found out it did match something,
so... The current approach is not so good.

Yesterday he came up with a new way to filter solid k-mers instead of doing
error trimming (and named it... [syrah][35]?),
but you can go to [his blog post][36] to check for more details.
I [created a new Celery task][38] and refactored the Snakemake rule,
and started running it again...
And wow is it faster!
It is currently doing around 4200 signatures per hour,
and it will end in less than five days.

# Future

The solution works,
but several improvements can be made.
First,
I use Snakemake at both ends,
both to keep track of the work done and get the workers results.
I can make the workers a bit smarter and post the results to a S3 bucket,
and so I only need to use Snakemake to track what work needs to be done and post tasks to the queue.
This removes the need for celery-s3 and querying S3 all the time,
and opens the path to use Lambda again to trigger updates to IPFS.

I'm insisting on using IPFS to make the data available because...
Well, it is super cool!
I always wanted to have a system like bittorrent to distribute data,
but IPFS builds up on top of other very good ideas from bitcoin (bitswap),
and git (the DAG representation) to make a resilient system and,
even more important,
something that can be used in a scientific context to both increase bandwidth for important resources (like, well, the SRA)
and to make sure data can stay around if the centralized solution goes away.
And,
even crazier,
we can actually use IPFS to store our SBT implementation,
but more about this in part 2!

[0]: 
[1]: 
[2]: 
[3]: 
[4]: 
[21]: https://twitter.com/ctitusbrown/status/812003429535006721
[27]: http://kubernetes.io/docs/user-guide/replication-controller/
[30]: https://github.com/NERSC/2016-11-14-sc16-Container-Tutorial
