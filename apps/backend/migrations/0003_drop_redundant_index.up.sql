-- The composite index `idx_news_posts_published` from migration 0002
-- covers all queries on `published_at`, making the standalone index redundant.
DROP INDEX idx_news_posts_published_at ON news_posts;
