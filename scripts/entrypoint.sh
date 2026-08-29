#!/bin/bash
# 启动前渲染配置: 密码/UUID/域名 全部来自 Railway 环境变量
set -e

# 安全校验: 拒绝用占位默认值启动
for v in WEB_PASSWORD VLESS_UUID SSH_PASSWORD; do
  if [ -z "${!v}" ] || [ "${!v}" = "changeme" ]; then
    echo "[entrypoint] 错误: 请在 Railway 环境变量中设置 $v" >&2
    exit 1
  fi
done

# nginx 密码门 (权限错了会 500: 必须 root:www-data + 640)
echo "admin:$(openssl passwd -apr1 "$WEB_PASSWORD")" > /etc/nginx/.htpasswd
chown root:www-data /etc/nginx/.htpasswd && chmod 640 /etc/nginx/.htpasswd

# SSH root 密码
echo "root:$SSH_PASSWORD" | chpasswd

# xray 配置 (注入 UUID)
mkdir -p /usr/local/etc/xray
sed "s/__UUID__/$VLESS_UUID/" /opt/stack/xray-template.json > /usr/local/etc/xray/config.json

# nginx: 容器能看到宿主机 48 核, worker 手动设 2
sed -i "s/^worker_processes .*/worker_processes 2;/" /etc/nginx/nginx.conf
cp /opt/stack/nginx-dsh.conf /etc/nginx/conf.d/dsh.conf

mkdir -p /run/sshd /root/workspace

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
