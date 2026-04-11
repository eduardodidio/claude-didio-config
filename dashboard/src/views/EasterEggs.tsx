import { useEffect, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import type { EasterEggsFile } from '@/lib/types';

export interface NormalizedFranchise {
  key: string;
  name: string;
  color: string;
  emoji: string;
  phrases: string[];
}

export interface NormalizedEasterEggs {
  franchises: NormalizedFranchise[];
  role_mapping: Record<string, string>;
}

// HSL triplets so they can be composed into `hsl(...)` inline styles.
const FRANCHISE_COLORS: Record<string, string> = {
  mario: '0 85% 55%',
  pokemon: '48 95% 55%',
  naruto: '30 95% 55%',
  one_piece: '210 85% 55%',
  dragon_ball_z: '32 95% 50%',
  kimetsu_no_yaiba: '155 65% 40%',
  star_wars: '220 15% 30%',
  lord_of_the_rings: '90 35% 35%',
  dnd: '350 75% 40%',
};

const DEFAULT_COLOR = '265 70% 65%';
const CYCLE_MS = 2500;

function titleCase(key: string): string {
  return key
    .split('_')
    .map((w) => (w.length === 0 ? w : w[0].toUpperCase() + w.slice(1)))
    .join(' ');
}

export function normalizeEasterEggs(raw: EasterEggsFile): NormalizedEasterEggs {
  const franchises: NormalizedFranchise[] = Object.entries(raw.franchises ?? {}).map(
    ([key, value]) => ({
      key,
      name: titleCase(key),
      color: FRANCHISE_COLORS[key] ?? DEFAULT_COLOR,
      emoji: value.emoji ?? '✨',
      phrases: (value.success ?? []).slice(0, 4),
    }),
  );

  const role_mapping: Record<string, string> = {};
  for (const [role, list] of Object.entries(raw.role_mapping ?? {})) {
    if (Array.isArray(list) && list.length > 0) {
      role_mapping[role] = list[0];
    }
  }

  return { franchises, role_mapping };
}

function FranchiseCard({ franchise }: { franchise: NormalizedFranchise }) {
  const [idx, setIdx] = useState(0);
  const total = franchise.phrases.length;

  useEffect(() => {
    if (total <= 1) return;
    const id = setInterval(() => {
      setIdx((i) => (i + 1) % total);
    }, CYCLE_MS);
    return () => clearInterval(id);
  }, [total]);

  const phrase = total > 0 ? franchise.phrases[idx] : '';

  return (
    <Card data-testid={`franchise-${franchise.key}`}>
      <CardHeader className="flex-row items-center justify-between space-y-0">
        <span
          className="inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold text-white"
          style={{ backgroundColor: `hsl(${franchise.color})` }}
          data-testid={`chip-${franchise.key}`}
        >
          <span aria-hidden>{franchise.emoji}</span>
          {franchise.name}
        </span>
        <span className="text-xs text-muted-foreground">
          {total > 0 ? `${idx + 1} / ${total}` : '—'}
        </span>
      </CardHeader>
      <CardContent>
        <div className="min-h-[3.5rem] text-sm">
          <AnimatePresence mode="wait">
            <motion.p
              key={idx}
              data-testid={`phrase-${franchise.key}`}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.25 }}
            >
              {phrase}
            </motion.p>
          </AnimatePresence>
        </div>
      </CardContent>
    </Card>
  );
}

type LoadState =
  | { kind: 'loading' }
  | { kind: 'ready'; data: NormalizedEasterEggs }
  | { kind: 'error' };

export default function EasterEggs() {
  const [state, setState] = useState<LoadState>({ kind: 'loading' });

  useEffect(() => {
    let cancelled = false;
    fetch('./easter-eggs.json')
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.json() as Promise<EasterEggsFile>;
      })
      .then((raw) => {
        if (!cancelled) setState({ kind: 'ready', data: normalizeEasterEggs(raw) });
      })
      .catch(() => {
        if (!cancelled) setState({ kind: 'error' });
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (state.kind === 'loading') {
    return (
      <div className="p-6" data-testid="phrases-loading">
        <p className="text-sm text-muted-foreground">Loading phrases…</p>
      </div>
    );
  }

  if (state.kind === 'error') {
    return (
      <div className="space-y-2 p-6" data-testid="phrases-error">
        <h1 className="text-2xl font-semibold tracking-tight">Phrases</h1>
        <p className="text-sm text-muted-foreground">
          Could not load <code>easter-eggs.json</code>. Check that the file is
          served at the dashboard root.
        </p>
      </div>
    );
  }

  const { franchises, role_mapping } = state.data;
  const roleRows = Object.entries(role_mapping);

  return (
    <div className="space-y-6 p-6" data-testid="phrases-view">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Phrases</h1>
        <p className="text-sm text-muted-foreground">
          Thematic one-liners each agent role prints on task completion.
        </p>
      </div>

      {roleRows.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Role → Franchise</CardTitle>
          </CardHeader>
          <CardContent>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Role</TableHead>
                  <TableHead>Franchise</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {roleRows.map(([role, key]) => (
                  <TableRow key={role} data-testid={`role-row-${role}`}>
                    <TableCell className="font-medium">{role}</TableCell>
                    <TableCell>{titleCase(key)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {franchises.length === 0 ? (
        <p className="text-sm text-muted-foreground">No franchises to display.</p>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {franchises.map((f) => (
            <FranchiseCard key={f.key} franchise={f} />
          ))}
        </div>
      )}
    </div>
  );
}
