#!/bin/sh
set -e
cd /app

PORT="${PORT:-10000}"
ST_USER="${ST_USER:-tavern}"
ST_PASS="${ST_PASS:-tavern}"

mkdir -p data backups plugins public/scripts/extensions/third-party

# 兜底：如果镜像里的 public/lib.js 丢了，就从 dist 里的编译产物补一份（/lib.js 404 会让整个前端白屏）
if [ ! -s public/lib.js ]; then
  LIB="$(find /app/dist -name lib.js -type f 2>/dev/null | head -1 || true)"
  if [ -n "$LIB" ]; then cp "$LIB" public/lib.js; echo "restored public/lib.js from $LIB"; fi
fi

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

# 免费实例没有持久盘：给账号种一份官方默认 settings.json，否则 /api/settings/get 返回 500，
# 前端拿到不到设置就一直在“Error getting settings”状态，界面初始化不了
DATA_DIR="data/${ST_USER}"
mkdir -p "$DATA_DIR"
if [ ! -s "$DATA_DIR/settings.json" ] && [ -s /usr/local/share/silverseed-settings.json ]; then
  cp /usr/local/share/silverseed-settings.json "$DATA_DIR/settings.json"
  echo "seeded $DATA_DIR/settings.json"
elif [ ! -s "$DATA_DIR/settings.json" ] && [ -s "default/content/settings.json" ]; then
  cp "default/content/settings.json" "$DATA_DIR/settings.json"
  echo "seeded $DATA_DIR/settings.json"
fi

# 把冥王星快捷回复集种进账号（注意目录名是 QuickReplies，大写），开机就能直接用
mkdir -p "$DATA_DIR/QuickReplies"
if [ -s /usr/local/share/silverseed-qr.json ] && [ ! -s "$DATA_DIR/QuickReplies/🪐冥王星QR.json" ]; then
  cp /usr/local/share/silverseed-qr.json "$DATA_DIR/QuickReplies/🪐冥王星QR.json"
  echo "seeded pluto quick reply set"
fi

echo "Starting SillyTavern on port ${PORT} (account login)"
exec node --max-old-space-size=400 server.js --listen --port "${PORT}"
