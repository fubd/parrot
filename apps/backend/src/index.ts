import {Hono} from 'hono';
import {HTTPException} from 'hono/http-exception';
import {cors} from 'hono/cors';
import {logger} from 'hono/logger';
import {db, closeDatabase, waitForDatabase} from './db/client.js';
import {env} from './env.js';

type SummaryRow = {
  publishedNewsCount: number;
  latestPublishedAt: string | null;
};

type NewsRow = {
  id: number;
  slug: string;
  title: string;
  summary: string;
  body: string;
  publishedAt: string;
};

const app = new Hono();

app.use('*', logger());

app.onError((err, context) => {
  const status = err instanceof HTTPException ? err.status : 500;
  console.error(`[backend] ❌ ${context.req.method} ${context.req.path} →`, err);
  return context.json(
    {
      success: false,
      message: err instanceof Error ? err.message : 'Internal Server Error',
    },
    status,
  );
});

app.notFound(context => {
  return context.json(
    {
      success: false,
      message: `${context.req.method} ${context.req.path} not found`,
    },
    404,
  );
});

app.use('/api/*', cors({origin: '*'}));

app.get('/healthz', async context => {
  await db`SELECT 1 AS ok`;
  return context.json({
    status: 'ok',
    service: 'backend',
    database: 'connected',
  });
});

app.post('/api/health', async context => {
  await db`SELECT 1 AS ok`;
  return context.json({
    success: true,
    data: {
      database: 'connected',
      version: env.version,
    },
  });
});

app.post('/api/v1/system/summary', async context => {
  const [summary] = await db<SummaryRow[]>`
    SELECT
      COUNT(*) AS publishedNewsCount,
      DATE_FORMAT(MAX(published_at), '%Y-%m-%d %H:%i:%s') AS latestPublishedAt
    FROM news_posts
    WHERE is_published = 1
  `;

  return context.json({
    success: true,
    data: {
      appName: env.appName,
      version: env.version,
      environment: env.nodeEnv,
      publishedNewsCount: Number(summary?.publishedNewsCount ?? 0),
      latestPublishedAt: summary?.latestPublishedAt ?? null,
      services: ['React 19 + Rsbuild', 'Hono + Bun', 'Bun.sql (MySQL)', 'Nginx + Docker Compose'],
    },
  });
});

app.post('/api/v1/news', async context => {
  const rows = await db<NewsRow[]>`
    SELECT
      id,
      slug,
      title,
      summary,
      body,
      DATE_FORMAT(published_at, '%Y-%m-%d') AS publishedAt
    FROM news_posts
    WHERE is_published = 1
    ORDER BY published_at DESC, id DESC
  `;

  return context.json({
    success: true,
    data: {
      items: rows.map(row => ({
        id: Number(row.id),
        slug: row.slug,
        title: row.title,
        summary: row.summary,
        body: row.body,
        publishedAt: row.publishedAt,
      })),
    },
  });
});

app.post('/api/v1/meta', context => {
  return context.json({
    success: true,
    data: {
      appName: env.appName,
      version: env.version,
      ports: {
        frontend: Number(process.env.FRONTEND_PORT ?? 26030),
        backend: Number(process.env.BACKEND_PORT ?? 26031),
        mysql: Number(process.env.MYSQL_PORT ?? 26032),
        nginx: Number(process.env.NGINX_PORT ?? 26033),
      },
    },
  });
});

let isShuttingDown = false;

const shutdown = async (signal: string) => {
  if (isShuttingDown) return;
  isShuttingDown = true;
  console.log(`[backend] received ${signal}, shutting down`);
  server.stop(true);
  await closeDatabase();
  process.exit(0);
};

await waitForDatabase();

const server = Bun.serve({
  fetch: app.fetch,
  port: env.port,
  hostname: '0.0.0.0',
});

console.log(`[backend] listening on http://localhost:${server.port}`);

process.on('SIGINT', () => {
  void shutdown('SIGINT');
});
process.on('SIGTERM', () => {
  void shutdown('SIGTERM');
});
