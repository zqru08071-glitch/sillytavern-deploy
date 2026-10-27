// 给前端静态资源引用统一加 ?v=<内容指纹>。
// 配合 nginx「js/css 长缓存」：镜像内容不变 → 指纹不变 → 一直吃本地缓存；
// 镜像重建或改了前端 → 指纹变 → URL 变 → 客户端必然重新拉取，不会卡在旧版本上。
// 幂等：指纹计算前先把已存在的 ?v=xxx 抹掉，重复执行结果完全一致。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ROOT = process.argv[2] || '/app/public';
// 内置扩展（expressions / regex / vectors…）的 index.js 会 import 核心模块，
// 不给他们打指纹 → 核心模块会被第二次以「无版本号」URL 加载 → 两份实例 → 循环依赖 TDZ。
// 只跳过第三方扩展（用户自己放的）和用户数据目录。
const SKIP_DIRS = new Set(['third-party', 'node_modules', '.git', 'characters', 'chats', 'user', 'backups']);
const V_RE = /\?v=[0-9a-f]{8,}/g;

function walk(dir, out = []) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name)) walk(p, out); }
        else out.push(p);
    }
    return out;
}

const all = walk(ROOT).sort();
const targets = all.filter(f => /\.(js|mjs|css|html)$/i.test(f));

// 1) 指纹：按「抹掉版本号后的内容」算，保证幂等
const h = crypto.createHash('md5');
for (const f of targets) {
    h.update(path.relative(ROOT, f));
    h.update(fs.readFileSync(f, 'utf8').replace(V_RE, ''));
}
const STAMP = h.digest('hex').slice(0, 10);
const V = '?v=' + STAMP;

// 2) 三类引用
const RE_HTML = /(\b(?:src|href)=")(?!https?:|\/\/|data:|#|\/)([^"?#]+?\.(?:js|mjs|css|woff2?|png|ico|svg|json))(?:\?v=[0-9a-f]+)?(")/g;
const RE_CSS  = /(@import\s+url\(\s*['"]?)(?!https?:|\/\/|data:)([^'")]+?\.css)(?:\?v=[0-9a-f]+)?(['"]?\s*\))/g;
const RE_JS   = /(\bfrom\s*['\"]|\bimport\s*['\"]|\bimport\(\s*['\"])(?!https?:|\/\/|data:)((?:\.{1,2}\/|\/)[^'\"?]+?\.(?:js|mjs))(?:\?v=[0-9a-f]+)?(['\"])/g;

let files = 0, refs = 0;
for (const f of targets) {
    const src = fs.readFileSync(f, 'utf8');
    let out = src, n = 0;
    for (const re of [RE_HTML, RE_CSS, RE_JS]) {
        out = out.replace(re, (m, a, mid, b) => { n++; return a + mid + V + b; });
    }
    if (n === 0 || out === src) continue;
    files++; refs += n;
    fs.writeFileSync(f, out);
}
console.log(`asset-version: stamp=${STAMP} files=${files} refs=${refs}`);
