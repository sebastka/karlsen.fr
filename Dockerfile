FROM scratch
COPY mta-sts /mnt/karlsenfr/mta-sts
COPY openpgpkey /mnt/karlsenfr/openpgpkey
COPY other /mnt/karlsenfr/other
COPY www /mnt/karlsenfr/www
WORKDIR /mnt/karlsenfr/www
ENTRYPOINT ["/mnt/karlsenfr/www"]
