#!/bin/bash
# dsh 客户端补丁: isLoopbackHostname() 放行 .up.railway.app
# 公网域名访问时客户端误判非 loopback, 导致设置页不可用
# 路径自适应: 兼容 Debian(npm -g /usr/lib) 与 NodeSource(/usr/local/lib) 布局
set -e
TARGET=$(find /usr/local/lib/node_modules /usr/lib/node_modules \
  -path "*dsh-client-connection/lib/client.js" 2>/dev/null | head -1)
if [ -z "$TARGET" ]; then
  echo "[patch] 未找到 dsh client.js" >&2
  exit 1
fi
if grep -q 'up\.railway\.app' "$TARGET"; then
  echo "[patch] 已打补丁, 跳过"
  exit 0
fi
python3 - "$TARGET" << 'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'if (hostname === "localhost" || hostname === "[::1]") return true;'
new = old + '\n\t\t\tif (hostname.endsWith(".up.railway.app")) return true;'
assert old in s, "未找到目标代码行"
open(p, "w").write(s.replace(old, new, 1))
print("[patch] 补丁完成:", p)
PYEOF
grep -q 'up\.railway\.app' "$TARGET" || { echo "[patch] 校验失败" >&2; exit 1; }
