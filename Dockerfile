FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 基础工具 + nginx + sshd + supervisor + cron + Node 22
RUN apt-get update && apt-get install -y \
      curl ca-certificates make g++ python3 zstd \
      nginx-light libnginx-mod-http-subs-filter \
      openssh-server supervisor cron \
    && printf 'PermitRootLogin yes\n' > /etc/ssh/sshd_config.d/60-permit-root.conf \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# dsh 锁版本（构建在 Railway 构建机上进行，不受 1GB 容器内存限制）
RUN NODE_OPTIONS="--max-old-space-size=2048" npm install -g @deepseek-ai/dsh@0.1.1-rc.2 --no-audit --no-fund --no-progress

# isLoopback 补丁在构建期固化进镜像
COPY scripts/patch-dsh.sh /usr/local/bin/patch-dsh.sh
RUN chmod +x /usr/local/bin/patch-dsh.sh && patch-dsh.sh

# filebrowser / xray / cloudflared（按构建架构选择二进制，版本锁定保证构建可复现）
ARG TARGETARCH=amd64
RUN set -ex; \
    case "$TARGETARCH" in \
      arm64) FB=linux-arm64; XR=Xray-linux-arm64-v8a.zip; CF=cloudflared-linux-arm64 ;; \
      *)     FB=linux-amd64; XR=Xray-linux-64.zip;        CF=cloudflared-linux-amd64 ;; \
    esac; \
    curl -fsSL -o /tmp/fb.tar.gz "https://github.com/filebrowser/filebrowser/releases/download/v2.63.23/${FB}-filebrowser.tar.gz" \
    && tar xzf /tmp/fb.tar.gz -C /tmp filebrowser && mv /tmp/filebrowser /usr/local/bin/ \
    && curl -fsSL -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/v26.3.27/${XR}" \
    && python3 -c "import zipfile; zipfile.ZipFile('/tmp/xray.zip').extract('xray','/usr/local/bin')" \
    && curl -fsSL -o /usr/local/bin/cloudflared "https://github.com/cloudflare/cloudflared/releases/download/2026.8.2/${CF}" \
    && chmod +x /usr/local/bin/xray /usr/local/bin/cloudflared

# 栈配置
COPY supervisord.conf /etc/supervisor/conf.d/stack.conf
COPY configs/nginx-dsh.conf /opt/stack/nginx-dsh.conf
COPY configs/xray-template.json /opt/stack/xray-template.json
COPY scripts/entrypoint.sh scripts/tunnel.sh /opt/stack/
RUN chmod +x /opt/stack/entrypoint.sh /opt/stack/tunnel.sh

# 占位默认值: entrypoint 检测到未配置真实值会拒绝启动, 真实值走 Railway 环境变量
ENV RAILWAY_PUBLIC_DOMAIN=localhost \
    WEB_PASSWORD=changeme \
    VLESS_UUID=changeme \
    SSH_PASSWORD=changeme

EXPOSE 3082 22
ENTRYPOINT ["/opt/stack/entrypoint.sh"]
