ARG BASE_BUN_IMAGE=registry.cn-hangzhou.aliyuncs.com/fubd_own/base-bun:1-alpine
ARG MIGRATE_IMAGE=migrate/migrate:v4.19.1
ARG BUN_CONFIG_REGISTRY=https://registry.npmmirror.com

FROM ${MIGRATE_IMAGE} AS migrate

FROM ${BASE_BUN_IMAGE} AS runner
WORKDIR /app

ARG BUN_CONFIG_REGISTRY
ENV BUN_CONFIG_REGISTRY=${BUN_CONFIG_REGISTRY}

RUN apk add --no-cache wget
COPY --from=migrate /usr/bin/migrate /usr/local/bin/migrate

ENV BUN_ENV=production
ENV PORT=26031

COPY apps/backend/package.json ./package.json
RUN bun install --production

COPY apps/backend/src ./src
COPY apps/backend/migrations ./migrations

EXPOSE 26031

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q -O - http://127.0.0.1:26031/healthz >/dev/null || exit 1

CMD ["bun", "./src/index.ts"]
