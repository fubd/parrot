-- Composite index to accelerate the most common query pattern:
-- WHERE is_published = 1 ORDER BY published_at DESC
-- The leading column (is_published) filters the working set; the trailing
-- column (published_at) satisfies the ORDER BY without a filesort.
ALTER TABLE news_posts
  ADD INDEX idx_news_posts_published (is_published, published_at DESC);
