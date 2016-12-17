FROM python:3.5.2-slim

RUN groupadd user && \
    useradd --create-home --home-dir /home/user -g user -s /bin/bash user

WORKDIR /home/user

# install sra-toolkit 2.8.0-2 and requirements

ADD requirements.txt .

RUN apt-get update && \
    apt-get install -y build-essential libssl-dev libcurl4-openssl-dev curl && \
    curl --output sratoolkit.tar.gz https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/2.8.0/sratoolkit.2.8.0-2-ubuntu64.tar.gz && \
    tar xf sratoolkit.tar.gz && \
    rm sratoolkit.tar.gz && \
    find sratoolkit.2.8.0-2-ubuntu64 ! -type d ! -name "fastq-dump*" -a ! -name "*.kfg" -delete && \
    pip install -r requirements.txt && \
    apt-get remove -y curl build-essential libssl-dev && \
    apt-get autoremove -y

ENV PATH $PATH:/home/user/sratoolkit.2.8.0-2-ubuntu64/bin/

USER user

# Configure sra-toolkit to disable cache
RUN mkdir .ncbi
RUN echo '/repository/user/cache-disabled = "true"' > .ncbi/user-settings.mkfg

COPY soursigs soursigs

CMD celery -A soursigs -c 1 worker
