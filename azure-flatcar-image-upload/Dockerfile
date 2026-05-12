FROM mcr.microsoft.com/azure-cli

RUN tdnf -y install jq

COPY --chmod=0755 ./upload_image.sh /usr/local/bin/upload_images.sh

ENTRYPOINT [ "/usr/local/bin/upload_images.sh" ]
