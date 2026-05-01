# 数据库与运维指南

本项目的数据库管理和运维操作的完整参考。快速操作见 [README 命令速查](../README.md#make-命令速查)。

---

## 命令速查

| 命令                                     | 说明                                 |
| ---------------------------------------- | ------------------------------------ |
| `make create-migration NAME=xxx`         | 创建带自动编号的迁移文件             |
| `make compose-migrate`                   | 在容器内执行迁移                     |
| `make db-backup`                         | 手动本地备份                         |
| `make db-restore BACKUP_FILE=...`        | 从本地快照恢复                       |
| `make setup-backup-cron`                 | 安装本地定时备份任务                 |
| `make sync-base-images`                  | 强制同步共享基础镜像到 ACR           |
| `make push`                              | 构建并推送 Docker 镜像到 ACR         |
| `make remote-deploy`                     | 一键完整部署（推镜像 + 同步 + 迁移） |
| `make remote-rollback`                   | 回滚到上一次部署的版本               |
| `make remote-verify`                     | 验证远端服务健康状态                 |
| `make remote-logs`                       | 实时查看远端服务日志                 |
| `make remote-db-backup`                  | 在服务器创建数据库快照               |
| `make remote-db-restore BACKUP_FILE=...` | 从快照恢复服务器数据库               |
| `make remote-setup-backup-cron`          | 在服务器安装定时备份任务             |

---

## 常见场景

### 场景一：开发新功能，需要加数据库表

本地开发加表的完整流程：

```bash
# 1. 新建迁移文件（会生成 up/down 两个文件）
make create-migration NAME=add_users_table

# 2. 编辑 up 文件
cat > apps/backend/migrations/0004_add_users_table.up.sql << 'EOF'
CREATE TABLE users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL DEFAULT '',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
EOF

# 3. 编辑 down 文件
cat > apps/backend/migrations/0004_add_users_table.down.sql << 'EOF'
DROP TABLE IF EXISTS users;
EOF

# 4. 执行迁移
make compose-migrate

# 5. 验证表已创建
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" parrot \
  -e "SHOW TABLES; DESCRIBE users;"
```

**注意**：

- 永远不要修改已有的迁移文件，只新增
- `make start` / `make restart` 会先执行 `make compose-migrate`
- 迁移由 golang-migrate 执行，已执行版本不会重复跑

### 场景二：首次部署到生产服务器

假设服务器 IP 为 `1.2.3.4`，用户 `root`，项目部署到 `/opt/parrot`：

```bash
# 1. 确认本地 .env 已填写部署相关字段
#    ALIYUN_REGISTRY、IMAGE_NAMESPACE、ALIYUN_USERNAME、ALIYUN_PASSWORD
#    REMOTE_HOST=root@1.2.3.4、REMOTE_PATH=/opt/parrot
#    VERSION=1.0.0

# 2. 确认 SSH 免密登录已配置
ssh root@1.2.3.4 "echo ok"

# 3. 一键部署（构建镜像 → 同步文件 → 拉起服务 → 健康检查）
VERSION=1.0.0 make remote-deploy

# 4. 验证服务正常
make remote-verify

# 5. 安装定时备份（默认每天凌晨 3 点）
make remote-setup-backup-cron
```

`remote-deploy` 内部执行顺序：

1. `make push` — 构建 `linux/amd64` 镜像，推送到阿里云 ACR
2. `make remote-sync` — 通过 SSH 同步 `.env`、compose 文件、脚本到服务器
3. 服务器上拉取镜像 → 启动 MySQL → 执行迁移 → 重启 backend + nginx → 清理旧镜像
4. `make remote-verify` — 验证健康检查端点，失败则自动回滚

### 场景二点五：手动同步共享基础镜像到 ACR

基础镜像统一使用不带项目名前缀的共享仓库名，方便其他项目复用：

- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-bun:1-alpine`
- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-migrate:v4.19.1`
- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-nginx:1.27-alpine`
- `${ALIYUN_REGISTRY}/${IMAGE_NAMESPACE}/base-mysql:8.4.4`

首次初始化 ACR 或怀疑基础镜像缺失时，可手动执行：

```bash
make sync-base-images
```

本地开发的 `make start` 默认不会再检查 ACR 中的基础镜像是否存在；如果 ACR 尚未初始化，请先手动执行一次 `make sync-base-images`。

### 场景三：日常版本迭代发布

已部署过的项目，每次改完代码后：

```bash
# 1. 本地验证
make lint && make type-check && make frontend-build
# 如需统一格式，可额外执行
make format

# 2. 发布（指定新版本号）
VERSION=1.1.0 make remote-deploy

# 3. 观察日志确认无异常
make remote-logs

# 4. 如果没问题，推送代码
git push
```

### 场景四：部署后发现问题，需要回滚

```bash
# 1. 确认当前服务异常
make remote-verify
make remote-logs

# 2. 回滚到上一个版本（自动读取 .release.previous.env）
make remote-rollback

# 3. 确认回滚成功
make remote-verify
```

`remote-rollback` 会拉取上一次部署的镜像版本并重启，然后自动验证健康检查。

如果回滚也无法解决问题，说明可能是数据库迁移导致的问题：

```bash
# 先恢复数据库到部署前的备份
make remote-db-restore BACKUP_FILE=backups/mysql/parrot_20260412_030000.sql.gz

# 再执行代码回滚
make remote-rollback
```

> 回滚**不会**回滚数据库迁移。如需回滚数据库，必须先手动恢复备份，再执行代码回滚。

### 场景五：生产数据误操作，需要恢复

```bash
# 1. 先做一次当前状态的备份（保留现场）
make remote-db-backup

# 2. 找到要恢复的备份文件
#    定时备份保存在服务器的 backups/mysql/ 目录下
#    文件格式：parrot_20260412_030000.sql.gz

# 3. 恢复（会自动先创建一份 pre_restore_ 备份）
make remote-db-restore BACKUP_FILE=backups/mysql/parrot_20260412_030000.sql.gz

# 4. 验证数据
make remote-verify
```

恢复脚本的安全措施：

- 恢复前自动创建 `pre_restore_20260412_102030.sql.gz` 备份
- 恢复后验证 gzip 文件完整性
- 用备份内容**完全覆盖**当前数据库，操作前务必确认

### 场景六：迁移到新服务器

将项目从旧服务器迁移到新服务器 `5.6.7.8`：

```bash
# 1. 在旧服务器做一次完整备份
make remote-db-backup
# 备份文件在旧服务器的 backups/mysql/ 下

# 2. 从旧服务器把备份文件下载到本地
scp root@1.2.3.4:/opt/parrot/backups/mysql/parrot_20260412_103000.sql.gz ./backups/mysql/

# 3. 修改 .env 指向新服务器
#    REMOTE_HOST=root@5.6.7.8
#    REMOTE_PATH=/opt/parrot

# 4. 在新服务器首次部署
VERSION=1.1.0 make remote-deploy

# 5. 将备份文件上传到新服务器并恢复
scp ./backups/mysql/parrot_20260412_103000.sql.gz root@5.6.7.8:/opt/parrot/backups/mysql/
make remote-db-restore BACKUP_FILE=backups/mysql/parrot_20260412_103000.sql.gz

# 6. 安装定时备份
make remote-setup-backup-cron
```

---

## 数据库迁移

### 核心原则：所有结构变更必须走迁移文件

**不要用 DataGrip 等工具直接改表结构。** 原因：

- 迁移系统通过 `parrot_schema_migrations` 表记录已执行的变更，GUI 工具绕过了这个机制
- 直接改库后，其他开发者 `make start` 不会拿到你的变更，生产部署也不会执行
- 迁移文件是唯一的数据库结构变更来源，它就是"数据库的 Git"

**DataGrip 可以做的事**：

- 查看、查询数据（SELECT）
- 在写迁移文件前，先用 DataGrip 测试 SQL 语句是否正确
- 查看表结构、索引

**DataGrip 不能做的事**：

- CREATE TABLE / ALTER TABLE / DROP TABLE
- 加减字段、改索引、改字段类型

### 操作流程

任何结构变更都遵循同一套流程：

```
make create-migration NAME=描述  →  编辑 SQL  →  make compose-migrate  →  验证  →  提交代码
```

第一步会自动创建带正确序号的迁移文件，无需手动查编号：

```bash
make create-migration NAME=add_users_table
# → Created: apps/backend/migrations/0004_add_users_table.up.sql
# → Created: apps/backend/migrations/0004_add_users_table.down.sql

make create-migration NAME=add_users_status
# → Created: apps/backend/migrations/0005_add_users_status.up.sql
# → Created: apps/backend/migrations/0005_add_users_status.down.sql
```

### 添加表

```bash
make create-migration NAME=add_users_table
```

编辑生成的 `.up.sql` 文件：

```sql
-- 0004_add_users_table.up.sql

CREATE TABLE users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL DEFAULT '',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

编辑生成的 `.down.sql` 文件：

```sql
-- 0004_add_users_table.down.sql

DROP TABLE IF EXISTS users;
```

```bash
make compose-migrate   # 只执行迁移，不重启整个栈
# 在 DataGrip 中检查表结构是否正确
```

### 添加字段

```bash
make create-migration NAME=add_users_status
```

```sql
-- 0005_add_users_status.up.sql

ALTER TABLE users
  ADD COLUMN status ENUM('active', 'inactive') NOT NULL DEFAULT 'active' AFTER name,
  ADD COLUMN avatar_url VARCHAR(500) DEFAULT NULL;
```

### 修改字段

```bash
make create-migration NAME=widen_users_name
```

```sql
-- 0006_widen_users_name.up.sql

ALTER TABLE users
  MODIFY COLUMN name VARCHAR(200) NOT NULL DEFAULT '';
```

### 删除字段

```bash
make create-migration NAME=drop_users_avatar
```

```sql
-- 0007_drop_users_avatar.up.sql

ALTER TABLE users
  DROP COLUMN avatar_url;
```

### 删除表

```bash
make create-migration NAME=drop_legacy_logs
```

```sql
-- 0008_drop_legacy_logs.up.sql

DROP TABLE IF EXISTS legacy_logs;
```

### 添加索引

```bash
make create-migration NAME=add_users_status_idx
```

```sql
-- 0009_add_users_status_idx.up.sql

ALTER TABLE users
  ADD INDEX idx_users_status (status, created_at DESC);
```

### 每次操作后的验证

```bash
# 执行迁移
make compose-migrate

# 确认迁移已记录
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" parrot \
  -e "SELECT * FROM parrot_schema_migrations ORDER BY version;"

# 3. 在 DataGrip 中连接 localhost:26032，检查表结构是否符合预期
```

### 数据库初始化

**全新项目首次启动**时，数据库初始化完全自动化：

```bash
# 1. 确保 .env 已配置（复制 .env.example 并填写）
cp .env.example .env

# 2. 启动项目（自动完成：安装依赖 → 构建前端 → 构建镜像 → 初始化数据库 → 启动服务）
make start
```

`make start` 内部流程：

1. `install` — 安装依赖
2. `frontend-build` — 构建前端资源
3. `compose-build` — 构建 Docker 镜像
4. **`compose-migrate`** — 执行数据库迁移（关键步骤）
   - 启动 MySQL 容器并等待就绪
   - 运行 golang-migrate，按版本号顺序执行所有 `*.up.sql` 文件
   - 首次执行会创建 `parrot_schema_migrations` 版本跟踪表
   - 应用 `0001_init.up.sql`：创建 `news_posts` 表并插入种子数据
   - 应用后续迁移（索引、优化等）
5. 启动 backend + nginx 容器
6. 启动前端开发监听

**已参与过开发的项目**，只需：

```bash
make start     # 自动运行 compose-migrate，仅执行未应用的新版本
```

**生产服务器首次部署**：

```bash
# 构建镜像、同步文件、执行迁移、启动服务
VERSION=1.0.0 make remote-deploy
```

> `remote-deploy` 会在服务器上依次完成：拉取镜像 → 启动 MySQL → 运行迁移 → 启动 backend + nginx → 健康检查。

### 迁移机制

迁移文件位于 `apps/backend/migrations/`，以 `NNNN_description.up.sql` / `NNNN_description.down.sql` 成对命名，由 golang-migrate CLI 按版本号顺序执行。

当前迁移：

- `0001_init.up.sql` — 创建 `news_posts` 表并插入初始种子数据
- `0002_add_indexes.up.sql` — 添加复合索引 `(is_published, published_at DESC)`
- `0003_drop_redundant_index.up.sql` — 移除被复合索引覆盖的单列索引

迁移运行时特性：

- **幂等**：已执行版本记录在 `parrot_schema_migrations` 表，不会重复执行
- **原子性**：每个迁移版本在一个事务中执行（MySQL DDL 会隐式提交，golang-migrate 会拆分多语句文件为逐个事务）
- **并发安全**：golang-migrate 获取 MySQL 迁移锁，防止多实例同时执行
- **旧库兼容**：若旧 `schema_migrations` 表存在且新表不存在，`run-migrations.ts` 会自动读取旧版本号并 force 到 `parrot_schema_migrations`，再继续执行后续新迁移

### 迁移操作

#### 执行迁移（最常用）

```bash
make compose-migrate
```

等价于手动执行：

```bash
docker compose --env-file .env run --rm --no-deps backend bun run migrate
# 默认执行 'up'：应用所有未执行的 up 迁移
```

#### 查看当前版本与状态

```bash
# 查看已执行的迁移版本
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" parrot \
  -e "SELECT version, dirty FROM parrot_schema_migrations;"
```

`dirty` 字段含义：

- `0` — 正常状态，迁移执行成功
- `1` — **脏状态**：上一次迁移执行失败，数据库可能处于不一致状态，需立即修复

#### 回滚迁移

```bash
# 回滚 1 个版本
docker compose --env-file .env run --rm --no-deps backend bun run migrate down 1

# 回滚所有迁移（回到空库）
docker compose --env-file .env run --rm --no-deps backend bun run migrate down -1
```

> ⚠️ 回滚会执行对应版本的 `.down.sql`，请确认 down 文件内容正确。不可安全回滚的迁移应在 down 文件中写 no-op 注释。

#### 强制跳转到指定版本（修复脏状态）

当迁移执行失败导致 `dirty=1` 时，需手动修复：

```bash
# 1. 先确认当前数据库结构与哪个迁移版本一致
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" parrot \
  -e "SHOW TABLES; DESCRIBE news_posts;"

# 2. 强制标记为对应版本（无需执行 SQL，仅修改版本号）
docker compose --env-file .env run --rm --no-deps backend bun run migrate force 3

# 3. 清除 dirty 状态后，重新执行迁移
make compose-migrate
```

> 常见原因：手动改过表结构导致 up 文件中的 DDL 与实际结构冲突（如"Table already exists"）。修复实际结构后，用 force 校准版本号，再重新执行迁移。

#### 跳转到指定版本

```bash
# 向前或向后迁移到指定版本（自动选择合适的 up/down 方向）
docker compose --env-file .env run --rm --no-deps backend bun run migrate goto 2
```

### 迁移规则

- **永远不要修改已有的迁移文件**，只新增。已执行的迁移被其他环境依赖，修改会导致不一致
- 序号必须递增且不重复（查看现有文件确定下一个编号）
- 一个迁移版本只做一件事，方便定位和回滚
- 每个版本都要保留 `.up.sql` 和 `.down.sql`；不可安全回滚时，在 down 文件中写明 no-op 注释
- **迁移文件是唯一的数据库结构变更来源**，它就是"数据库的 Git"

### 日常维护

#### 查看连接数与运行状态

```bash
# 查看当前连接数
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW PROCESSLIST;"

# 查看数据库大小
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
    SELECT table_schema AS 'Database',
           ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
    FROM information_schema.tables
    WHERE table_schema = 'parrot'
    GROUP BY table_schema;"
```

#### 慢查询排查

```bash
# 临时开启慢查询日志（重启后失效）
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
    SET GLOBAL slow_query_log = 'ON';
    SET GLOBAL long_query_time = 2;
    SET GLOBAL log_queries_not_using_indexes = 'ON';"
```

#### 清理 binlog 释放磁盘空间

```bash
# 查看 binlog 占用
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW BINARY LOGS;"

# 清理 3 天前的 binlog（在 mysql 容器内执行）
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "PURGE BINARY LOGS BEFORE NOW() - INTERVAL 3 DAY;"
```

---

## 备份与恢复

### 手动备份

```bash
make db-backup              # 本地
make remote-db-backup       # 生产
```

备份文件命名格式：`parrot_20260101_030000.sql.gz`

备份脚本内置安全措施：

- **磁盘空间检查**：备份前检测可用空间（至少 10 MB），不足则中止
- **gzip 完整性校验**：备份完成后验证 `.gz` 文件完整性，损坏则自动删除并报错

默认保留最近 7 天的备份（可通过 `BACKUP_RETENTION_DAYS` 调整）。

### 自动定时备份

定时备份通过宿主机 `crontab` 调用项目自带 shell 脚本，不要求宿主机安装 `bun`。

```bash
# 安装（默认每天凌晨 3 点）
make setup-backup-cron

# 自定义时间（每天凌晨 2:30）
BACKUP_SCHEDULE="30 2 * * *" make setup-backup-cron

# 查看
crontab -l

# 卸载
bash scripts/setup-backup-cron.sh --remove
```

生产服务器同理：将上述命令中的 `setup-backup-cron` 替换为 `remote-setup-backup-cron`，`--remove` 改为在服务器上直接执行 `bash scripts/setup-backup-cron.sh --remove`。

### 数据卷说明

MySQL 数据存储在 Docker 命名卷 `parrot_mysql-data` 中。

| 操作                     | 安全性   | 说明                                         |
| ------------------------ | -------- | -------------------------------------------- |
| `docker compose down`    | 安全     | 仅停止容器，数据卷保留                       |
| `docker compose down -v` | **危险** | 同时删除数据卷，数据永久丢失                 |
| 换服务器迁移             | 需导出   | 需先 `make remote-db-backup`，在新服务器恢复 |

---

## 构建与部署

### 配置前置检查

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

### 发布命令

```bash
# 一键部署
make remote-deploy

# 指定版本
VERSION=1.2.0 make remote-deploy

# 仅推镜像（不部署）
make push

# 仅同步配置文件
make remote-sync
```

### 架构说明

| 场景                    | 架构   | 说明                                       |
| ----------------------- | ------ | ------------------------------------------ |
| 本地开发 (`make start`) | ARM64  | 使用本机架构直接构建运行                   |
| 生产构建 (`make push`)  | AMD64  | `BUILD_PLATFORMS ?= linux/amd64`，交叉编译 |
| 基础镜像 (ACR)          | 双架构 | `linux/amd64,linux/arm64` 都同步到 ACR     |

---

## 密钥管理

所有敏感配置（数据库密码、ACR 密钥、SSH 目标等）存放在 `.env` 文件中，该文件已被 `.gitignore` 屏蔽，**严禁提交到 Git**。

`.env` 的备份方案（按推荐程度排序）：

| 方案                               | 适用场景             |
| ---------------------------------- | -------------------- |
| 1Password / Bitwarden Secure Note  | 个人或小团队，最轻量 |
| 阿里云 KMS / AWS Secrets Manager   | 团队协作，合规要求   |
| GitHub Actions / GitLab CI Secrets | 全自动化流水线       |
