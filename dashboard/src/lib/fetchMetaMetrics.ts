import type { MetaMetricsReport } from './metaTypes';

export async function fetchMetaMetrics(): Promise<MetaMetricsReport> {
  const res = await fetch('./meta-metrics.json', { cache: 'no-store' });
  if (!res.ok) throw new Error(`meta-metrics.json ${res.status}`);
  const raw = await res.json();
  return {
    generated_at: raw.generated_at ?? '',
    gandalf: raw.gandalf ?? {},
    saruman: raw.saruman ?? {},
    loop_health: raw.loop_health ?? {},
  } as MetaMetricsReport;
}
