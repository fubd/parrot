# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Parrot is a full-stack monorepo: Bun + Hono backend, React 19 + Ant Design 6 frontend, MySQL 8.4, Nginx gateway. All operations go through `make` targets. The host machine requires Docker, Bun, and make. Docker runs the services; Bun on the host handles installs, builds, checks, and the frontend watcher.

## Common Commands

```bash
make start               # Install deps, build frontend, build images, migrate DB, start stack + watcher
make down                # Stop watcher and Docker stack
make restart             # Recreate backend + nginx containers, rerun migrations, restart watcher
make install             # bun install on host machine
make lint                # oxlint (both apps) on host machine
make format              # oxfmt across the repo on host machine
make format-check        # oxfmt format check on host machine
make type-check          # tsc --noEmit (both apps) on host machine
make frontend-build      # Build frontend assets on host machine
make watch               # Foreground frontend watcher on host machine
make logs                # Tail all container logs
make ps                  # Show container status
```

Database:

```bash
make create-migration NAME=add_users_table   # Auto-numbered SQL migration file
make compose-migrate                          # Run migrations in backend container
make db-backup                                # Backup to backups/mysql/
make db-restore BACKUP_FILE=backups/mysql/parrot_20260101_030000.sql.gz
```

## Architecture

**Request flow:** Browser → Nginx (:26033) → `/api/*` proxied to Hono backend (:26031) → MySQL (:26032). All other routes serve the React SPA from `apps/frontend/dist/`.

**Monorepo structure:** Bun workspaces — root `package.json` defines `"workspaces": ["apps/*"]`. Scripts use `bun run --filter <workspace> <script>`. `apps/backend/` and `apps/frontend/` each have their own `package.json`, `tsconfig.json`, and source tree. Shared TypeScript config in `tsconfig.base.json`.

**Backend** (`apps/backend/src/`):

- `index.ts` — All routes, middleware (CORS, logging, error handler), graceful shutdown. Routes use `Bun.sql` tagged template literals for raw SQL queries — no ORM.
- `env.ts` — Validates required env vars at startup, exports typed `env` object.
- `db/client.ts` — `Bun.sql` connection pool with `waitForDatabase()` retry loop.
- `db/run-migrations.ts` — golang-migrate wrapper. It builds the MySQL migration URL, bootstraps old `schema_migrations` state into `parrot_schema_migrations` when needed, then delegates execution to the `migrate` CLI.

**Frontend** (`apps/frontend/src/`):

- Rsbuild (Rspack) with `pluginReact` and `pluginLess`.
- React, react-dom, react-dom/client are CDN externals (UMD bundles from `s.fubodong.com`).
- Routes defined in `routes/config.tsx` with `React.lazy()` and a 404 catch-all.
- CSS Modules (`.module.less`) for all component styles.
- `components/ErrorBoundary.tsx` catches lazy-load chunk failures.

**API convention:** All `/api/*` endpoints use POST method. Only `/healthz` uses GET for Docker healthchecks and nginx.

**Docker setup:**

- `docker-compose.yml` — Local dev: backend (bun), mysql, nginx. Nginx mounts host `./apps/frontend/dist` and serves whatever the host-side Bun watcher builds there.
- `docker-compose.deploy.yml` — Production: same services minus dev container. Nginx image just copies pre-built frontend assets.

**Backend dev hot reload:** The backend container runs with `bun --watch` and mounts `apps/backend/src/` and `apps/backend/migrations/` as volumes. On Linux (CI/CD, remote servers), file changes trigger automatic process restart. On macOS Docker, VirtioFS does not propagate file system events to inotify, so `--watch` is inactive — use `make restart` instead.

**Base images** are synced to Aliyun ACR via `make sync-base-images`. Shared base repositories use reusable names (`base-bun`, `base-migrate`, `base-nginx`, `base-mysql`) instead of project-specific prefixes. `make start` assumes those base images already exist in ACR. Production builds target `linux/amd64`.

## Key Conventions

- **Package manager:** Bun everywhere — `bun install`, `bun run`, `bun.lock`. No npm or Node.js.
- **Migrations:** Only add new paired files in `apps/backend/migrations/` with `NNNN_description.up.sql` and `NNNN_description.down.sql` naming. Never modify existing migration files. Use `make create-migration NAME=...` to get auto-numbered files.
- **SQL:** Raw SQL via `Bun.sql` tagged templates, no query builders or ORMs. Type results with inline `TypeRow[]` generics.
- **Environment variables:** Backend reads from `process.env` via `env.ts` with validation and defaults. Inside Docker, `DATABASE_HOST` is overridden to `mysql`. All secrets live in `.env` (gitignored).
- **Host-first workflow:** `make install`, `make build`, `make frontend-build`, `make lint`, `make format`, `make format-check`, `make type-check`, and `make watch` all run through host Bun. The watcher lifecycle is managed internally by `make start`, `make down`, and `make restart`.
- **Backend changes on macOS:** Source is bind-mounted into the container, so backend edits take effect after `make restart`; no extra image rebuild is required for normal code changes.
