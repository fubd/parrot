import React from 'react';
import {Button, Space, Tag, Typography} from 'antd';
import {Link} from 'react-router-dom';
import {request} from '../../utils/request';
import styles from './index.module.less';

const {Paragraph, Title} = Typography;

type SummaryData = {
  appName: string;
  version: string;
  environment: string;
  publishedNewsCount: number;
  latestPublishedAt: string | null;
  services: string[];
};

const Home: React.FC = () => {
  const [summary, setSummary] = React.useState<SummaryData | null>(null);

  React.useEffect(() => {
    let cancelled = false;

    const loadSummary = async () => {
      const result = await request<SummaryData>('/api/v1/system/summary');
      if (!cancelled && result.success && result.data) {
        setSummary(result.data);
      }
    };

    void loadSummary();

    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className={styles.homeWrapper}>
      <section className={styles.hero}>
        <div className={styles.heroCopy}>
          <Tag color="cyan" bordered={false}>
            Full-stack refactor branch
          </Tag>
          <h1 className={styles.heroTitle}>HELLO WORLD</h1>
          <p className={styles.heroSubtitle}>
            React stays on the surface, Hono serves the API, MySQL stores the data, and nginx routes
            traffic without taking on SSL responsibility inside the container boundary.
          </p>
          <Space size="middle" wrap>
            <Button type="primary" size="large">
              <Link to="/news">Browse API-backed news</Link>
            </Button>
            <Button size="large" href="/api/health" target="_blank" rel="noreferrer">
              Open backend health
            </Button>
          </Space>
        </div>

        <div className={styles.systemPanel}>
          <div className={styles.systemPanelHeader}>
            <span className={styles.systemPanelEyebrow}>System summary</span>
            <span className={`${styles.systemPill}${summary ? ` ${styles.systemPillLive}` : ''}`}>
              {summary ? 'API online' : 'Waiting for API'}
            </span>
          </div>

          <div className={styles.systemStats}>
            <article className={styles.statCard}>
              <span className={styles.statLabel}>App name</span>
              <strong className={styles.statValue}>{summary?.appName ?? 'Parrot'}</strong>
            </article>
            <article className={styles.statCard}>
              <span className={styles.statLabel}>Published news</span>
              <strong className={styles.statValue}>{summary?.publishedNewsCount ?? 0}</strong>
            </article>
            <article className={styles.statCard}>
              <span className={styles.statLabel}>Last content sync</span>
              <strong className={styles.statValue}>
                {summary?.latestPublishedAt ?? 'Pending'}
              </strong>
            </article>
            <article className={styles.statCard}>
              <span className={styles.statLabel}>Runtime</span>
              <strong className={styles.statValue}>{summary?.environment ?? 'development'}</strong>
            </article>
          </div>

          <div className={styles.serviceList}>
            {(
              summary?.services ?? [
                'React 19 + Rsbuild',
                'Hono + TypeScript',
                'Bun.sql + MySQL',
                'Nginx + Docker Compose',
              ]
            ).map(service => (
              <span key={service} className={styles.serviceTag}>
                {service}
              </span>
            ))}
          </div>

          <p className={styles.statusMessage}>
            The page reads real data from the new backend, so you can immediately verify the full
            stack is connected.
          </p>
        </div>
      </section>

      <section className={styles.grid}>
        <article className={styles.card}>
          <Title level={4}>Raw SQL stays visible</Title>
          <Paragraph>
            The backend keeps database behavior close to the code you read every day, with Bun.sql
            used as the connection and SQL execution layer instead of hiding queries behind heavy
            repositories.
          </Paragraph>
        </article>

        <article className={styles.card}>
          <Title level={4}>Docker is production-oriented</Title>
          <Paragraph>
            Frontend, backend, MySQL, and gateway nginx each have a clear role, while compose keeps
            ports predictable and images ready for Aliyun ACR publishing.
          </Paragraph>
        </article>

        <article className={styles.card}>
          <Title level={4}>Operations live in Makefile</Title>
          <Paragraph>
            Build, type-check, migrate, run, push, and remote deploy commands are centralized so the
            refactor is easier to operate than a stack of ad-hoc shell history.
          </Paragraph>
        </article>
      </section>
    </div>
  );
};

export default Home;
