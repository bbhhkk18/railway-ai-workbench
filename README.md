# Railway AI 工作台全家桶

一个 Docker 镜像在 Railway 上跑完 6 个服务：AI 工作台（dsh）+ 文件管理（filebrowser）+ vless 代理（Cloudflare 临时隧道）+ SSH 调试入口。

**push 到仓库即自动构建部署**；所有密码/UUID 走环境变量注入，仓库内零密钥。

📖 **本 README 写给人看**（人工准备 + 手动部署路线）；🤖 交给 AI Agent 全自动部署的剧本在 **[AGENT.md](AGENT.md)**，两份配合使用。

---

## 一、人工准备清单（无论哪种部署方式都要做）

### 1. 账号

- GitHub 账号 + Railway 账号（Railway 免费试用额度即可，长期用 Hobby $5/月）

### 2. 生成两个 token（建议每次部署前新建、用完轮换）

- **GitHub**：头像 → Settings → Developer settings → Personal access tokens → Generate new token，勾选 `repo` 权限
- **Railway**：Railway 首页 → 头像 → Account Settings → Tokens → Create New Token

### 3. 授权 GitHub App（让 Railway 能读取你的仓库）

- GitHub → Settings → Applications → **Installed GitHub Apps** → **Railway** → **Configure**
- Repository access 选 **All repositories**（或至少勾选你的部署仓库）→ **Save**
- ⚠️ **只做授权这一步，不要提前在 Railway 面板建项目/服务**——那是部署流程自己的事，手动建了会留下空项目

---

## 二、方式 A：交给 AI Agent 全自动（推荐）

把下面这段话 + 两个 token 发给你的 AI Agent（如 ZCode）：

```
帮我全自动部署 AI 工作台。

仓库：<本仓库地址，或你 fork 后的地址>
这是我的 GitHub token 和 Railway token。
按仓库里的 AGENT.md 全自动部署，凭据直接输出在对话里。
遇到需要浏览器/人工确认的步骤，先停下来问我。
```

Agent 会自动完成：生成强密码和 UUID → fork/绑定仓库 → 建项目设变量 → 生成域名 → 等待构建 → 从部署日志取代理域名 → 验证 → **把所有凭据直接打印在对话里**。

期间 Agent 停下来问你的问题（授权状态等），如实回答即可。

---

## 三、方式 B：手动在仪表盘部署（5 步）

1. **Fork 本仓库**（右上角 Fork 到你的 GitHub 账号）
2. **Railway 建项目**：登录 [Railway](https://railway.app) → New Project → Deploy from GitHub repo → 选择你 fork 的仓库
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

---

## 四、部署完成后你要做的

1. 浏览器打开域名 → `admin` + WEB_PASSWORD 登录工作台
2. dsh 设置 → 模型 → 填入**你自己的** DeepSeek API Key
3. 按对话/凭据里的 Clash 配置配置代理
4. （建议）Clash 设置分流：支付、银行、国内域名走 DIRECT 直连——用代理 IP 操作支付容易触发平台风控
5. 用完的 token 记得轮换

---

## 五、服务构成（supervisor 守护，进程崩溃自动重启）

| 服务 | 端口 | 说明 |
|------|------|------|
| nginx | 3082 | 公网入口，密码门 + 反代 |
| dsh | 3083 | AI 工作台（内部） |
| filebrowser | 3084 | 文件管理 /files/（内部） |
| xray | 10808 | vless 代理，仅本机（内部） |
| cloudflared | — | Cloudflare 临时隧道，暴露 xray |
| sshd | 22 | SSH 调试入口 |

代理节点信息：协议 `vless + ws`，UUID = 你设的 `VLESS_UUID`，
服务器地址 = 容器内 `/root/.tunnel_domain`（或 Railway 部署日志中 `[tunnel]` 行），端口 443（TLS 由 Cloudflare 终结）。

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

---

## 六、安全须知（务必阅读）

- **密码和 UUID 必须自己生成**，绝不复用你从任何地方看到的示例值
- **API Key（DeepSeek 等）只在 dsh 网页设置里填写**，不要写进任何文件或配置
- **永远不要把真实密码提交进 git**——环境变量就是为此存在的
- SSH 只用于调试，调试完建议关闭或改用密钥登录
- 部署完先验证密码门生效：浏览器无密码访问域名应返回 401

## ⚠️ 代理使用条款（重要）

- Cloudflare 临时隧道（trycloudflare.com）定位是**开发测试用途**
- **自用、小流量**一般没问题；**勿大流量使用**（4K 视频、大文件下载），**勿转手分享当公共节点**
- 违反 Cloudflare 服务条款会被封禁隧道甚至账号，**用法合规的风险由部署者本人承担**

---

## 七、数据持久化与运维

- 建议给服务挂 **Volume** 到 `/root/workspace`（filebrowser 工作区），重部署数据不丢
- 进程崩溃 supervisor 自动重启；容器重启自动拉起全部服务
- 修改任何配置 = 改仓库文件 → push → Railway 自动重建（2-8 分钟）
- 每次重部署后隧道域名会变：SSH 执行 `cat /root/.tunnel_domain`，或看 Railway 部署日志中 `[tunnel]` 行（UUID 不变，只改 Clash 的 server 字段）

## 八、构建细节

- 基于 Ubuntu 22.04，dsh 版本锁定 `0.1.1-rc.2`，filebrowser `v2.63.23` / Xray `v26.3.27` / cloudflared `2026.8.2` 同样锁定（升级需改 Dockerfile）
- dsh 客户端 `isLoopbackHostname` 补丁（放行 `.up.railway.app`）在 Docker 构建期固化进镜像
- `RAILWAY_PUBLIC_DOMAIN` 由 Railway 自动注入，无需手工配置
