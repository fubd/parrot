SHELL := /bin/bash
.DEFAULT_GOAL := help

STACK_ENV_FILE ?= .env
COMPOSE ?= docker compose
DEPLOY_COMPOSE_FILE ?= docker-compose.deploy.yml
BUILD_PLATFORMS ?= linux/amd64
LOCAL_COMPOSE_FILE ?= docker-compose.yml
BACKUP_DIR ?= backups/mysql
BACKUP_RETENTION_DAYS ?= 7
BACKUP_SCHEDULE ?= 0 3 * * *
REMOTE_RELEASE_ENV_FILE ?= .release.env
REMOTE_PREVIOUS_RELEASE_ENV_FILE ?= .release.previous.env
PKG_REGISTRY ?= https://registry.npmmirror.com
BUILD_RETRY_COUNT ?= 3
BUILD_RETRY_DELAY ?= 5
PUSH_BUILD_CACHE ?= 0
MIGRATE_VERSION ?= v4.19.1

LOCAL_COMPOSE := $(COMPOSE) --env-file $(STACK_ENV_FILE) -f $(LOCAL_COMPOSE_FILE)
WATCH_CONTAINER := parrot-watch
WATCH_PID_FILE ?= .watch.pid
WATCH_LOG_FILE ?= .watch.log
REMOTE_COMPOSE := docker compose --env-file .env --env-file $(REMOTE_RELEASE_ENV_FILE) -f $(DEPLOY_COMPOSE_FILE)

ifneq (,$(wildcard $(STACK_ENV_FILE)))
include $(STACK_ENV_FILE)
export
endif

IMAGE_NAMESPACE ?= $(ALIYUN_USERNAME)
BASE_BUN_IMAGE ?= $(ALIYUN_REGISTRY)/$(IMAGE_NAMESPACE)/base-bun:1-alpine
BASE_MIGRATE_IMAGE ?= $(ALIYUN_REGISTRY)/$(IMAGE_NAMESPACE)/base-migrate:$(MIGRATE_VERSION)
BASE_NGINX_IMAGE ?= $(ALIYUN_REGISTRY)/$(IMAGE_NAMESPACE)/base-nginx:1.27-alpine
BASE_MYSQL_IMAGE ?= $(ALIYUN_REGISTRY)/$(IMAGE_NAMESPACE)/base-mysql:8.4.4
BACKEND_IMAGE ?= $(ALIYUN_REGISTRY)/$(IMAGE_NAMESPACE)/parrot-backend:$(VERSION)
NGINX_IMAGE ?= $(ALIYUN_REGISTRY)/$(IMAGE_NAMESPACE)/parrot-nginx:$(VERSION)
BACKEND_BUILD_CACHE ?= $(ALIYUN_REGISTRY)/$(IMAGE_NAMESPACE)/parrot-backend:buildcache
NGINX_BUILD_CACHE ?= $(ALIYUN_REGISTRY)/$(IMAGE_NAMESPACE)/parrot-nginx:buildcache

ifeq ($(PUSH_BUILD_CACHE),1)
BACKEND_CACHE_ARGS := --cache-from type=registry,ref=$(BACKEND_BUILD_CACHE) --cache-to type=registry,ref=$(BACKEND_BUILD_CACHE),mode=max
NGINX_CACHE_ARGS := --cache-from type=registry,ref=$(NGINX_BUILD_CACHE) --cache-to type=registry,ref=$(NGINX_BUILD_CACHE),mode=max
else
BACKEND_CACHE_ARGS :=
NGINX_CACHE_ARGS :=
endif

.PHONY: help guard-stack-env guard-bun install build frontend-build type-check lint format format-check dev-backend create-migration compose-migrate migrate db-status start down restart logs ps watch _ensure-watch _stop-watch acr-login sync-base-images compose-build push remote-sync \
	remote-deploy remote-verify remote-rollback remote-logs db-backup db-restore remote-db-backup remote-db-restore \
	setup-backup-cron remote-setup-backup-cron

