#!/bin/sh
set -e
cd /home/node/app

# Render 用 PORT 环境变量指定端口
PORT="${PORT:-10000}"
ST_USER="${ST_USER:-tavern}"
ST_PASS="${ST_PASS:-tavern}"

mkdir -p config data backups plugins public/scripts/extensions/third-party

if [ ! -s config/config.yaml ]; then
  cat > config/config.yaml <<EOF
dataRoot: ./data
listen: true
port: ${PORT}
whitelistMode: false
basicAuthMode: true
basicAuthUser:
  username: "${ST_USER}"
  password: "${ST_PASS}"
enableCorsProxy: false
enableUserAccounts: false
securityOverride: true
EOF
fi

npm run init || true
chown -R node:node config data backups plugins public/scripts/extensions/third-party 2>/dev/null || true

exec node server.js --listen --port "${PORT}"
