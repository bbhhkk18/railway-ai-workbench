#!/bin/bash
# cloudflared 临时隧道包装:
# 后台启动 cloudflared, 抓取随机域名写入 /root/.tunnel_domain,
# 取完即清日志(隐私), 然后 wait 保持前台供 supervisor 监管;
# cloudflared 挂掉 → 脚本退出 → supervisor 重启本脚本 → 生成新域名
cloudflared tunnel --url http://127.0.0.1:10808 --no-autoupdate > /var/log/cloudflared.log 2>&1 &
CFPID=$!
for i in $(seq 1 30); do
  D=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" /var/log/cloudflared.log 2>/dev/null | head -1)
  if [ -n "$D" ]; then
    echo "$D" > /root/.tunnel_domain
    echo "[tunnel] $D"
    truncate -s 0 /var/log/cloudflared.log
    break
  fi
  sleep 2
done
wait $CFPID