help:
	@printf "\nAvailable targets:\n"
	@printf "  %-26s %s\n" "start" "Install deps, build frontend, build images, migrate DB, start stack + watcher"
	@printf "  %-26s %s\n" "down" "Stop watcher and docker compose stack"
	@printf "  %-26s %s\n" "restart" "Restart backend + nginx, re-run migrations, ensure watcher"
	@printf "  %-26s %s\n" "watch" "Run the frontend watcher in foreground"
	@printf "  %-26s %s\n" "logs" "Tail compose logs"
	@printf "  %-26s %s\n" "ps" "Show compose service status"
	@printf "  %-26s %s\n" "install" "Install all workspace dependencies on the host"
	@printf "  %-26s %s\n" "build" "Run the workspace build script on the host"
	@printf "  %-26s %s\n" "frontend-build" "Build frontend assets for nginx to serve"
	@printf "  %-26s %s\n" "type-check" "Run TypeScript checks for both apps"
	@printf "  %-26s %s\n" "lint" "Run oxlint for both apps"
	@printf "  %-26s %s\n" "format" "Run oxfmt across the repository"
	@printf "  %-26s %s\n" "format-check" "Check formatting with oxfmt"
	@printf "  %-26s %s\n" "dev-backend" "Start the backend in Docker (recreates container)"
	@printf "  %-26s %s\n" "create-migration" "Create a numbered migration (NAME=optional, auto-generates)"
	@printf "  %-26s %s\n" "compose-migrate" "Run migrations in backend container"
	@printf "  %-26s %s\n" "migrate" "Run migrate command (ARGS=\"down 1\" / \"force 3\")"
	@printf "  %-26s %s\n" "db-status" "Show migration version and dirty status"
	@printf "  %-26s %s\n" "db-backup" "Create a compressed MySQL backup under $(BACKUP_DIR)"
	@printf "  %-26s %s\n" "db-restore" "Restore MySQL from BACKUP_FILE=/path/to/dump.sql.gz"
	@printf "  %-26s %s\n" "setup-backup-cron" "Install a daily backup cron job on this machine"
	@printf "  %-26s %s\n" "remote-setup-backup-cron" "Install a daily backup cron job on the remote host"
	@printf "  %-26s %s\n" "acr-login" "Login to Aliyun ACR"
	@printf "  %-26s %s\n" "sync-base-images" "Force sync shared base images to ACR"
	
	@printf "  %-26s %s\n" "push" "Build and push deploy images for $(BUILD_PLATFORMS)"
	@printf "  %-26s %s\n" "remote-deploy" "Push images, migrate remotely, deploy, and verify"
	@printf "  %-26s %s\n" "remote-verify" "Check remote compose status and health endpoints"
	@printf "  %-26s %s\n" "remote-rollback" "Rollback to the previous remote VERSION metadata"
	@printf "  %-26s %s\n" "remote-db-backup" "Create a compressed MySQL backup on the remote host"
	@printf "  %-26s %s\n" "remote-db-restore" "Restore remote MySQL from BACKUP_FILE=backups/mysql/file.sql.gz"
	@printf "\n"

guard-stack-env:
	@test -f $(STACK_ENV_FILE) || (echo "Missing $(STACK_ENV_FILE). Copy .env.example to $(STACK_ENV_FILE) and fill it first." && exit 1)

guard-bun:
	@command -v bun >/dev/null || (echo "Bun is not installed on this host. Install it: https://bun.sh" && exit 1)

install: guard-bun
	bun install

build: guard-bun
	bun run build

frontend-build: guard-bun
	bun run build:frontend

type-check: guard-bun
	bun run type-check

lint: guard-bun
	bun run lint

format: guard-bun
	bun run format

format-check: guard-bun
	bun run format:check

dev-backend:
	@$(LOCAL_COMPOSE) up -d --force-recreate backend

