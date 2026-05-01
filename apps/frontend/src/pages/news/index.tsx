import React from 'react';
import {Card, Skeleton, Typography} from 'antd';
import {request} from '../../utils/request';

type NewsItem = {
  id: number;
  slug: string;
  title: string;
  summary: string;
  body: string;
  publishedAt: string;
};

type NewsData = {
  items: NewsItem[];
};

const News: React.FC = () => {
  const [items, setItems] = React.useState<NewsItem[]>([]);
  const [loading, setLoading] = React.useState(true);

  React.useEffect(() => {
    let cancelled = false;

    const loadNews = async () => {
      const result = await request<NewsData>('/api/v1/news');
      if (!cancelled) {
        if (result.success && result.data) {
          setItems(result.data.items);
        }
        setLoading(false);
      }
    };

    void loadNews();

    return () => {
      cancelled = true;
    };
  }, []);

  if (loading) {
    return <Skeleton active paragraph={{rows: 8}} />;
  }

  return (
    <div style={{display: 'grid', gap: 20}}>
      <Typography.Title level={2} style={{marginBottom: 0}}>
        News now
      </Typography.Title>
      <Typography.Paragraph style={{marginTop: 0}}>
        These entries are coming from MySQL through the Hono API.
      </Typography.Paragraph>
      {items.map(item => (
        <Card key={item.id} title={item.title} extra={item.publishedAt}>
          <Typography.Paragraph>{item.summary}</Typography.Paragraph>
          <Typography.Paragraph type="secondary">{item.body}</Typography.Paragraph>
        </Card>
      ))}
    </div>
  );
};

export default News;
