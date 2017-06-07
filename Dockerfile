FROM alpine:latest
MAINTAINER Stephane Albert "sheeprine@nullplace.com"

ENV RNDC_KEY_FILE="/run/secrets/rndc.key" \
    TSIG_KEY_FILE="/run/secrets/tsig.key"
RUN apk add --no-cache bind && rm -rf /var/cache/apk/* && \
    # ln -s /dev/null /etc/bind/rndc.key && \
    # touch /etc/bind/named.conf && \
    chown named: /etc/bind

COPY entrypoint.sh /
COPY /templates /templates

ENTRYPOINT ["/entrypoint.sh"]
