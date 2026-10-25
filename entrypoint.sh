#!/bin/sh
set -e
cd /home/node/app

PORT="${PORT:-10000}"
ST_USER="${ST_USER:-tavern}"
ST_PASS="${ST_PASS:-tavern}"

mkdir -p config data backups plugins public/scripts/extensions/third-party

cat > config/config.yaml <<EOF
dataRoot: ./data
listen: true
port: ${PORT}
whitelistMode: false
basicAuthMode: true
basicAuthUser:
  username: "${ST_USER}"
  password: "${ST_PASS}"
enableUserAccounts: false
securityOverride: true
skipContentCheck: true
extensions:
  enabled: true
  autoUpdate: false
  models:
    autoDownload: false
EOF

chown -R node:node config data backups plugins public/scripts/extensions/third-party 2>/dev/null || true

exec node --max-old-space-size=384 server.js --listen --port "${PORT}"
