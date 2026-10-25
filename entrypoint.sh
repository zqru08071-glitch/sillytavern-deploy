#!/bin/sh
set -e
cd /app

PORT="${PORT:-10000}"
ST_USER="${ST_USER:-tavern}"
ST_PASS="${ST_PASS:-tavern}"

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
enableDiscreetLogin: true
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

# 首次启动时创建带密码的账号（免费实例无持久磁盘，每次启动重建）
ST_USER="$ST_USER" ST_PASS="$ST_PASS" node --input-type=module -e '
import storage from "node-persist";
import crypto from "node:crypto";
const handle = process.env.ST_USER;
const password = process.env.ST_PASS;
await storage.init({ dir: "/app/data/_storage", ttl: false, expiredInterval: 0 });
const keys = await storage.keys(x => x.key.startsWith("user:"));
// 出厂的无密码 default-user 账号必须禁用，否则任何人可无密码登录
const def = await storage.getItem("user:default-user");
if (def && def.enabled) { def.enabled = false; await storage.setItem("user:default-user", def); }
if (!keys.some(k => k === "user:" + handle)) {
  const salt = crypto.randomBytes(16).toString("base64");
  const hash = crypto.scryptSync(password.normalize(), salt, 64).toString("base64");
  await storage.setItem("user:" + handle, {
    handle, name: handle, created: Date.now(), password: hash, salt,
    admin: true, enabled: true,
  });
  console.log("account ready:", handle);
}
'

echo "Starting SillyTavern on port ${PORT} (account login)"
exec node --max-old-space-size=400 server.js --listen --port "${PORT}"
