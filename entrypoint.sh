#!/bin/sh
set -e
cd /app

PORT="${PORT:-10000}"

mkdir -p data backups plugins public/scripts/extensions/third-party

cat > config.yaml <<EOF
dataRoot: ./data
listen: true
listenAddress:
  ipv4: 0.0.0.0
  ipv6: '[::]'
protocol:
  ipv4: true
  ipv6: false
port: ${PORT}
browserLaunch:
  enabled: false
whitelistMode: false
basicAuthMode: false
enableUserAccounts: true
enableDiscreetLogin: false
securityOverride: true
skipContentCheck: true
enableDownloadableTokenizers: false
sessionTimeout: -1
extensions:
  enabled: true
  autoUpdate: false
  models:
    autoDownload: false
EOF

echo "Starting SillyTavern on port ${PORT} (accounts login)"
exec node --max-old-space-size=400 server.js --listen --port "${PORT}"
