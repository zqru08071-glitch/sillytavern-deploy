// 酒馆助手（JS-Slash-Runner）在「带资源指纹的酒馆」上的补丁，启动时执行，幂等。
//
// 症状：睡莲等美化里的美化块不渲染，代码块直接露出来；
//      TH.render 的 runtimes 恒为空，TavernHelper.getChatMessages() 恒为 0 条。
//
// 原因 1（致命）：ES 模块按 URL 识别。index.html 里 script.js 是
//   /script.js?v=<指纹>，第三方扩展里却写死 import "../../../script.js"
//   （不带查询串）→ 浏览器加载了第二份 script.js，助手的 chat 恒为空，
//   渲染器遍历 0 条消息，于是什么都不渲染。
//   修法：扩展里指向自己包外的 import 一律改成「绝对路径 + 同一指纹」。
//
// 原因 2：4.11.3 在模块顶层求值 promptManager.render（此刻还是 null），
//   整包抛 TypeError 不加载。改成惰性取值。
//
// 原因 3：manifest 的 js 带查询串就得手工换版本号。统一输出 app.js，
//   配合 nginx 对 third-party 目录 no-store，改完刷新即生效。
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.argv[2] || '/app/public';
const THIRD = path.join(ROOT, 'scripts', 'extensions', 'third-party');
if (!fs.existsSync(THIRD)) { console.log('patch-tavernhelper: 无 third-party 目录，跳过'); process.exit(0); }

let stamp = '';
try {
  const m = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8').match(/script\.js\?v=([0-9a-f]{8,})/);
  if (m) stamp = m[1];
} catch {}
const V = stamp ? '?v=' + stamp : '';

const dirs = fs.readdirSync(THIRD, { withFileTypes: true })
  .filter(e => e.isDirectory() && e.name.startsWith('JS-Slash-Runner'))
  .map(e => path.join(THIRD, e.name));
if (dirs.length === 0) { console.log('patch-tavernhelper: 酒馆助手未安装，跳过'); process.exit(0); }

function rewrite(spec, base) {
  if (/^[a-z]+:/i.test(spec) || spec.startsWith('//')) return null;
  const abs = spec.startsWith('/') ? path.join(ROOT, spec) : path.resolve(base, spec);
  if (abs.startsWith(THIRD + path.sep)) return null;   // 扩展自己包内引用不动
  if (!fs.existsSync(abs)) return null;
  return '/' + path.relative(ROOT, abs).split(path.sep).join('/') + V;
}

let handled = 0;
for (const DIR of dirs) {
  const dist = path.join(DIR, 'dist');
  const idx = path.join(dist, 'index.js');
  if (!fs.existsSync(idx)) continue;

  let s = fs.readFileSync(idx, 'utf8');
  let ops = 0;

  s = s.replace(/(\bfrom\s*["'])([^"']+?\.(?:js|mjs))(?:\?v=[0-9a-f]+)?(["'])/g, (m, a, spec, b) => {
    const r = rewrite(spec, dist);
    if (!r) return m;
    if (a + r + b !== m) ops++;
    return a + r + b;
  });

  s = s.replace(/(\bimport\(\s*["'])([^"']+?\.(?:js|mjs))(?:\?v=[0-9a-f]+)?(["']\s*\))/g, (m, a, spec, b) => {
    const r = rewrite(spec, dist);
    if (!r) return m;
    if (a + r + b !== m) ops++;
    return a + r + b;
  });

  const pm = /renderPromptManager:(\w+)\.render(,renderPromptManagerDebounced:)?\1\.renderDebounced/g;
  if (pm.test(s)) {
    pm.lastIndex = 0;
    s = s.replace(pm, (_m, v) =>
      'renderPromptManager:(...e)=>{const p=' + v + '||window.SillyTavern?.getContext?.()?.promptManager;return p&&p.render&&p.render(...e)},' +
      'renderPromptManagerDebounced:(...e)=>{const p=' + v + '||window.SillyTavern?.getContext?.()?.promptManager;return p&&p.renderDebounced&&p.renderDebounced(...e)}');
    ops++;
  }

  // 产物用内容哈希命名：内容变了 URL 就变（浏览器必然拿到新的），
  // 内容没变 URL 不变（缓存照常命中）。这样也不必依赖 nginx 的 no-store。
  const hash = crypto.createHash('sha1').update(s).digest('hex').slice(0, 10);
  const jsName = 'dist/app.' + hash + '.js';
  const jsOut = path.join(DIR, jsName);
  if (!fs.existsSync(jsOut)) fs.writeFileSync(jsOut, s);
  // 清掉上一版的产物，别让 dist 越滚越大
  for (const f of fs.readdirSync(dist)) {
    if (/^app\.[0-9a-f]{10}\.(js|css)$/.test(f) && 'dist/' + f !== jsName) fs.unlinkSync(path.join(dist, f));
  }

  let cssName = null;
  const css = path.join(dist, 'index.css');
  if (fs.existsSync(css)) {
    const ch = crypto.createHash('sha1').update(fs.readFileSync(css)).digest('hex').slice(0, 10);
    cssName = 'dist/app.' + ch + '.css';
    if (!fs.existsSync(path.join(DIR, cssName))) fs.copyFileSync(css, path.join(DIR, cssName));
    for (const f of fs.readdirSync(dist)) {
      if (/^app\.[0-9a-f]{10}\.css$/.test(f) && 'dist/' + f !== cssName) fs.unlinkSync(path.join(dist, f));
    }
  }

  const mf = path.join(DIR, 'manifest.json');
  const man = JSON.parse(fs.readFileSync(mf, 'utf8'));
  if (man.js !== jsName || man.auto_update !== false || (cssName && man.css !== cssName)) {
    man.js = jsName;
    if (cssName) man.css = cssName;
    man.auto_update = false;
    ops++;
  }
  fs.writeFileSync(mf, JSON.stringify(man, null, 2));

  console.log('patch-tavernhelper: ' + path.basename(DIR) + ' stamp=' + (stamp || '(none)') + ' ops=' + ops);
  handled++;
}
if (handled === 0) console.log('patch-tavernhelper: 没有可处理的 dist/index.js');
