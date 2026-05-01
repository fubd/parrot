# Parrot Platform

基于 **Bun + Hono + MySQL + React + Nginx** 的轻量全栈 Monorepo 基座，所有运维操作通过 `Makefile` 一行命令完成。

```
Browser
  └─▶ Nginx :26033
        ├─ /api/*  ──▶ Hono Backend :26031 ──▶ MySQL :26032
        └─ /*      ──▶ React SPA (静态文件)
```

---

## 目录

- [技术栈](#技术栈)
- [目录结构](#目录结构)
- [快速开始](#快速开始)
- [本地开发](#本地开发)
- [数据库与迁移](#数据库与迁移)
- [数据库备份与恢复](#数据库备份与恢复)
- [构建与部署](#构建与部署)
- [API 接口](#api-接口)
- [环境变量参考](#环境变量参考)
- [Make 命令速查](#make-命令速查)
- [常见问题](#常见问题)
- [开发哲学](#开发哲学)
- [密钥管理](#密钥管理)

---

## 技术栈

| 层       | 技术                          | 说明                                                                    |
| -------- | ----------------------------- | ----------------------------------------------------------------------- |
| 前端     | React 19 + Rsbuild            | Rspack 驱动，极速编译；核心包通过 CDN 加载（classic runtime）           |
| 前端     | Ant Design 6 + React Router 7 | UI 组件库 v6 + 客户端路由（懒加载 + 404 兜底）                          |
| 前端     | CSS Modules（`.module.less`） | 组件样式自动作用域隔离，避免全局污染                                    |
| 后端     | Bun + Hono                    | 原生 HTTP server，零依赖 SQL 驱动（`Bun.sql`，内置连接池）              |
| 数据库   | MySQL 8.4                     | 原生 SQL，无 ORM                                                        |
| 网关     | Nginx 1.27                    | Gzip 压缩 + 静态资源缓存 + API 反向代理                                 |
| 编排     | Docker Compose + Makefile     | 本地开发 & 生产部署统一入口；Docker 负责服务，宿主机 Bun 负责构建与监听 |
| 镜像仓库 | 阿里云 ACR                    | 支持 `linux/amd64` 和 `arm64` 双架构                                    |
| 语言     | TypeScript 5.9（strict）      | 前后端统一 oxlint + oxfmt 规范                                          |

---

## 目录结构

```
parrot/
├── apps/
│   ├── backend/                # Hono API 服务
│   │   ├── src/
│   │   │   ├── index.ts        # 路由、中间件、启动入口
│   │   │   ├── env.ts          # 环境变量验证
│   │   │   └── db/
│   │   │       ├── client.ts   # Bun.sql 连接池 + 健康等待
│   │   │       └── run-migrations.ts  # golang-migrate 包装器 + 旧迁移表 bootstrap
│   │   ├── migrations/         # golang-migrate SQL 迁移（*.up.sql / *.down.sql）
│   │   ├── Dockerfile          # 包含 wget + HEALTHCHECK
│   │   ├── package.json
│   │   └── tsconfig.json
│   └── frontend/               # React SPA
│       ├── src/
│       │   ├── App.tsx         # 路由 + Ant Design 主题
│       │   ├── components/     # ErrorBoundary（捕获懒加载 chunk 失败）
│       │   ├── layouts/        # MainLayout（Header / Nav / Footer）+ CSS Modules
│       │   ├── pages/          # home / about / news（CSS Modules）
│       │   ├── routes/         # 路由配置与懒加载 + 404 兜底
│       │   ├── styles/         # 全局样式（global.less）
│       │   ├── assets/         # 静态资源
│       │   └── theme/          # Ant Design token 配置
│       ├── public/index.html   # 含 meta/OG 标签、favicon
│       ├── rsbuild.config.mjs
│       ├── package.json
│       └── tsconfig.json
├── docs/
│   └── DEVOPS.md               # 数据库与运维完整指南
├── infra/
│   └── nginx/
│       ├── default.conf        # 路由规则、Gzip、缓存策略
│       └── Dockerfile          # 直接 COPY 预构建前端产物到 Nginx 运行时
├── scripts/
│   ├── mysql-backup.sh         # 手动/定时备份（磁盘检查 + gzip 校验 + 保留期清理）
│   ├── mysql-restore.sh        # 从快照恢复（自动预恢复备份）
│   └── setup-backup-cron.sh    # 安装/卸载定时备份 cron job
├── docker-compose.yml          # 本地开发栈（含 dev 构建容器 + 挂载）
├── docker-compose.deploy.yml   # 生产部署栈（仅引用预构建镜像）
├── Makefile                    # 所有操作入口
├── .env.example                # 环境变量模板
└── tsconfig.base.json          # 共享 TypeScript 配置
```

---

## 快速开始

### 前置依赖

| 工具           | 版本要求 | 说明                              |
| -------------- | -------- | --------------------------------- |
| Docker Desktop | 最新版   | 包含 `docker compose` 和 `buildx` |
| Bun            | >= 1.0   | 本地构建、前端 watcher、代码检查  |
| make           | 系统自带 | macOS / Linux 均已内置            |
| SSH 密钥       | —        | 远端部署时需要免密登录目标服务器  |

> 本地开发默认要求宿主机安装 Bun。Docker 负责运行 `mysql / backend / nginx`，宿主机负责前端构建、watcher 和代码质量检查。

### 第一次启动

```bash
# 1. 克隆项目
git clone <repo-url> && cd parrot

# 2. 复制环境变量模板
cp .env.example .env
# 编辑 .env，至少填写 MYSQL_PASSWORD、MYSQL_ROOT_PASSWORD
# 以及 ALIYUN_* 相关字段（本地构建底层镜像与部署都会用到）

# 3. 一键启动
make start
```

`make start` 会依次完成：

1. 在宿主机安装 Bun 依赖
2. 构建前端静态资源到 `apps/frontend/dist/`
3. 使用 ACR 中已同步的共享基础镜像构建并启动服务
4. 按健康检查顺序启动 `mysql → backend → nginx`
5. 自动执行 SQL 迁移
6. 在宿主机启动前端 watcher 后台进程

启动后访问：**http://localhost:26033**

---

## 本地开发

### 修改前端

前端 watcher 运行在宿主机，由 Bun 直接监听 `apps/frontend/src/` 变化并重新输出到 `apps/frontend/dist/`。`make start` 和 `make restart` 都会自动确保 watcher 在运行：

```bash
# watcher 已随 make start / make restart 自动启动，直接编辑 apps/frontend/src/ 下的文件
# 保存 → watcher 自动重新编译到 dist/
# 浏览器刷新 http://localhost:26033 即可看到效果
```

`make start`、`make down` 和 `make restart` 会自动管理后台 watcher。如需前台查看实时编译输出：

```bash
make watch
```

后台 watcher 日志默认写入仓库根目录的 `.watch.log`。

### 修改后端

后端容器已配置 `bun --watch` + 源码卷挂载，文件变更时自动重启进程。在 Linux 环境（CI/CD、远程服务器）下直接生效。

macOS Docker 存在已知限制：VirtioFS 不传递宿主机文件事件到容器内的 inotify，因此 `--watch` 无法感知宿主机编辑。改完后执行：

```bash
make restart
```

等待几秒，后端重启并通过健康检查后自动恢复。

### 不使用 Docker 开发后端

如果想在宿主机跑后端并获得热重载（需要本地安装 Bun ≥ 1 且 MySQL 已在运行）：

```bash
# 运行迁移
make compose-migrate

# 启动带热重载的后端
bun --hot apps/backend/src/index.ts
```

### 代码检查与类型校验

以下命令都直接在宿主机通过 Bun 执行：

```bash
make lint          # oxlint 检查（前后端）
make format        # oxfmt 统一格式
make format-check  # oxfmt 格式校验
make type-check    # tsc --noEmit（前后端）
make install       # 安装 / 更新依赖（bun install）
```

仓库启用了 Husky `pre-commit` hook。提交代码时会自动运行 `oxfmt --check .` 和 `oxlint apps/frontend/src apps/backend/src`。

---

## 数据库与迁移

### 迁移机制

迁移文件位于 `apps/backend/migrations/`，使用 golang-migrate 命名：
`NNNN_description.up.sql` / `NNNN_description.down.sql`。业务查询仍使用 Bun.SQL，迁移执行交给 golang-migrate CLI。

当前迁移：

- `0001_init.up.sql` — 创建 `news_posts` 表并插入初始种子数据
- `0002_add_indexes.up.sql` — 添加复合索引 `(is_published, published_at DESC)`
- `0003_drop_redundant_index.up.sql` — 移除被复合索引覆盖的单列索引

迁移运行时特性：

- **幂等**：已执行版本记录在 `parrot_schema_migrations` 表，不会重复执行
- **成熟执行器**：由 golang-migrate 负责版本推进、dirty 状态和 MySQL 锁
- **旧库兼容**：如果旧 `schema_migrations` 表存在且新表不存在，会自动读取旧版本并 `force` 到对应版本，再继续执行新迁移

### 新增表结构变更

**永远不要直接修改已有的迁移文件**，只需新增文件：

```bash
# 新建迁移文件（自动编号）
make create-migration NAME=add_users_table
```

```sql
-- 0004_add_users_table.up.sql

CREATE TABLE users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

```sql
-- 0004_add_users_table.down.sql

DROP TABLE IF EXISTS users;
```

触发迁移：

```bash
# 在容器内执行迁移（推荐，环境与生产一致）
make compose-migrate
```

### 查看当前迁移状态

```bash
# 连接到 MySQL 容器
docker compose --env-file .env exec mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" parrot

# 查看已执行的迁移
SELECT * FROM parrot_schema_migrations ORDER BY version;
```

---

## 数据库备份与恢复

### 手动备份

```bash
# 本地开发环境备份（保存到 backups/mysql/）
make db-backup

# 远端生产环境备份（在服务器创建快照）
make remote-db-backup
```

备份文件命名格式：`parrot_20260101_030000.sql.gz`

备份脚本内置安全措施：

- **磁盘空间检查**：备份前检测可用空间（至少 10 MB），不足则中止
- **gzip 完整性校验**：备份完成后验证 `.gz` 文件完整性，损坏则自动删除并报错

默认保留最近 7 天的备份（可通过 `BACKUP_RETENTION_DAYS` 调整）。

### 自动定时备份

定时备份通过宿主机 `crontab` 调用项目自带 shell 脚本，不要求宿主机安装 `bun`。

将定时备份 cron job 安装到当前机器：

```bash
# 本地开发机（默认每天凌晨 3 点）
make setup-backup-cron

# 生产服务器
make remote-setup-backup-cron
```

查看已安装的 cron job：

```bash
crontab -l
```

自定义备份时间（示例：每天凌晨 2:30）：

```bash
BACKUP_SCHEDULE="30 2 * * *" make setup-backup-cron
```

卸载定时任务：

```bash
bash scripts/setup-backup-cron.sh --remove
```

### 从备份恢复

恢复脚本会在覆盖数据库前**自动创建一份安全备份**（`pre_restore_*.sql.gz`），以防误操作后可追溯。

```bash
# 本地恢复
make db-restore BACKUP_FILE=backups/mysql/parrot_20260101_030000.sql.gz

# 远端恢复（文件路径相对于服务器的 REMOTE_PATH）
make remote-db-restore BACKUP_FILE=backups/mysql/parrot_20260101_030000.sql.gz
```

> **警告**：恢复操作会用备份内容**完全覆盖**当前数据库，操作前务必确认或先做一次新备份。

### 数据卷说明

MySQL 数据存储在 Docker 命名卷 `parrot_mysql-data` 中。

| 操作                     | 安全性      | 说明                                       |
| ------------------------ | ----------- | ------------------------------------------ |
| `docker compose down`    | ✅ 安全     | 仅停止容器，数据卷保留                     |
| `docker compose down -v` | ❌ **危险** | 同时删除数据卷，数据永久丢失               |
| 换服务器迁移             | ⚠️ 需导出   | 代码目录之外，需先 `make remote-db-backup` |

---

## 构建与部署

### 配置前置检查

```bash
# 确认 .env 中以下字段已正确填写：
# ALIYUN_REGISTRY / IMAGE_NAMESPACE / ALIYUN_USERNAME / ALIYUN_PASSWORD
# REMOTE_HOST（格式：user@host）/ REMOTE_PATH
# VERSION（镜像 tag，如 1.0.0）
```

### 手动同步 ACR 基础镜像

项目的基础镜像统一同步到阿里云 ACR，命名不带 `parrot` 前缀，方便其他项目复用：

- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-bun:1-alpine`
- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-migrate:v4.19.1`
- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-nginx:1.27-alpine`
- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-mysql:8.4.4`

手动强制同步全部基础镜像：

```bash
make sync-base-images
```

日常 `make start` 默认**不再检查** ACR 中的基础镜像是否存在，前提是你已经手动同步过一次。

### 一键发布到生产

```bash
make remote-deploy
```

该命令按顺序执行：

1. **`make push`**：先本地构建前端静态资源，再构建后端和 Nginx Docker 镜像，推送到阿里云 ACR（Nginx 镜像仅 COPY 预构建产物，无需在 Docker 内安装依赖）
2. **`make remote-sync`**：通过 SSH 将 `.env`、`docker-compose.deploy.yml`、脚本文件同步到服务器
3. 在服务器上：
   - 拉取最新镜像
   - 启动 MySQL（若未运行）
   - 通过 golang-migrate 自动执行 SQL 迁移
   - 滚动重启 backend + nginx（不重建镜像）
   - 清理旧镜像
4. **`make remote-verify`**：验证健康检查端点，失败则自动触发回滚

### 发布特定版本

```bash
VERSION=1.2.0 make remote-deploy
```

### 仅推镜像（不部署）

```bash
make push
```

### 仅同步配置文件

```bash
make remote-sync
```

---

## 回滚

```bash
make remote-rollback
```

服务器上的 `.release.previous.env` 保存了上一次部署的版本信息，回滚命令从中读取版本号，拉取对应旧镜像，恢复运行状态，并自动验证健康检查。

> 回滚**不会**回滚数据库迁移。如需同时回滚数据库，请先手动恢复备份（`make remote-db-restore`），再执行代码回滚。

---

## API 接口

所有业务 API（`/api/*`）统一使用 POST 方法。后端启用了 CORS（`origin: *`）和请求日志中间件。

| 方法 | 路径                     | 描述                                                       | 响应示例                                                     |
| ---- | ------------------------ | ---------------------------------------------------------- | ------------------------------------------------------------ |
| GET  | `/healthz`               | 后端存活检查（含 DB 连通性），供 Docker/nginx 健康检查使用 | `{"status":"ok","service":"backend","database":"connected"}` |
| POST | `/api/health`            | 服务健康状态 + 版本                                        | `{"success":true,"data":{...}}`                              |
| POST | `/api/v1/system/summary` | 应用信息 + 新闻统计                                        | 见下方示例                                                   |
| POST | `/api/v1/news`           | 全部已发布新闻列表（按发布时间倒序）                       | `{"success":true,"data":{"items":[...]}}`                    |
| POST | `/api/v1/meta`           | 端口元数据                                                 | `{"success":true,"data":{"appName":"...","ports":{...}}}`    |

**`POST /api/v1/system/summary` 响应示例：**

```json
{
  "success": true,
  "data": {
    "appName": "Parrot",
    "version": "latest",
    "environment": "production",
    "publishedNewsCount": 3,
    "latestPublishedAt": "2026-03-22 08:30:00",
    "services": ["React 19 + Rsbuild", "Hono + Bun", "Bun.sql (MySQL)", "Nginx + Docker Compose"]
  }
}
```

**`POST /api/v1/news` 响应示例：**

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": 1,
        "slug": "full-stack-foundation",
        "title": "Full-stack foundation is ready",
        "summary": "...",
        "body": "...",
        "publishedAt": "2026-03-22"
      }
    ]
  }
}
```

**错误响应格式（统一）：**

```json
// 404 - 路由不存在
{ "success": false, "message": "POST /api/v1/xxx not found" }

// 500 - 服务器内部错误
{ "success": false, "message": "具体错误描述" }
```

---

## 环境变量参考

复制 `.env.example` 为 `.env` 并按需修改。

### 应用配置

| 变量       | 默认值        | 说明                              |
| ---------- | ------------- | --------------------------------- |
| `APP_NAME` | `Parrot`      | 应用名称（出现在 API 响应中）     |
| `NODE_ENV` | `development` | 运行环境，生产时设为 `production` |
| `VERSION`  | `latest`      | 镜像版本 tag，用于部署追踪        |

### 端口配置

| 变量            | 默认值  | 说明                                |
| --------------- | ------- | ----------------------------------- |
| `FRONTEND_PORT` | `26030` | （保留，前端不使用独立 dev server） |
| `BACKEND_PORT`  | `26031` | Hono 后端宿主机映射端口             |
| `MYSQL_PORT`    | `26032` | MySQL 宿主机映射端口                |
| `NGINX_PORT`    | `26033` | Nginx 网关宿主机映射端口（主入口）  |

### 数据库配置

| 变量                  | 默认值      | 说明                                 |
| --------------------- | ----------- | ------------------------------------ |
| `DATABASE_HOST`       | `127.0.0.1` | 本地直连时使用；容器内固定为 `mysql` |
| `DATABASE_PORT`       | `26032`     | 本地直连端口                         |
| `MYSQL_DATABASE`      | `parrot`    | 数据库名                             |
| `MYSQL_USER`          | `parrot`    | 业务账号                             |
| `MYSQL_PASSWORD`      | —           | 业务账号密码                         |
| `MYSQL_ROOT_PASSWORD` | —           | root 密码（备份 / 迁移使用）         |

### 备份配置

| 变量                    | 默认值      | 说明                                            |
| ----------------------- | ----------- | ----------------------------------------------- |
| `BACKUP_RETENTION_DAYS` | `7`         | 保留最近 N 天的备份，超期自动删除（0 = 不删除） |
| `BACKUP_SCHEDULE`       | `0 3 * * *` | cron 表达式，用于 `make setup-backup-cron`      |

### 阿里云 ACR（部署时必填）

| 变量              | 示例值                              | 说明                    |
| ----------------- | ----------------------------------- | ----------------------- |
| `ALIYUN_REGISTRY` | `registry.cn-hangzhou.aliyuncs.com` | ACR 域名                |
| `IMAGE_NAMESPACE` | `my-namespace`                      | 命名空间                |
| `ALIYUN_USERNAME` | `my@example.com`                    | 登录账号                |
| `ALIYUN_PASSWORD` | —                                   | 登录密码（勿提交 Git）  |
| `MIGRATE_VERSION` | `v4.19.1`                           | golang-migrate 镜像版本 |

### 远端部署（部署时必填）

| 变量          | 示例值             | 说明                   |
| ------------- | ------------------ | ---------------------- |
| `REMOTE_HOST` | `root@1.2.3.4`     | SSH 目标（需免密登录） |
| `REMOTE_PATH` | `/root/app/parrot` | 服务器上的项目目录     |

---

## Make 命令速查

```bash
make help               # 查看所有可用命令
```

### 开发

| 命令               | 说明                                                       |
| ------------------ | ---------------------------------------------------------- |
| `make start`       | 安装依赖、构建前端、构建镜像、执行迁移，并启动本地开发环境 |
| `make down`        | 停止本地 watcher 和 Docker 栈                              |
| `make restart`     | 重新执行迁移并重启 backend + nginx，随后确保 watcher 存活  |
| `make logs`        | 实时查看所有服务日志                                       |
| `make ps`          | 查看服务运行状态                                           |
| `make dev-backend` | 在 Docker 中启动后端（重建容器）                           |
| `make watch`       | 前台运行前端 watcher                                       |

### 数据库

| 命令                              | 说明                      |
| --------------------------------- | ------------------------- |
| `make create-migration NAME=...`  | 创建 up/down 迁移文件     |
| `make compose-migrate`            | 在容器内执行迁移          |
| `make db-backup`                  | 手动本地备份              |
| `make db-restore BACKUP_FILE=...` | 从本地快照恢复            |
| `make setup-backup-cron`          | 安装本地定时备份 cron job |

### 构建与代码质量

| 命令                  | 说明                    |
| --------------------- | ----------------------- |
| `make install`        | 安装所有 workspace 依赖 |
| `make build`          | 运行工作区构建脚本      |
| `make frontend-build` | 构建前端静态资源        |
| `make lint`           | oxlint 检查             |
| `make format`         | oxfmt 格式化            |
| `make format-check`   | oxfmt 格式校验          |
| `make type-check`     | TypeScript 类型检查     |

### 部署（生产）

| 命令                                     | 说明                                     |
| ---------------------------------------- | ---------------------------------------- |
| `make push`                              | 构建并推送 Docker 镜像到 ACR             |
| `make sync-base-images`                  | 强制同步共享基础镜像到 ACR               |
| `make remote-deploy`                     | 一键完整部署（包含推镜像 + 同步 + 迁移） |
| `make remote-rollback`                   | 回滚到上一次部署的版本                   |
| `make remote-verify`                     | 验证远端服务健康状态                     |
| `make remote-logs`                       | 实时查看远端服务日志                     |
| `make remote-db-backup`                  | 在服务器创建数据库快照                   |
| `make remote-db-restore BACKUP_FILE=...` | 从快照恢复服务器数据库                   |
| `make remote-setup-backup-cron`          | 在服务器安装定时备份任务                 |

---

## 常见问题

### `make push` / `make remote-deploy` 卡在 "Syncing multi-arch image..."

项目会先把官方基础镜像同步到阿里云 ACR，网络较慢时耗时较长（10~30 分钟）。这是为了确保本地和生产都基于同一套可复用 ACR 基础镜像。

### `make start` 提示基础镜像不存在或拉取失败

说明当前 ACR 中还没有同步所需的共享基础镜像。先手动执行一次：

```bash
make sync-base-images
```

同步完成后再重新执行：

```bash
make start
```

### 后端启动报 "Database connection failed"

MySQL 启动比后端慢。后端内置了最多 20 次重试（每次间隔 2 秒），正常情况下会等待。如果始终失败：

```bash
# 查看 MySQL 日志
make logs

# 检查 .env 中的密码是否与容器匹配
# 如果改过密码但容器已有旧数据卷，需要先删卷重建：
docker compose --env-file .env down -v   # ⚠️ 会清空数据
make start
```

### 迁移报错 "Dirty database version"

golang-migrate 会在失败时标记 dirty 状态，避免后续迁移继续破坏数据库。先修复失败原因，再确认数据库结构处于哪个版本，最后执行：

```bash
docker compose --env-file .env run --rm --no-deps backend bun run migrate force <version>
make compose-migrate
```

### Nginx 返回 502

后端尚未就绪，等待几秒后刷新；或检查：

```bash
make ps       # 查看 backend 是否 healthy
make logs     # 查看错误日志
```

### 前端改了代码但页面没有变化

1. 查看 watcher 日志：`tail -f .watch.log`
2. 重新执行 `make start`，确认 watcher 被自动拉起
3. 如需前台观察编译过程，执行 `make watch`

### 想修改 Nginx 端口

在 `.env` 中修改 `NGINX_PORT`，然后：

```bash
make restart
```

---

## 开发哲学

1. **简单之美**：不引入 ORM、不用重型框架，原生 SQL 表达业务，原生 HTTP server 处理请求。复杂性在引入前就被消灭。

2. **错误前置**：后端全局 `onError` 统一兜底，路由层不写冗长的 `try/catch`，直接 `throw`，由网关格式化成标准 JSON 返回。前端 `ErrorBoundary` 捕获懒加载 chunk 失败，防止白屏。未匹配路由由 `notFound` 统一处理。后端收到 `SIGINT`/`SIGTERM` 时优雅关闭连接池。

3. **零运行耗损**：Gzip 交给 Nginx，基础依赖（React / React DOM）交给 CDN，慢 SQL 交给索引优化器，代码只关心业务逻辑。

4. **样式隔离**：CSS Modules（`.module.less`）自动生成哈希类名，组件样式零冲突，告别全局污染。

---

## 密钥管理

所有敏感配置（数据库密码、ACR 密钥、SSH 目标等）存放在 `.env` 文件中，该文件已被 `.gitignore` 屏蔽，**严禁提交到 Git**。

`.env` 的备份方案（按推荐程度排序）：

| 方案                               | 适用场景              |
| ---------------------------------- | --------------------- |
| 1Password / Bitwarden Secure Note  | 个人或小团队，最轻量  |
| 阿里云 KMS / AWS Secrets Manager   | 团队协作，合规要求    |
| GitHub Actions / GitLab CI Secrets | 全自动化 CI/CD 流水线 |
