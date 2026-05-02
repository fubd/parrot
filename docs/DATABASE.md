# 数据库指南

数据库迁移、维护、备份与恢复的完整参考。

---

## 核心原则

**所有结构变更必须走迁移文件，不要用 DataGrip 等工具直接改表结构。**

- 迁移系统通过 `parrot_schema_migrations` 表记录已执行的变更，GUI 工具绕过了这个机制
- 直接改库后，其他开发者 `make start` 不会拿到你的变更，生产部署也不会执行
- 迁移文件是唯一的数据库结构变更来源，它就是"数据库的 Git"

**DataGrip 可以做的事**：查看/查询数据、测试 SQL 语句、查看表结构和索引。
**不能做的事**：CREATE TABLE / ALTER TABLE / DROP TABLE、加减字段、改索引、改字段类型。

---

## 相关命令

| 命令                                     | 说明                   |
| ---------------------------------------- | ---------------------- |
| `make create-migration NAME=...`         | 创建 up/down 迁移文件  |
| `make compose-migrate`                   | 在容器内执行迁移       |
| `make db-backup`                         | 手动本地备份           |
| `make db-restore BACKUP_FILE=...`        | 从本地快照恢复         |
| `make setup-backup-cron`                 | 安装本地定时备份       |
| `make remote-db-backup`                  | 在服务器创建快照       |
| `make remote-db-restore BACKUP_FILE=...` | 从快照恢复服务器数据库 |
| `make remote-setup-backup-cron`          | 在服务器安装定时备份   |

## 迁移机制

迁移文件位于 `apps/backend/migrations/`，以 `NNNN_description.up.sql` / `NNNN_description.down.sql` 成对命名，由 golang-migrate CLI 按版本号顺序执行。

当前迁移：

- `0001_init.up.sql` — 创建 `news_posts` 表并插入初始种子数据
- `0002_add_indexes.up.sql` — 添加复合索引 `(is_published, published_at DESC)`
- `0003_drop_redundant_index.up.sql` — 移除被复合索引覆盖的单列索引

运行时特性：

- **幂等**：已执行版本记录在 `parrot_schema_migrations` 表，不会重复执行
- **原子性**：每个迁移版本在一个事务中执行
- **并发安全**：golang-migrate 获取 MySQL 迁移锁，防止多实例同时执行
- **旧库兼容**：若旧 `schema_migrations` 表存在且新表不存在，`run-migrations.ts` 会自动读取旧版本号并 force 到 `parrot_schema_migrations`，再继续执行后续新迁移

---

## 操作流程

任何结构变更都遵循同一套流程：

```
make create-migration NAME=描述 → 编辑 up/down SQL → make compose-migrate → 验证 → 提交代码
```

### 创建迁移文件

```bash
make create-migration NAME=add_users_table
# → Created: apps/backend/migrations/0004_add_users_table.up.sql
# → Created: apps/backend/migrations/0004_add_users_table.down.sql
```

自动检测现有最大序号并递增，无需手动查编号。

### 执行迁移

```bash
make compose-migrate
```

等价于 `docker compose --env-file .env run --rm --no-deps backend bun run migrate`（默认执行 `up`，应用所有未执行的迁移）。

### 查看版本状态

```bash
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" parrot \
  -e "SELECT version, dirty FROM parrot_schema_migrations;"
```

`dirty=0` 正常；`dirty=1` 表示上一次迁移执行失败，需立即修复。

### 回滚

```bash
# 回滚 1 个版本
docker compose --env-file .env run --rm --no-deps backend bun run migrate down 1

# 回滚所有迁移
docker compose --env-file .env run --rm --no-deps backend bun run migrate down -1
```

> 回滚会执行 `.down.sql`，请确认 down 文件内容正确。不可安全回滚的迁移应在 down 文件中写 no-op 注释。

### 跳转到指定版本

```bash
docker compose --env-file .env run --rm --no-deps backend bun run migrate goto 2
```

### 强制标记版本（修复 dirty 状态）

```bash
# 1. 确认数据库结构当前与哪个版本一致
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" parrot -e "SHOW TABLES;"

# 2. 强制标记（仅改版本号，不执行 SQL）
docker compose --env-file .env run --rm --no-deps backend bun run migrate force 3

# 3. 重新执行迁移
make compose-migrate
```

## 迁移规则

- **永远不要修改已有的迁移文件**，只新增。已执行的迁移被其他环境依赖，修改会导致不一致
- 序号必须递增且不重复
- 一个迁移版本只做一件事，方便定位和回滚
- 每个版本都要保留 `.up.sql` 和 `.down.sql`；不可安全回滚时，在 down 文件中写明 no-op 注释

---

## 日常维护

### 查看连接数

```bash
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW PROCESSLIST;"
```

### 查看数据库大小

```bash
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
    SELECT table_schema AS 'Database',
           ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
    FROM information_schema.tables
    WHERE table_schema = 'parrot'
    GROUP BY table_schema;"
```

### 慢查询排查

```bash
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
    SET GLOBAL slow_query_log = 'ON';
    SET GLOBAL long_query_time = 2;
    SET GLOBAL log_queries_not_using_indexes = 'ON';"
```

### 清理 binlog

```bash
# 查看 binlog 占用
docker compose --env-file .env exec mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW BINARY LOGS;"

# 清理 3 天前的 binlog
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

备份文件命名格式：`parrot_20260502_030000.sql.gz`，保存在 `backups/mysql/`。

备份方式：`mysqldump --single-transaction --skip-lock-tables`（InnoDB MVCC 一致性快照，不锁表）+ gzip 压缩。

安全措施：

- **磁盘空间检查**：备份前检测可用空间 ≥ 10 MB，不足则中止
- **gzip 完整性校验**：备份完成后 `gzip -t` 验证，损坏则自动删除并报错
- **保留策略**：默认保留 7 天（`BACKUP_RETENTION_DAYS` 可调），超期自动清理

### 自动定时备份

通过宿主机 `crontab` 调用项目脚本，不依赖 Bun：

```bash
# 安装（默认每天凌晨 3 点）
make setup-backup-cron

# 自定义时间
BACKUP_SCHEDULE="30 2 * * *" make setup-backup-cron

# 生产服务器
make remote-setup-backup-cron

# 查看
crontab -l

# 卸载
bash scripts/setup-backup-cron.sh --remove
```

### 从备份恢复

恢复前会**自动创建一份安全备份**（`pre_restore_*.sql.gz`），以防误操作后可追溯。交互终端会要求输入 `yes` 确认。

```bash
# 本地恢复
make db-restore BACKUP_FILE=backups/mysql/parrot_20260501_030000.sql.gz

# 远端恢复
make remote-db-restore BACKUP_FILE=backups/mysql/parrot_20260501_030000.sql.gz
```

> **恢复会用备份内容完全覆盖当前数据库**，操作前务必确认。

### 数据卷说明

MySQL 数据存储在 Docker 命名卷 `parrot_mysql-data` 中。

| 操作                     | 安全性   | 说明                                         |
| ------------------------ | -------- | -------------------------------------------- |
| `docker compose down`    | 安全     | 仅停止容器，数据卷保留                       |
| `docker compose down -v` | **危险** | 删除数据卷，数据永久丢失                     |
| 换服务器迁移             | 需导出   | 需先 `make remote-db-backup`，在新服务器恢复 |

---
