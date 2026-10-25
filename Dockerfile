FROM ghcr.io/sillytavern/sillytavern:latest

USER root

# 构建期预编译前端 lib.js（官方镜像运行期会重新编译，Render 免费实例 512M 编译失败 → /lib.js 404 → 整个前端白屏）
RUN node -e "import('./src/middleware/webpack-serve.js').then(m=>m.default().runWebpackCompiler({forceDist:true}))" \
 && cp "$(find dist/_webpack -name lib.js | head -1)" /app/prebuilt-lib.js \
 && ls -l /app/prebuilt-lib.js

COPY patch-lib.cjs /app/patch-lib.cjs
COPY entrypoint.sh /usr/local/bin/st-entrypoint.sh
RUN chmod +x /usr/local/bin/st-entrypoint.sh

ENV PORT=10000 \
    PREBUILT_LIB=/app/prebuilt-lib.js
EXPOSE 10000

ENTRYPOINT ["/usr/local/bin/st-entrypoint.sh"]
