FROM mcr.microsoft.com/azure-cli

RUN tdnf -y install go jq unzip make

WORKDIR /usr/src

RUN go install golang.org/x/lint/golint@latest && \
    curl -LO https://github.com/microsoft/azure-vhd-utils/archive/master.zip && \
    unzip master.zip && \
    rm master.zip

WORKDIR /usr/src/azure-vhd-utils-master

ENV PATH="/root/go/bin:${PATH}"
RUN make && \
    cp /usr/src/azure-vhd-utils-master/azure-vhd-utils /usr/local/bin/azure-vhd-utils

COPY ./upload_image.sh /usr/local/bin/upload_images.sh

RUN chmod +x /usr/local/bin/upload_images.sh

ENTRYPOINT [ "/usr/local/bin/upload_images.sh" ]
