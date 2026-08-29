# AGENT.md — 全自动部署剧本（给 AI Agent 执行）

> **你是 AI 编码代理（如 ZCode），本文件是你的执行剧本。**
> 用户提供三样东西：GitHub token（repo 权限）、Railway token、本仓库地址。
> 你的任务：纯 API 完成全自动部署，最后把**所有凭据直接输出在对话里**给用户。
> 严禁把任何真实密码/UUID 写进 git 仓库或容器文件。

## ⚠️ 前提检查点（开始任何 Step 之前，必须停下与用户确认）

Railway 服务绑定 GitHub 仓库依赖 **Railway GitHub App** 授权，token 无法替代这一步。

**先在对话中问用户，并停下等待回答，不要自行跳过：**

> "你的 Railway 账号之前授权过 Railway 的 GitHub App 吗？授权范围包含本仓库吗？"

- 用户确认"已授权且覆盖本仓库" → 继续 Step 0/1
- 用户回答"没有 / 不确定" → 给出以下指引，然后**停下等用户回复"好了"**再继续：
  1. 打开 GitHub → Settings → Applications → Installed GitHub Apps → **Railway** → Configure
  2. 勾选目标仓库（或选 All repositories）→ Save
  3. （新仓库首次授权也可走 Railway 面板 New Project → Deploy from GitHub repo 流程）
- 即使确认过，Step 2.3 若仍报"找不到仓库/无权限"，立即回到本检查点与用户沟通，**不要反复重试**
- 同理，本文件中任何需要用户在浏览器操作或提供信息的步骤，都必须停下等用户，不要猜测或代替用户决定

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

## Step 1 确定部署源仓库

部署源是 `railway-ai-workbench` 仓库，按执行者身份二选一：

- **用户已拥有本仓库**（作者自部署，如 bbhhkk18）→ 无需 fork，部署源 = `<用户名>/railway-ai-workbench`
- **第三方使用者** → 先 Fork 本仓库，部署源 = fork 返回的 `full_name`：

```
POST https://api.github.com/repos/bbhhkk18/railway-ai-workbench/forks
```

返回 JSON 中取 `full_name`（形如 `<用户名>/railway-ai-workbench`）。fork 默认分支为 main。

> ⚠️ GitHub 不允许 fork 到同一账号：执行者与 bbhhkk18 是同一账号时走第一种，不要调 fork 接口。
> 绑定前用 `GET /repos/<部署源>` 验证仓库存在，404 则停下与用户确认，不要猜测或替换仓库名。

## Step 2 Railway 部署（按序执行，ID 从各步返回中提取）

**2.1 建项目** → 取 `projectId`（`workspaceId` 必填，先查账号工作空间）

```graphql
query { me { workspaces { id name } } }
# 取个人工作空间 id（通常只有一个），再：
mutation { projectCreate(input: { name: "ai-workbench", workspaceId: "<workspaceId>" }) { id name } }
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
    source: { repo: "<用户名>/railway-ai-workbench" }
  }) { ... }
}
```

> 服务创建会立即开始首次构建，此时变量还没设，首次部署 CRASHED 属预期，按 2.6 处理。

> ⚠️ 经 API 创建的服务**不会自动创建 deployment trigger**（面板建服务才有）：首次部署正常，但之后 push 到仓库不会触发自动构建。需要 push 自动部署时，按故障表「push 后没有自动构建」补建触发器。

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
mutation { serviceInstanceRedeploy(serviceId: "<serviceId>", environmentId: "...") }
```

> ⚠️ `serviceInstanceRedeploy` 是**原镜像重跑**，只让环境变量等运行时配置生效，不会拉取新代码；仓库代码有改动时要用 `serviceInstanceDeploy(serviceId: "...", environmentId: "...", latestCommit: true)`。

轮询部署状态（首次构建约 5-10 分钟）：

```graphql
query { project(id: "...") { services { edges { node {
  deployments(last: 1) { edges { node { id status } } } } } } } }
```

状态流转 `QUEUED → BUILDING → DEPLOYING → SUCCESS`；`FAILED/CRASHED` 见故障表。

**2.7 取隧道域名**（用 2.6 拿到的 deploymentId）

```graphql
query { deploymentLogs(deploymentId: "...", limit: 200) { message timestamp } }
```

在日志中找 `[tunnel] https://xxxx.trycloudflare.com` 行，即代理隧道域名。

> ⚠️ 每次重部署都会生成新域名：多次重部署后日志里会同时有多条 `[tunnel]` 行（旧容器产生的已失效），只有当前容器那条有效。拿不准就逐个 `curl -s -o /dev/null -w "%{http_code}" https://<域名>/` 验证——活隧道打到 xray 返回 400，死隧道返回 Cloudflare 530。`deploymentLogs` 对"原镜像重跑"的部署可能为空，此时改用 `environmentLogs(environmentId: "...") { message timestamp }`（运行时日志聚合了各次容器启动），或 SSH `cat /root/.tunnel_domain`。

**2.8 验证**

```bash
curl -s -o /dev/null -w "%{http_code}" https://<域名>/          # 期望 401
curl -s -o /dev/null -w "%{http_code}" -u "admin:<WEB_PASSWORD>" https://<域名>/   # 期望 200
```

## Step 3 输出凭据（直接打印在对话里，不写任何文件）

向用户输出一张凭据卡，必须包含：

1. **网页工作台**：`https://<域名>`，用户名 `admin`，密码 `<WEB_PASSWORD>`
2. **代理节点**：协议 vless+ws，服务器 `<隧道域名>`，端口 443，UUID `<VLESS_UUID>`，path `/`
3. **Clash 完整 config.yaml**（国内直连、其余走节点，模板见 README；server/uuid 替换为实际值）
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
| 用户改了仓库代码 | 无需重新 fork，Railway 构建部署源的 main 分支 |
| push 后没有自动构建 | **API 建的服务（serviceCreate）没有 deployment trigger，push 永远静默无效**（不是 webhook 抖动）：API 补建 `deploymentTriggerCreate(input:{projectId, serviceId, environmentId, provider:"github", repository:"<owner>/<repo>", branch:"main"})`（建后 autoDeploy 自动置为 enabled），或面板服务 Settings → Source 打开 Auto Deploy；应急本次构建 `serviceInstanceDeploy(latestCommit: true)`（注意 `serviceInstanceRedeploy` 不拉新代码） |
| 迁移 region 不生效 | 改 `multiRegionConfig`：键含连字符，必须用 **JSON 类型变量**传参（variables 传 `mrc: {"asia-southeast1-eqsg3a": {"numReplicas": 1}}`，新加坡；`asia-southeast1` 为同城弃用别名，旧短代码 `sin` 已失效），只改 `region` 字段会被覆盖 |

## 安全守则

- 两个 token 只在本次部署中使用，完成后提醒用户轮换
- 凭据只输出在对话中，**绝不**写入 git、容器文件或日志文件
- 本仓库永远不出现真实密码（环境变量是唯一注入通道）
