#!/bin/sh
set -e
cd /app

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

exec node --max-old-space-size=400 server.js --listen --port "${PORT}"
