# 部署指南

构建、发布、回滚与服务器运维的完整参考。

---

## 前置检查

确认 `.env` 中以下字段已正确填写：

```
ALIYUN_REGISTRY=registry.cn-hangzhou.aliyuncs.com
IMAGE_NAMESPACE=my-namespace
ALIYUN_USERNAME=my@example.com
ALIYUN_PASSWORD=******

REMOTE_HOST=root@1.2.3.4
REMOTE_PATH=/opt/parrot
VERSION=1.0.0
```

---

## 基础镜像

项目使用共享基础镜像（不含 `parrot` 前缀，方便其他项目复用），统一托管在阿里云 ACR：

- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-bun:1-alpine`
- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-migrate:v4.19.1`
- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-nginx:1.27-alpine`
- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-mysql:8.4.4`

支持 `linux/amd64` 和 `linux/arm64` 双架构。

```bash
# 首次使用或怀疑镜像缺失时，手动同步一次
make sync-base-images
```

`make start` 默认不检查基础镜像是否存在——前提是你已同步过一次。

---

## 场景一：首次部署到生产

```bash
# 1. 确认 SSH 免密登录
ssh root@1.2.3.4 "echo ok"

# 2. 一键部署（构建镜像 → 同步文件 → 拉起服务 → 健康检查）
VERSION=1.0.0 make remote-deploy

# 3. 验证
make remote-verify

# 4. 安装定时备份
make remote-setup-backup-cron
```

`remote-deploy` 内部执行顺序：

1. `make push` — 构建 `linux/amd64` 镜像，推送到阿里云 ACR
2. `make remote-sync` — SSH 同步 `.env`、compose 文件、迁移文件、脚本到服务器
3. 服务器上：拉取镜像 → 启动 MySQL → 执行迁移 → 启动 backend + nginx → 清理旧镜像
4. `make remote-verify` — 验证健康检查端点，失败则自动回滚

---

## 场景二：日常版本迭代

```bash
# 1. 本地验证
make lint && make type-check && make frontend-build

# 2. 发布
VERSION=1.1.0 make remote-deploy

# 3. 观察日志
make remote-logs

# 4. 推送代码
git push
```

---

## 场景三：回滚

```bash
# 回滚到上一个版本（自动读取 .release.previous.env）
make remote-rollback
```

> 回滚**不会**回滚数据库迁移。如需同时回滚数据库，先恢复备份再回滚代码：
>
> ```bash
> make remote-db-restore BACKUP_FILE=backups/mysql/parrot_20260412_030000.sql.gz
> make remote-rollback
> ```

---

## 场景四：迁移到新服务器

```bash
# 1. 在旧服务器做一次完整备份
make remote-db-backup

# 2. 下载备份到本地
scp root@1.2.3.4:/opt/parrot/backups/mysql/parrot_20260502_103000.sql.gz ./backups/mysql/

# 3. 修改 .env 指向新服务器
#    REMOTE_HOST=root@5.6.7.8
#    REMOTE_PATH=/opt/parrot

# 4. 在新服务器首次部署
VERSION=1.1.0 make remote-deploy

# 5. 上传备份并恢复
scp ./backups/mysql/parrot_20260502_103000.sql.gz root@5.6.7.8:/opt/parrot/backups/mysql/
make remote-db-restore BACKUP_FILE=backups/mysql/parrot_20260502_103000.sql.gz

# 6. 安装定时备份
make remote-setup-backup-cron
```

---

## 仅推镜像（不部署）

```bash
make push
```

构建 `linux/amd64` 镜像并推送到 ACR，支持最多 3 次重试。

---

## 仅同步文件

```bash
make remote-sync
```

通过 SSH 同步 compose 文件、`.env`、迁移文件、备份脚本到服务器。

---

## 架构说明

| 场景                    | 架构   | 说明                             |
| ----------------------- | ------ | -------------------------------- |
| 本地开发 (`make start`) | ARM64  | 本机架构直接构建                 |
| 生产构建 (`make push`)  | AMD64  | `BUILD_PLATFORMS ?= linux/amd64` |
| 基础镜像 (ACR)          | 双架构 | `linux/amd64,linux/arm64`        |

