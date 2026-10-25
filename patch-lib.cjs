// 让 SillyTavern 运行期不再用 webpack 编译 lib.js，直接吐出构建期预编译好的文件
const fs = require('node:fs');

const file = 'src/middleware/webpack-serve.js';
const prebuilt = process.env.PREBUILT_LIB;
if (!prebuilt || !fs.existsSync(prebuilt)) {
    console.log('[patch-lib] no prebuilt lib.js, leaving server untouched');
    process.exit(0);
}

let s = fs.readFileSync(file, 'utf8');

// 1) 补 fs 依赖
if (!s.includes("from 'node:fs'")) {
    s = s.replace("import path from 'node:path';", "import fs from 'node:fs';\nimport path from 'node:path';");
}

// 2) /lib.js 优先返回预编译文件
const sendLine = 'return res.sendFile(outputFile, { root: outputPath });';
if (s.includes(sendLine) && !s.includes('PREBUILT_LIB fallback')) {
    s = s.replace(sendLine, `if (process.env.PREBUILT_LIB && fs.existsSync(process.env.PREBUILT_LIB)) { /* PREBUILT_LIB fallback */ return res.sendFile(process.env.PREBUILT_LIB); }\n            ${sendLine}`);
}

// 3) 跳过运行期 webpack 编译（省内存、避免 404）
const marker = 'devMiddleware.runWebpackCompiler =';
const mi = s.indexOf(marker);
if (mi > -1 && !s.includes('skipping webpack compile')) {
    const brace = s.indexOf('{', s.indexOf('=>', mi));
    s = s.slice(0, brace + 1) + "\n        console.log('Using prebuilt lib.js, skipping webpack compile');\n        return Promise.resolve();\n" + s.slice(brace + 1);
}

fs.writeFileSync(file, s);
console.log('[patch-lib] patched', file);
