FROM google/cloud-sdk:401.0.0-alpine

COPY ./upload_image.sh /usr/local/bin/upload_images.sh

RUN chmod +x /usr/local/bin/upload_images.sh

ENTRYPOINT [ "/usr/local/bin/upload_images.sh" ]