---

## 环境变量参考

### 应用配置

| 变量       | 默认值        | 说明                    |
| ---------- | ------------- | ----------------------- |
| `APP_NAME` | `Parrot`      | 应用名称                |
| `NODE_ENV` | `development` | 生产时设为 `production` |
| `VERSION`  | `latest`      | 镜像版本 tag            |

### 端口

| 变量           | 默认值  | 说明                               |
| -------------- | ------- | ---------------------------------- |
| `BACKEND_PORT` | `26031` | Hono 后端宿主机映射端口            |
| `MYSQL_PORT`   | `26032` | MySQL 宿主机映射端口               |
| `NGINX_PORT`   | `26033` | Nginx 网关宿主机映射端口（主入口） |

### 数据库

| 变量                  | 默认值      | 说明                       |
| --------------------- | ----------- | -------------------------- |
| `DATABASE_HOST`       | `127.0.0.1` | 容器内自动覆盖为 `mysql`   |
| `DATABASE_PORT`       | `3306`      | 容器内使用 3306            |
| `MYSQL_DATABASE`      | `parrot`    | 数据库名                   |
| `MYSQL_USER`          | `parrot`    | 业务账号                   |
| `MYSQL_PASSWORD`      | —           | 业务账号密码               |
| `MYSQL_ROOT_PASSWORD` | —           | root 密码（备份/迁移使用） |

### 备份

| 变量                    | 默认值      | 说明                       |
| ----------------------- | ----------- | -------------------------- |
| `BACKUP_RETENTION_DAYS` | `7`         | 备份保留天数（0 = 不删除） |
| `BACKUP_SCHEDULE`       | `0 3 * * *` | cron 表达式                |

### 阿里云 ACR（部署必填）

| 变量              | 示例值                              | 说明                    |
| ----------------- | ----------------------------------- | ----------------------- |
| `ALIYUN_REGISTRY` | `registry.cn-hangzhou.aliyuncs.com` | ACR 域名                |
| `IMAGE_NAMESPACE` | `my-namespace`                      | 命名空间                |
| `ALIYUN_USERNAME` | `my@example.com`                    | 登录账号                |
| `ALIYUN_PASSWORD` | —                                   | 登录密码（勿提交 Git）  |
| `MIGRATE_VERSION` | `v4.19.1`                           | golang-migrate 镜像版本 |

### 远端部署

| 变量          | 示例值             | 说明                   |
| ------------- | ------------------ | ---------------------- |
| `REMOTE_HOST` | `root@1.2.3.4`     | SSH 目标（需免密登录） |
| `REMOTE_PATH` | `/root/app/parrot` | 服务器项目目录         |

---

## 密钥管理

所有敏感配置（数据库密码、ACR 密钥、SSH 目标等）存放在 `.env` 文件中，该文件已被 `.gitignore` 屏蔽，**严禁提交到 Git**。

`.env` 的备份方案（按推荐程度排序）：

| 方案                               | 适用场景             |
| ---------------------------------- | -------------------- |
| 1Password / Bitwarden Secure Note  | 个人或小团队，最轻量 |
| 阿里云 KMS / AWS Secrets Manager   | 团队协作，合规要求   |
| GitHub Actions / GitLab CI Secrets | 全自动化 CI/CD       |

---

## 相关命令

| 命令                                     | 说明                 |
| ---------------------------------------- | -------------------- |
| `make sync-base-images`                  | 同步基础镜像到 ACR   |
| `make push`                              | 构建并推送镜像       |
| `make remote-deploy`                     | 一键部署             |
| `make remote-rollback`                   | 回滚到上一版本       |
| `make remote-verify`                     | 验证远端健康状态     |
| `make remote-logs`                       | 查看远端日志         |
| `make remote-sync`                       | 同步配置文件到服务器 |
| `make remote-db-backup`                  | 服务器创建数据库快照 |
| `make remote-db-restore BACKUP_FILE=...` | 从快照恢复数据库     |
| `make remote-setup-backup-cron`          | 服务器安装定时备份   |
