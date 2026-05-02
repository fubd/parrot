# Parrot

基于 **Bun + Hono + MySQL + React + Nginx** 的轻量全栈 Monorepo。所有操作通过 `make` 一行命令完成。

```
Browser
  └─▶ Nginx :26033
        ├─ /api/*  ──▶ Hono Backend :26031 ──▶ MySQL :26032
        └─ /*      ──▶ React SPA (静态文件)
```

---

## 快速开始

```bash
# 1. 克隆并配置
cp .env.example .env
# 编辑 .env，填写 MYSQL_PASSWORD、MYSQL_ROOT_PASSWORD 及 ALIYUN_* 字段

# 2. 同步基础镜像到 ACR（仅首次需要）
make sync-base-images

# 3. 启动
make start
```

访问 **http://localhost:26033**

`make start` 自动完成：安装依赖 → 构建前端 → 构建镜像 → 执行数据库迁移 → 启动所有服务 → 启动前端 watcher。

---

## 技术栈

| 层     | 技术                              | 说明                                    |
| ------ | --------------------------------- | --------------------------------------- |
| 前端   | React 19 + Rsbuild + Ant Design 6 | Rspack 驱动，CDN externals，CSS Modules |
| 后端   | Bun + Hono                        | 原生 HTTP server，`Bun.sql` 直连 MySQL  |
| 数据库 | MySQL 8.4                         | 原生 SQL，无 ORM                        |
| 网关   | Nginx 1.27                        | Gzip + 静态缓存 + API 反向代理          |
| 编排   | Docker Compose + Makefile         | 统一入口，宿主机 Bun 负责构建和检查     |
| 镜像   | 阿里云 ACR                        | `linux/amd64` + `linux/arm64` 双架构    |

---

## 目录结构

```
parrot/
├── apps/
│   ├── backend/                 # Hono API
│   │   ├── src/
│   │   │   ├── index.ts         # 路由、中间件、启动
│   │   │   ├── env.ts           # 环境变量验证
│   │   │   └── db/
│   │   │       ├── client.ts    # Bun.sql 连接池
│   │   │       └── run-migrations.ts  # golang-migrate 包装器
│   │   └── migrations/          # *.up.sql / *.down.sql
│   └── frontend/                # React SPA
│       ├── src/
│       │   ├── pages/           # home / news / about
│       │   ├── components/      # ErrorBoundary
│       │   └── routes/          # 路由配置 + 懒加载
│       └── rsbuild.config.mjs
├── docs/
│   ├── DATABASE.md              # 数据库迁移、维护、备份
│   └── DEPLOY.md                # 构建、发布、回滚
├── infra/nginx/                 # Nginx 配置 + Dockerfile
├── scripts/                     # 备份/恢复/cron 脚本
├── docker-compose.yml           # 本地开发栈
├── docker-compose.deploy.yml    # 生产部署栈
└── Makefile                     # 所有操作入口
```

---

## 本地开发

### 修改前端

Watcher 由 `make start` 自动在后台启动，编辑 `apps/frontend/src/` 后自动编译到 `dist/`，浏览器刷新即可。

```bash
make watch   # 前台查看编译输出
tail -f .watch.log   # 查看后台 watcher 日志
```

### 修改后端

Linux 环境：容器 `bun --watch` + 卷挂载，保存即自动重启。

macOS 环境：VirtioFS 不传递文件事件，改完后执行：

```bash
make restart
```

### 代码检查

所有检查命令在宿主机通过 Bun 执行：

```bash
make lint          # oxlint
make format        # oxfmt 格式化
make format-check  # oxfmt 格式校验
make type-check    # tsc --noEmit
```

---

## API 接口

所有业务 API（`/api/*`）使用 POST 方法。响应格式统一为 `{"success": true, "data": {...}}`。

| 方法 | 路径                     | 说明                           |
| ---- | ------------------------ | ------------------------------ |
| GET  | `/healthz`               | 健康检查（含 DB 连通性）       |
| POST | `/api/health`            | 服务状态 + 版本                |
| POST | `/api/v1/system/summary` | 应用信息 + 新闻统计            |
| POST | `/api/v1/news`           | 已发布新闻列表（发布时间倒序） |
| POST | `/api/v1/meta`           | 端口元数据                     |

---

## 命令速查

### 开发

| 命令           | 说明                                         |
| -------------- | -------------------------------------------- |
| `make start`   | 安装依赖 + 构建 + 迁移 + 启动全部服务        |
| `make down`    | 停止 watcher 和 Docker 栈                    |
| `make restart` | 执行迁移 + 重建 backend/nginx + 确保 watcher |
| `make logs`    | 查看所有服务日志                             |
| `make ps`      | 查看容器状态                                 |

### 代码质量

| 命令                  | 说明                |
| --------------------- | ------------------- |
| `make install`        | 安装依赖            |
| `make frontend-build` | 构建前端            |
| `make lint`           | oxlint 检查         |
| `make format`         | oxfmt 格式化        |
| `make format-check`   | oxfmt 格式校验      |
| `make type-check`     | TypeScript 类型检查 |

### 数据库

| 命令                              | 说明                  |
| --------------------------------- | --------------------- |
| `make create-migration NAME=...`  | 创建 up/down 迁移文件 |
| `make compose-migrate`            | 执行迁移              |
| `make db-backup`                  | 本地备份              |
| `make db-restore BACKUP_FILE=...` | 从备份恢复            |
| `make setup-backup-cron`          | 安装定时备份          |

### 部署

| 命令                    | 说明               |
| ----------------------- | ------------------ |
| `make sync-base-images` | 同步基础镜像到 ACR |
| `make push`             | 构建并推送镜像     |
| `make remote-deploy`    | 一键部署到生产     |
| `make remote-rollback`  | 回滚到上一版本     |
| `make remote-verify`    | 验证远端健康状态   |

---

## 详细文档

- [数据库指南](docs/DATABASE.md) — 迁移机制、操作流程、日常维护、备份恢复
- [部署指南](docs/DEPLOY.md) — 镜像管理、发布流程、回滚、服务器迁移、环境变量参考
