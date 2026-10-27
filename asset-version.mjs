// 给前端静态资源引用统一加 ?v=<内容指纹>。
// 配合 nginx「js/css 长缓存」：镜像内容不变 → 指纹不变 → 一直吃本地缓存；
// 镜像重建或改了前端 → 指纹变 → URL 变 → 客户端必然重新拉取，不会卡在旧版本上。
// 幂等：指纹计算前先把已存在的 ?v=xxx 抹掉，重复执行结果完全一致。
//
// 关键约束（踩过两次坑）：ES 模块按 URL 识别身份，同一个文件被两个不同
// URL 加载就是两份实例。所以「同一个文件必须永远只有一个 URL」：
//   · 扩展内部互引（tts/index.js <-> tts/edge.js 这种循环）→ 一律不带查询串，
//     与酒馆拼出来的入口 URL /scripts/extensions/<name>/index.js 完全一致。
//   · 跨出扩展目录引核心模块 → 一律带上页面同一个指纹，和 index.html 里
//     script.js?v=xxx 的 URL 对上。
// 违反任一条都会让循环依赖变成「跨实例循环」，直接抛 TDZ：
//   Cannot access 'X' before initialization。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ROOT = process.argv[2] || '/app/public';
// 第三方扩展由 patch-tavernhelper.mjs 负责（它要按自己的规则改 import），别在这里动
const SKIP_DIRS = new Set(['third-party', 'node_modules', '.git', 'characters', 'chats', 'user', 'backups']);
const V_RE = /\?v=[0-9a-f]{8,}/g;

const EXT_ROOT = path.join(ROOT, 'scripts', 'extensions');

function walk(dir, out = []) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name)) walk(p, out); }
        else out.push(p);
    }
    return out;
}

/** 该文件属于哪个扩展目录（不在扩展里则为 null） */
function extDirOf(file) {
    if (!file.startsWith(EXT_ROOT + path.sep)) return null;
    const rel = path.relative(EXT_ROOT, file).split(path.sep);
    if (rel.length < 2) return null;
    return path.join(EXT_ROOT, rel[0]);
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

// 2) HTML / CSS 引用
const RE_HTML = /(\b(?:src|href)=")(?!https?:|\/\/|data:|#|\/)([^"?#]+?\.(?:js|mjs|css|woff2?|png|ico|svg|json))(?:\?v=[0-9a-f]+)?(")/g;
const RE_CSS  = /(@import\s+url\(\s*['"]?)(?!https?:|\/\/|data:)([^'")]+?\.css)(?:\?v=[0-9a-f]+)?(['"]?\s*\))/g;

// 3) JS 的 import / from：按「是否跨出本扩展目录」决定加还是抹
const RE_JS = /(\bfrom\s*['"]|\bimport\s*['"]|\bimport\(\s*['"])(?!https?:|\/\/|data:)([^'"?]+?\.(?:js|mjs))(\?v=[0-9a-f]+)?(['"])/g;

function resolveSpec(spec, file) {
    if (spec.startsWith('/')) return path.join(ROOT, spec);
    return path.resolve(path.dirname(file), spec);
}

let files = 0, refs = 0;
for (const f of targets) {
    const src = fs.readFileSync(f, 'utf8');
    let out = src, n = 0;

    for (const re of [RE_HTML, RE_CSS]) {
        out = out.replace(re, (m, a, mid, b) => { n++; return a + mid + V + b; });
    }

    const own = extDirOf(f);
    out = out.replace(RE_JS, (m, a, spec, q, b) => {
        // 只有能落盘的路径才处理，裸模块名（如 'pinia'）原样保留
        if (!/^[./]/.test(spec)) return m;
        const abs = resolveSpec(spec, f);
        const sameExt = own && abs.startsWith(own + path.sep);
        const want = sameExt ? '' : V;   // 扩展内部互引：不带查询串
        if (q === want || (!q && !want)) return m;
        n++;
        return a + spec + want + b;
    });

    if (n === 0 || out === src) continue;
    files++; refs += n;
    fs.writeFileSync(f, out);
}
console.log(`asset-version: stamp=${STAMP} files=${files} refs=${refs}`);
