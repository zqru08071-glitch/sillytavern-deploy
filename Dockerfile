FROM node:22-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends git git-lfs ca-certificates tini \
 && git lfs install --system \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone --depth 1 --branch release https://github.com/SillyTavern/SillyTavern.git . \
 && rm -rf .git

ENV NODE_ENV=production

# 构建期把前端 lib.js 编译好
RUN npm ci --no-audit --no-fund --loglevel=error --no-progress \
 && node ./docker/build-lib.js \
 && rm -rf ./docker \
 && npm cache clean --force

# 关键修复：把编好的 lib.js 直接放进 public，让 express.static 直接命中，/lib.js 不再 404 白屏
RUN LIB="$(find /app/dist -name lib.js -type f | head -1)" \
 && echo "prebuilt lib: $LIB" \
 && test -s "$LIB" \
 && cp "$LIB" /app/public/lib.js \
 && ls -l /app/public/lib.js

# 运行期也别再跑 webpack（免费实例内存小，重编译会失败）
RUN sed -i "s#await webpackMiddleware.runWebpackCompiler({ pruneCache: true });#console.log('Using prebuilt frontend libraries');#" src/server-main.js \
 && grep -n "prebuilt frontend" src/server-main.js

# 关键修复 2：/lib.js 会被 webpack 中间件先截住，去不存在的 dist 产物里找 → 404 白屏。
# 改成直接吐 public/lib.js
RUN sed -i "s#return res.sendFile(outputFile, { root: outputPath });#return res.sendFile('lib.js', { root: path.join(process.cwd(), 'public') });#" src/middleware/webpack-serve.js  && grep -n "public" src/middleware/webpack-serve.js

RUN mkdir -p /app/config /app/data /app/backups /app/plugins /app/public/scripts/extensions/third-party

COPY entrypoint.sh /usr/local/bin/st-entrypoint.sh
RUN chmod +x /usr/local/bin/st-entrypoint.sh

ENV PORT=10000
ENV NODE_OPTIONS=--max-old-space-size=400
EXPOSE 10000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/st-entrypoint.sh"]
