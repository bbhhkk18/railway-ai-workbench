# Railway AI 工作台全家桶

一个 Docker 镜像在 Railway 上跑完 6 个服务：AI 工作台（dsh）+ 文件管理（filebrowser）+ vless 代理（Cloudflare 临时隧道）+ SSH 调试入口。

**push 到仓库即自动构建部署**；所有密码/UUID 走环境变量注入，仓库内零密钥。

## 服务构成（supervisor 守护，进程崩溃自动重启）

| 服务 | 端口 | 说明 |
|------|------|------|
| nginx | 3082 | 公网入口，密码门 + 反代 |
| dsh | 3083 | AI 工作台（内部） |
| filebrowser | 3084 | 文件管理 /files/（内部） |
| xray | 10808 | vless 代理，仅本机（内部） |
| cloudflared | — | Cloudflare 临时隧道，暴露 xray |
| sshd | 22 | SSH 调试入口 |

## 从零部署（5 步）

1. **Fork 或使用本仓库**（Fork 到你自己的 GitHub 账号）
2. **Railway 建项目**：登录 [Railway](https://railway.app) → New Project → Deploy from GitHub repo → 选择仓库
3. **设置环境变量**：服务 → Variables，设置下面 3 个变量（**值必须自己生成**）
4. **生成域名**：服务 → Settings → Networking → Generate Domain，端口填 **3082**
5. **访问**：浏览器打开域名，用户 `admin` + 你设的 `WEB_PASSWORD` 登录

### 环境变量（缺一容器拒绝启动）

| 变量 | 说明 | 怎么生成 |
|------|------|----------|
| `WEB_PASSWORD` | 网页登录密码（用户 admin） | 自己编强密码 |
| `VLESS_UUID` | 代理节点 UUID | Linux/Mac 执行 `uuidgen`，或任意 UUID v4 |
| `SSH_PASSWORD` | root SSH 密码 | 强密码 |

> 容器有内建保护：检测到未设置或使用占位值，会拒绝启动，防止弱密码裸奔公网。

部署完成后，代理节点信息：协议 `vless + ws`，UUID = 你设的 `VLESS_UUID`，
服务器地址 = 容器内 `/root/.tunnel_domain` 文件中的 trycloudflare 域名（通过 SSH 查看），端口 443（TLS 由 Cloudflare 终结）。

Clash 客户端配置示例：

```yaml
- name: my-node
  type: vless
  server: <你的 trycloudflare 域名>
  port: 443
  uuid: <你设置的 VLESS_UUID>
  tls: true
  udp: false
  network: ws
  ws-opts:
    path: /
```

## 安全须知（务必阅读）

- **密码和 UUID 必须自己生成**，绝不复用你从任何地方看到的示例值
- **API Key（DeepSeek 等）只在 dsh 网页设置里填写**，不要写进任何文件或配置
- **永远不要把真实密码提交进 git**——环境变量就是为此存在的
- SSH 只用于调试，调试完建议关闭或改用密钥登录
- 部署完先验证密码门生效：浏览器无密码访问域名应返回 401

## ⚠️ 代理使用条款（重要）

- Cloudflare 临时隧道（trycloudflare.com）定位是**开发测试用途**
- **自用、小流量**一般没问题；**勿大流量使用**（4K 视频、大文件下载），**勿转手分享当公共节点**
- 违反 Cloudflare 服务条款会被封禁隧道甚至账号，**用法合规的风险由部署者本人承担**

## 数据持久化与运维

- 建议给服务挂 **Volume** 到 `/root/workspace`（filebrowser 工作区），重部署数据不丢
- 进程崩溃 supervisor 自动重启；容器重启自动拉起全部服务
- 修改任何配置 = 改仓库文件 → push → Railway 自动重建（2-8 分钟）
- 每次重部署后隧道域名会变：SSH 执行 `cat /root/.tunnel_domain` 获取最新值，更新客户端即可（UUID 不变）

## 构建细节

- 基于 Ubuntu 22.04，dsh 版本锁定 `0.1.1-rc.2`
- dsh 客户端 `isLoopbackHostname` 补丁（放行 `.up.railway.app`）在 Docker 构建期固化进镜像
- `RAILWAY_PUBLIC_DOMAIN` 由 Railway 自动注入，无需手工配置
