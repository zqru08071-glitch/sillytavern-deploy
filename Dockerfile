FROM ghcr.io/sillytavern/sillytavern:latest

USER root

COPY entrypoint.sh /usr/local/bin/st-entrypoint.sh
RUN chmod +x /usr/local/bin/st-entrypoint.sh

ENV PORT=10000
EXPOSE 10000

ENTRYPOINT ["/usr/local/bin/st-entrypoint.sh"]