create-migration:
	@last=$$(ls apps/backend/migrations/*.up.sql 2>/dev/null | sed 's|.*/||;s/_.*//' | sort -n | tail -1); \
	next=$$((10#$${last:-0} + 1)); \
	name="$(NAME)"; \
	if [ -z "$$name" ]; then name="migration_$$(date +%Y%m%d%H%M%S)"; fi; \
	versioned_name="$$(printf '%04d' $$next)_$${name}"; \
	up_file="apps/backend/migrations/$${versioned_name}.up.sql"; \
	down_file="apps/backend/migrations/$${versioned_name}.down.sql"; \
	printf '%s\n%s\n' "-- $${versioned_name} up" "" > "$$up_file"; \
	printf '%s\n%s\n' "-- $${versioned_name} down" "" > "$$down_file"; \
	echo "Created: $$up_file"; \
	echo "Created: $$down_file"

# ── frontend watcher ────────────────────────────────────────────
# Runs on the host with Bun so file changes are visible immediately
# to nginx, which mounts apps/frontend/dist from the host.

watch: guard-bun _stop-watch
	bun run --filter @parrot/frontend watch

_ensure-watch: guard-bun
	@if docker ps -aq --filter "name=$(WATCH_CONTAINER)" | grep -q .; then \
		docker stop $(WATCH_CONTAINER) >/dev/null 2>&1 || true; \
		docker rm $(WATCH_CONTAINER) >/dev/null 2>&1 || true; \
	fi
	@if [ -f "$(WATCH_PID_FILE)" ] && kill -0 "$$(cat "$(WATCH_PID_FILE)")" 2>/dev/null; then \
		echo "Watcher already running (pid $$(cat "$(WATCH_PID_FILE)"))"; \
	else \
		rm -f "$(WATCH_PID_FILE)"; \
		nohup bun run --filter @parrot/frontend watch >>"$(WATCH_LOG_FILE)" 2>&1 & echo $$! >"$(WATCH_PID_FILE)"; \
		sleep 1; \
		if [ -f "$(WATCH_PID_FILE)" ] && kill -0 "$$(cat "$(WATCH_PID_FILE)")" 2>/dev/null; then \
			echo "Watcher started (pid $$(cat "$(WATCH_PID_FILE)")). Logs: $(WATCH_LOG_FILE)"; \
		else \
			echo "Watcher failed to start. Check $(WATCH_LOG_FILE)" >&2; \
			rm -f "$(WATCH_PID_FILE)"; \
			exit 1; \
		fi; \
	fi

_stop-watch:
	@stopped=0; \
	if [ -f "$(WATCH_PID_FILE)" ]; then \
		pid="$$(cat "$(WATCH_PID_FILE)")"; \
		if kill -0 "$$pid" 2>/dev/null; then \
			kill "$$pid" >/dev/null 2>&1 || true; \
			wait "$$pid" 2>/dev/null || true; \
			stopped=1; \
		fi; \
		rm -f "$(WATCH_PID_FILE)"; \
	fi; \
	if docker ps -aq --filter "name=$(WATCH_CONTAINER)" | grep -q .; then \
		docker stop $(WATCH_CONTAINER) >/dev/null 2>&1 || true; \
		docker rm $(WATCH_CONTAINER) >/dev/null 2>&1 || true; \
		stopped=1; \
	fi; \
	if [ "$$stopped" -eq 1 ]; then \
		echo "Watcher stopped"; \
	else \
		echo "Watcher not running"; \
	fi

# ── compose lifecycle ───────────────────────────────────────────

down: guard-stack-env _stop-watch
	$(LOCAL_COMPOSE) down

restart: guard-stack-env _stop-watch compose-migrate
	$(LOCAL_COMPOSE) up -d --force-recreate backend nginx
	@$(MAKE) _ensure-watch

logs: guard-stack-env
	$(LOCAL_COMPOSE) logs -f --tail=200

ps: guard-stack-env
	$(LOCAL_COMPOSE) ps

# ── database ────────────────────────────────────────────────────

db-backup: guard-stack-env
	@mkdir -p $(BACKUP_DIR)
	@ENV_FILE=$(STACK_ENV_FILE) \
	COMPOSE_FILE=$(LOCAL_COMPOSE_FILE) \
	BACKUP_DIR=$(BACKUP_DIR) \
	DATABASE_NAME=$(MYSQL_DATABASE) \
	BACKUP_RETENTION_DAYS=$(BACKUP_RETENTION_DAYS) \
	bash scripts/mysql-backup.sh

db-restore: guard-stack-env
	@test -n "$(BACKUP_FILE)" || (echo "Missing BACKUP_FILE=/path/to/backup.sql[.gz]" && exit 1)
	@ENV_FILE=$(STACK_ENV_FILE) \
	COMPOSE_FILE=$(LOCAL_COMPOSE_FILE) \
	bash scripts/mysql-restore.sh "$(BACKUP_FILE)"

setup-backup-cron: guard-stack-env
	@PROJECT_DIR=$(CURDIR) \
	BACKUP_SCHEDULE="$(BACKUP_SCHEDULE)" \
	BACKUP_RETENTION_DAYS=$(BACKUP_RETENTION_DAYS) \
	COMPOSE_FILE=$(LOCAL_COMPOSE_FILE) \
	ENV_FILE=$(STACK_ENV_FILE) \
	bash scripts/setup-backup-cron.sh

remote-setup-backup-cron: remote-sync
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH) \
		&& PROJECT_DIR=$(REMOTE_PATH) \
		BACKUP_SCHEDULE='$(BACKUP_SCHEDULE)' \
		BACKUP_RETENTION_DAYS=$(BACKUP_RETENTION_DAYS) \
		COMPOSE_FILE=$(DEPLOY_COMPOSE_FILE) \
		ENV_FILE=.env \
		EXTRA_ENV_FILE=$(REMOTE_RELEASE_ENV_FILE) \
		bash scripts/setup-backup-cron.sh"

# ── images ──────────────────────────────────────────────────────

acr-login:
	@echo "$(ALIYUN_PASSWORD)" | docker login $(ALIYUN_REGISTRY) -u "$(ALIYUN_USERNAME)" --password-stdin

sync-base-images: guard-stack-env acr-login
	docker buildx imagetools create --platform linux/amd64,linux/arm64 --tag $(BASE_BUN_IMAGE) docker.io/oven/bun:1-alpine
	docker buildx imagetools create --platform linux/amd64,linux/arm64 --tag $(BASE_MIGRATE_IMAGE) docker.io/migrate/migrate:$(MIGRATE_VERSION)
	docker buildx imagetools create --platform linux/amd64,linux/arm64 --tag $(BASE_NGINX_IMAGE) docker.io/library/nginx:1.27-alpine
	docker buildx imagetools create --platform linux/amd64,linux/arm64 --tag $(BASE_MYSQL_IMAGE) docker.io/library/mysql:8.4.4

compose-build: guard-stack-env
	$(LOCAL_COMPOSE) build --build-arg BUN_CONFIG_REGISTRY=$(PKG_REGISTRY)

compose-migrate: guard-stack-env
	@$(LOCAL_COMPOSE) stop backend 2>/dev/null || true
	$(LOCAL_COMPOSE) up -d --wait mysql
	$(LOCAL_COMPOSE) run --rm --no-deps backend bun run migrate

# Lightweight migrate subcommand runner — no service stops.
# Defaults to 'up' when ARGS is not set. Examples:
#   make migrate ARGS="down 1"
#   make migrate ARGS="force 3"
#   make migrate ARGS="version"
migrate: guard-stack-env
	@$(LOCAL_COMPOSE) up -d --wait mysql
	$(LOCAL_COMPOSE) run --rm --no-deps backend bun run migrate $(ARGS)

db-status: guard-stack-env
	@$(LOCAL_COMPOSE) exec mysql mysql -uroot -p"$(MYSQL_ROOT_PASSWORD)" $(MYSQL_DATABASE) \
	 -e "SELECT version, dirty FROM parrot_schema_migrations;"

start: guard-stack-env install frontend-build compose-build compose-migrate
	$(LOCAL_COMPOSE) up -d --remove-orphans backend nginx
	@$(MAKE) _ensure-watch

push: guard-stack-env acr-login install frontend-build
	@echo "Building backend and nginx in parallel..."; \
	(attempt=1; \
	while true; do \
		docker buildx build --platform $(BUILD_PLATFORMS) --push \
			$(BACKEND_CACHE_ARGS) \
			--build-arg BASE_BUN_IMAGE=$(BASE_BUN_IMAGE) \
			--build-arg MIGRATE_IMAGE=$(BASE_MIGRATE_IMAGE) \
			--build-arg BUN_CONFIG_REGISTRY=$(PKG_REGISTRY) \
			-t $(BACKEND_IMAGE) \
			-f apps/backend/Dockerfile . && break; \
		status=$$?; \
		if [ $$attempt -ge $(BUILD_RETRY_COUNT) ]; then echo "Backend build failed"; exit 1; fi; \
		echo "Backend build failed (attempt $$attempt/$(BUILD_RETRY_COUNT)); retrying in $(BUILD_RETRY_DELAY)s"; \
		attempt=$$((attempt + 1)); \
		sleep $(BUILD_RETRY_DELAY); \
	done) & \
	backend_pid=$$!; \
	(attempt=1; \
	while true; do \
		docker buildx build --platform $(BUILD_PLATFORMS) --push \
			$(NGINX_CACHE_ARGS) \
			--build-arg BASE_NGINX_IMAGE=$(BASE_NGINX_IMAGE) \
			-t $(NGINX_IMAGE) \
			-f infra/nginx/Dockerfile . && break; \
		status=$$?; \
		if [ $$attempt -ge $(BUILD_RETRY_COUNT) ]; then echo "Nginx build failed"; kill $$backend_pid 2>/dev/null; exit 1; fi; \
		echo "Nginx build failed (attempt $$attempt/$(BUILD_RETRY_COUNT)); retrying in $(BUILD_RETRY_DELAY)s"; \
		attempt=$$((attempt + 1)); \
		sleep $(BUILD_RETRY_DELAY); \
	done) & \
	nginx_pid=$$!; \
	wait $$backend_pid || exit 1; \
	wait $$nginx_pid || exit 1; \
	echo "All images built successfully"

# ── remote ──────────────────────────────────────────────────────

remote-sync: guard-stack-env
	ssh $(REMOTE_HOST) "mkdir -p $(REMOTE_PATH) $(REMOTE_PATH)/scripts $(REMOTE_PATH)/apps/backend/migrations"
	scp $(DEPLOY_COMPOSE_FILE) $(REMOTE_HOST):$(REMOTE_PATH)/$(DEPLOY_COMPOSE_FILE)
	scp $(STACK_ENV_FILE) $(REMOTE_HOST):$(REMOTE_PATH)/.env
	scp apps/backend/migrations/*.sql $(REMOTE_HOST):$(REMOTE_PATH)/apps/backend/migrations/
	scp scripts/mysql-backup.sh scripts/mysql-restore.sh scripts/setup-backup-cron.sh $(REMOTE_HOST):$(REMOTE_PATH)/scripts/
	ssh $(REMOTE_HOST) "chmod +x $(REMOTE_PATH)/scripts/mysql-backup.sh $(REMOTE_PATH)/scripts/mysql-restore.sh $(REMOTE_PATH)/scripts/setup-backup-cron.sh"

remote-deploy: push remote-sync
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH) \
		&& if [ -f $(REMOTE_RELEASE_ENV_FILE) ]; then cp $(REMOTE_RELEASE_ENV_FILE) $(REMOTE_PREVIOUS_RELEASE_ENV_FILE); fi \
		&& printf 'VERSION=%s\n' '$(VERSION)' > $(REMOTE_RELEASE_ENV_FILE) \
		&& echo '$(ALIYUN_PASSWORD)' | docker login $(ALIYUN_REGISTRY) -u '$(ALIYUN_USERNAME)' --password-stdin \
		&& $(REMOTE_COMPOSE) pull \
		&& $(REMOTE_COMPOSE) stop backend 2>/dev/null || true \
		&& $(REMOTE_COMPOSE) up -d --wait mysql \
		&& $(REMOTE_COMPOSE) run --rm --no-deps backend bun run migrate \
		&& $(REMOTE_COMPOSE) up -d --remove-orphans --no-build \
		&& docker image prune -f"
	@$(MAKE) remote-verify || { echo "Remote verification failed; attempting rollback."; $(MAKE) remote-rollback; exit 1; }

remote-verify: guard-stack-env
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH) \
		&& if [ ! -f $(REMOTE_RELEASE_ENV_FILE) ]; then \
			echo 'No .release.env found. Run remote-deploy first.' >&2; \
			exit 1; \
		fi \
		&& $(REMOTE_COMPOSE) ps \
		&& curl -fsS http://127.0.0.1:$(BACKEND_PORT)/healthz >/dev/null \
		&& curl -fsS http://127.0.0.1:$(NGINX_PORT)/healthz >/dev/null \
		&& curl -fsS http://127.0.0.1:$(NGINX_PORT)/ >/dev/null \
		&& curl -fsS -X POST http://127.0.0.1:$(NGINX_PORT)/api/v1/system/summary >/dev/null"

remote-rollback: guard-stack-env
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH) \
		&& if [ ! -f $(REMOTE_PREVIOUS_RELEASE_ENV_FILE) ]; then \
			echo 'No previous version to rollback to. Run remote-deploy first.' >&2; \
			exit 1; \
		fi \
		&& cp $(REMOTE_PREVIOUS_RELEASE_ENV_FILE) $(REMOTE_RELEASE_ENV_FILE) \
		&& echo '$(ALIYUN_PASSWORD)' | docker login $(ALIYUN_REGISTRY) -u '$(ALIYUN_USERNAME)' --password-stdin \
		&& $(REMOTE_COMPOSE) pull backend nginx \
		&& $(REMOTE_COMPOSE) up -d --remove-orphans --no-build \
		&& docker image prune -f"
	@$(MAKE) remote-verify

remote-db-backup: remote-sync
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH) \
		&& if [ ! -f $(REMOTE_RELEASE_ENV_FILE) ]; then printf 'VERSION=%s\n' '$(VERSION)' > $(REMOTE_RELEASE_ENV_FILE); fi \
		&& mkdir -p backups/mysql \
		&& ENV_FILE=.env EXTRA_ENV_FILE=$(REMOTE_RELEASE_ENV_FILE) COMPOSE_FILE=$(DEPLOY_COMPOSE_FILE) BACKUP_DIR=backups/mysql DATABASE_NAME=$(MYSQL_DATABASE) bash scripts/mysql-backup.sh"

remote-db-restore: remote-sync
	@test -n "$(BACKUP_FILE)" || (echo "Missing BACKUP_FILE=backups/mysql/file.sql[.gz]" && exit 1)
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH) \
		&& if [ ! -f $(REMOTE_RELEASE_ENV_FILE) ]; then printf 'VERSION=%s\n' '$(VERSION)' > $(REMOTE_RELEASE_ENV_FILE); fi \
		&& ENV_FILE=.env EXTRA_ENV_FILE=$(REMOTE_RELEASE_ENV_FILE) COMPOSE_FILE=$(DEPLOY_COMPOSE_FILE) bash scripts/mysql-restore.sh '$(BACKUP_FILE)'"

remote-logs: guard-stack-env
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH) \
		&& if [ ! -f $(REMOTE_RELEASE_ENV_FILE) ]; then printf 'VERSION=%s\n' '$(VERSION)' > $(REMOTE_RELEASE_ENV_FILE); fi \
		&& $(REMOTE_COMPOSE) logs -f --tail=200"
