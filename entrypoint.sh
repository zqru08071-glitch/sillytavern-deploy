#!/bin/sh
set -e
cd /app

PORT="${PORT:-10000}"
ST_USER="${ST_USER:-tavern}"
ST_PASS="${ST_PASS:-tavern}"
PRESET_NAME="冥王星预设_Ver2.0"

mkdir -p data backups plugins public/scripts/extensions/third-party

# 持久盘适配：付费实例把磁盘挂到 /app/data，这里把第三方扩展/插件/备份也放进去，
# 这样重部署后「酒馆助手」这类扩展、插件和备份都不会丢。没挂盘时等同普通目录，行为不变。
link_dir() {
  src="$1"; dst="$2"
  mkdir -p "$src"
  if [ -d "$dst" ] && [ ! -L "$dst" ]; then
    cp -a "$dst/." "$src/" 2>/dev/null || true
    rm -rf "$dst"
  fi
  [ -L "$dst" ] || [ -e "$dst" ] || ln -s "$src" "$dst"
}
link_dir /app/data/third-party-extensions public/scripts/extensions/third-party
link_dir /app/data/plugins plugins
link_dir /app/data/backups backups

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

# 把冥王星预设（Chat Completion 预设）种进 OpenAI Settings，预设下拉里直接能选
mkdir -p "$DATA_DIR/OpenAI Settings"
if [ -s /usr/local/share/silverseed-preset.json ] && [ ! -s "$DATA_DIR/OpenAI Settings/$PRESET_NAME.json" ]; then
  cp /usr/local/share/silverseed-preset.json "$DATA_DIR/OpenAI Settings/$PRESET_NAME.json"
  echo "seeded pluto preset"
fi

# 免费实例无持久盘：把主题种进账号，重启后依然在；
# 只有用户还没选过主题（或还是出厂 Dark Lite）时，才把 seed-theme.json 设为当前主题
if ls /usr/local/share/silverseed-theme*.json >/dev/null 2>&1; then
  mkdir -p "$DATA_DIR/themes"
  rm -f "$DATA_DIR/themes/silverseed-theme"*.json
  for f in /usr/local/share/silverseed-theme*.json; do
    NAME="$(basename "$f" .json)"; NAME="${NAME#silverseed-theme}"
    case "$NAME" in
      -x-default) TARGET="【SAYA】X-default" ;;
      -x-lightsout) TARGET="【SAYA】X-lights out" ;;
      -x-pink) TARGET="【SAYA】X-pink" ;;
      *) TARGET="♡♱ 少女祷告 ♱♡" ;;
    esac
    [ -s "$DATA_DIR/themes/$TARGET.json" ] || cp "$f" "$DATA_DIR/themes/$TARGET.json"
  done
  DATA_DIR="$DATA_DIR" node --input-type=module -e '
import fs from "node:fs";
const dir = process.env.DATA_DIR;
try {
  const theme = JSON.parse(fs.readFileSync("/usr/local/share/silverseed-theme-x-default.json", "utf8"));
  const file = `${dir}/settings.json`;
  if (fs.existsSync(file)) {
    const s = JSON.parse(fs.readFileSync(file, "utf8"));
    s.power_user = s.power_user || {};
    if (!s.power_user.theme || s.power_user.theme === "Dark Lite") {
      s.power_user.theme = theme.name;
      s.power_user.custom_css = theme.custom_css || "";
      for (const [k, v] of Object.entries(theme)) {
        if (["name", "custom_css", "extensions", "tags", "character_version"].includes(k)) continue;
        if (s.power_user[k] === undefined) s.power_user[k] = v;
      }
      fs.writeFileSync(file, JSON.stringify(s, null, 4), "utf8");
      console.log("theme applied:", theme.name);
    }
  }
} catch (e) {
  console.error("theme seed skipped:", e.message);
}
'
fi

# 免费实例无持久盘：把美化正则（睡莲）合并进 settings.json，重启/重部署后还在
if [ -s /usr/local/share/silverseed-regex.json ]; then
  DATA_DIR="$DATA_DIR" node --input-type=module -e '
import fs from "node:fs";
const dir = process.env.DATA_DIR;
try {
  const seeds = JSON.parse(fs.readFileSync("/usr/local/share/silverseed-regex.json", "utf8"));
  const file = `${dir}/settings.json`;
  if (!fs.existsSync(file)) process.exit(0);
  const s = JSON.parse(fs.readFileSync(file, "utf8"));
  s.extension_settings = s.extension_settings || {};
  const cur = Array.isArray(s.extension_settings.regex) ? s.extension_settings.regex : [];
  const have = new Set(cur.map(x => x.scriptName));
  let added = 0;
  for (const seed of seeds) {
    if (have.has(seed.scriptName)) continue;
    cur.push(seed);
    added++;
  }
  s.extension_settings.regex = cur;
  fs.writeFileSync(file, JSON.stringify(s, null, 4), "utf8");
  console.log("regex seeded:", added);
} catch (e) {
  console.error("regex seed skipped:", e.message);
}
'
fi

echo "Starting SillyTavern on port ${PORT} (account login)"
exec node --max-old-space-size="${NODE_HEAP:-400}" server.js --listen --port "${PORT}"
