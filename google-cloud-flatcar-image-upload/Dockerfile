FROM google/cloud-sdk:alpine

COPY --chmod=0755 ./upload_image.sh /usr/local/bin/upload_images.sh

ENTRYPOINT [ "/usr/local/bin/upload_images.sh" ]
