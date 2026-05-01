CREATE TABLE IF NOT EXISTS news_posts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  slug VARCHAR(160) NOT NULL UNIQUE,
  title VARCHAR(180) NOT NULL,
  summary VARCHAR(255) NOT NULL,
  body TEXT NOT NULL,
  is_published TINYINT(1) NOT NULL DEFAULT 1,
  published_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_news_posts_published_at (published_at)
);

INSERT INTO news_posts (slug, title, summary, body, published_at)
VALUES
  (
    'full-stack-foundation',
    'Full-stack foundation is ready',
    'The starter now ships with React, Hono, raw SQL through Bun.sql, MySQL, nginx, Docker Compose, and Makefile automation.',
    'This branch turns the original frontend starter into a deployable full-stack baseline with a production-facing gateway and containerized services.',
    '2026-03-20 10:00:00'
  ),
  (
    'container-first-delivery',
    'Container-first delivery is built in',
    'Images, ports, remote deployment, and registry publishing are wired through Make targets so the stack is easier to operate.',
    'The deployment path is designed around Aliyun ACR images, a host-level nginx proxy, and a container nginx entrypoint that stays focused on HTTP routing.',
    '2026-03-21 09:00:00'
  ),
  (
    'mysql-with-raw-sql',
    'MySQL access stays close to SQL',
    'Database reads and writes are intentionally expressed as SQL statements, while Bun.sql provides the connection and execution layer.',
    'That keeps the backend easy to reason about and avoids hiding important database behavior behind extra repository abstractions.',
    '2026-03-22 08:30:00'
  )
ON DUPLICATE KEY UPDATE
  title = VALUES(title),
  summary = VALUES(summary),
  body = VALUES(body),
  is_published = VALUES(is_published),
  published_at = VALUES(published_at),
  updated_at = CURRENT_TIMESTAMP;
