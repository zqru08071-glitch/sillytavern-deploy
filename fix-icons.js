// 把酒馆自带的 favicon / apple-touch-icon 换成冥王星的图标
const fs = require('fs');

const LINKS = [
    '<link rel="apple-touch-icon" sizes="180x180" href="img/icons/app-icon-180.png" />',
    '<link rel="icon" type="image/png" sizes="192x192" href="img/icons/app-icon-192.png" />',
    '<link rel="icon" type="image/png" sizes="512x512" href="img/icons/app-icon-512.png" />',
];

for (const file of ['public/index.html', 'public/login.html']) {
    if (!fs.existsSync(file)) continue;
    let html = fs.readFileSync(file, 'utf8');
    html = html.replace(/[ \t]*<link[^>]*rel="(?:apple-touch-icon|icon|shortcut icon)"[^>]*>\r?\n/g, '');
    html = html.replace(
        /([ \t]*)(<link[^>]*rel="apple-touch-icon"|<link[^>]*rel="icon")/g,
        '$1$2',
    );
    html = html.replace(
        /([ \t]*)(<link[^>]*rel="manifest"[^>]*>)/g,
        (_m, indent, tag) => [tag, ...LINKS.map(l => indent + l)].join('\n'),
    );
    fs.writeFileSync(file, html);
    console.log('icons patched:', file);
}
