# AGENT.md — 全自动部署剧本（给 AI Agent 执行）

> **你是 AI 编码代理（如 ZCode），本文件是你的执行剧本。**
> 用户提供三样东西：GitHub token（repo 权限）、Railway token、本仓库地址。
> 你的任务：纯 API 完成全自动部署，最后把**所有凭据直接输出在对话里**给用户。
> 严禁把任何真实密码/UUID 写进 git 仓库或容器文件。

## 前提（唯一需要人工的一步）

Railway 服务绑定 GitHub 仓库依赖 **Railway GitHub App** 授权。
- 判断：执行 Step 2.2 时若报"找不到仓库/无权限"，即为未授权
- 引导用户浏览器完成：Railway → New Project → Deploy from GitHub repo → Install GitHub App（建议选 All repositories），完成后你重试即可
- 用户此前部署过 Railway 项目则大概率已授权，直接往下走

## GraphQL 端点（Railway 全部操作都用它）

```
POST https://backboard.railway.app/graphql/v2
Header: Authorization: Bearer <RAILWAY_TOKEN>
```

GitHub REST API：`https://api.github.com`，Header: `Authorization: token <GITHUB_TOKEN>`

## Step 0 生成密钥（本地生成，勿写入任何文件）

```bash
WEB_PASSWORD=$(openssl rand -base64 12 | tr '+/' 'Aa')      # 12 位强密码
VLESS_UUID=$(python3 -c "import uuid; print(uuid.uuid4())") # UUID v4
SSH_PASSWORD=$(openssl rand -base64 12 | tr '+/' 'Aa')
```

记住三个值，最后随凭据卡输出给用户。

## Step 1 Fork 仓库

```
POST https://api.github.com/repos/bbhhkk18/railwaysshtemplate/forks
```

返回 JSON 中取 `full_name`（形如 `<用户名>/railwaysshtemplate`）。fork 默认分支为 main。

## Step 2 Railway 部署（按序执行，ID 从各步返回中提取）

**2.1 建项目** → 取 `projectId`

```graphql
mutation { projectCreate(input: { name: "ai-workbench" }) { ... } }
```

**2.2 查环境** → 取 `environmentId`（production）

```graphql
query { project(id: "<projectId>") { environments { edges { node { id name } } } } }
```

**2.3 建服务并绑定仓库源** → 取 `serviceId`

```graphql
mutation {
  serviceCreate(input: {
    projectId: "<projectId>", name: "workbench",
    source: { repo: "<用户名>/railwaysshtemplate" }
  }) { ... }
}
```

> 服务创建会立即开始首次构建，此时变量还没设，首次部署 CRASHED 属预期，按 2.6 处理。

**2.4 设置环境变量 ×3**（值来自 Step 0，一个都不能少）

```graphql
mutation { variableUpsert(input: {
  projectId: "...", environmentId: "...", serviceId: "...",
  name: "WEB_PASSWORD", value: "<WEB_PASSWORD>"   # VLESS_UUID / SSH_PASSWORD 同法
}) }
```

**2.5 生成公网域名**（自动命名，绑定 3082 端口）

```graphql
mutation { serviceDomainCreate(input: {
  serviceId: "...", environmentId: "...", targetPort: 3082
}) { ... } }
```

**2.6 触发重部署（让变量生效）并等待完成**

```graphql
mutation { serviceInstanceRedeploy(id: "<serviceId>", environmentId: "...") ... }
```

轮询部署状态（首次构建约 5-10 分钟）：

```graphql
query { project(id: "...") { services { edges { node {
  deployments(last: 1) { edges { node { id status } } } } } } } }
```

状态流转 `QUEUED → BUILDING → DEPLOYING → SUCCESS`；`FAILED/CRASHED` 见故障表。

**2.7 取隧道域名**（用 2.6 拿到的 deploymentId）

```graphql
query { deploymentLogs(deploymentId: "...", limit: 200) { ... } }
```

在日志中找 `[tunnel] https://xxxx.trycloudflare.com` 行，即代理隧道域名。

**2.8 验证**

```bash
curl -s -o /dev/null -w "%{http_code}" https://<域名>/          # 期望 401
curl -s -o /dev/null -w "%{http_code}" -u "admin:<WEB_PASSWORD>" https://<域名>/   # 期望 200
```

## Step 3 输出凭据（直接打印在对话里，不写任何文件）

向用户输出一张凭据卡，必须包含：

1. **网页工作台**：`https://<域名>`，用户名 `admin`，密码 `<WEB_PASSWORD>`
2. **代理节点**：协议 vless+ws，服务器 `<隧道域名>`，端口 443，UUID `<VLESS_UUID>`，path `/`
3. **Clash 配置 YAML**（server/uuid 替换为实际值）
4. **SSH**（可选调试用）：Railway 面板 → 服务 Settings → Networking → Generate Domain 选 TCP Proxy、端口 22；密码 `<SSH_PASSWORD>`
5. **维护提示**：重部署后隧道域名会变（重新执行 2.7 获取，UUID 不变）；dsh 的 API Key 在重部署后需在设置页重填；代理勿大流量、勿转手分享（Cloudflare 条款风险自担）
6. **提醒用户轮换两个 token**

## 故障速查

| 症状 | 处理 |
|------|------|
| serviceCreate 报找不到仓库/无权限 | GitHub App 未授权 → 转人工（见前提） |
| 首次部署 CRASHED | 变量未生效 → 确认 2.4 三个变量都成功后执行 2.6 |
| 日志中无 `[tunnel]` 行 | 镜像较旧 → SSH 方式：先在面板生成 TCP Proxy(22)，`ssh root@<地址> -p <端口> 'cat /root/.tunnel_domain'` |
| 401 验证失败 | htpasswd 渲染失败，查部署日志 entrypoint 输出 |
| 用户改了仓库代码 | 无需重新 fork，Railway 构建 fork 的 main 分支 |

## 安全守则

- 两个 token 只在本次部署中使用，完成后提醒用户轮换
- 凭据只输出在对话中，**绝不**写入 git、容器文件或日志文件
- 本仓库永远不出现真实密码（环境变量是唯一注入通道）
