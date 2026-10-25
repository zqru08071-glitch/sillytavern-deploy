FROM node:22-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends git git-lfs ca-certificates tini procps \
 && git lfs install --system \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone --depth 1 --branch release https://github.com/SillyTavern/SillyTavern.git . \
 && rm -rf .git

ENV NODE_ENV=production

RUN npm ci --no-audit --no-fund --loglevel=error --no-progress \
 && node ./docker/build-lib.js \
 && rm -rf ./docker \
 && npm cache clean --force

RUN mkdir -p /app/config /app/data /app/backups /app/plugins

COPY entrypoint.sh /usr/local/bin/st-entrypoint.sh
RUN chmod +x /usr/local/bin/st-entrypoint.sh

ENV PORT=10000
EXPOSE 10000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/st-entrypoint.sh"]
