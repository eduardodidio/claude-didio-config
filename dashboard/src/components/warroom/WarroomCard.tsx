// ---------------------------------------------------------------------------
// F31-T04 -- WarroomCard component
// A text-heavy card representing a single War Room entry within a column.
// ---------------------------------------------------------------------------

import { motion } from 'framer-motion';
import { Card, CardHeader, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import {
  User,
  Bot,
  Globe,
  CheckCircle2,
  Clock,
  HelpCircle,
  Archive,
} from 'lucide-react';
import type {
  WarRoomCard as WarRoomCardType,
  CardSource,
  Priority,
  OverlordRecommendation,
} from '@/lib/warroomTypes';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

export interface WarroomCardProps {
  card: WarRoomCardType;
  onSelect?: (cardId: string) => void;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SOURCE_ICONS: Record<CardSource, React.ElementType> = {
  operator: User,
  agent: Bot,
  external: Globe,
};

const SOURCE_LABELS: Record<CardSource, string> = {
  operator: 'Operator',
  agent: 'Agent',
  external: 'External',
};

const PRIORITY_COLORS: Record<Priority, string> = {
  low: 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300',
  medium: 'bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300',
  high: 'bg-orange-100 text-orange-700 dark:bg-orange-900 dark:text-orange-300',
  max: 'bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300',
};

const RECOMMENDATION_CONFIG: Record<
  OverlordRecommendation,
  { icon: React.ElementType; label: string; colorClass: string }
> = {
  promote: {
    icon: CheckCircle2,
    label: 'Promote',
    colorClass: 'text-green-600 dark:text-green-400',
  },
  defer: {
    icon: Clock,
    label: 'Defer',
    colorClass: 'text-gray-500 dark:text-gray-400',
  },
  archive: {
    icon: Archive,
    label: 'Archive',
    colorClass: 'text-slate-500 dark:text-slate-400',
  },
  needs_input: {
    icon: HelpCircle,
    label: 'Needs Input',
    colorClass: 'text-amber-600 dark:text-amber-400',
  },
};

/** Format an ISO date string as a relative time (e.g. "3h ago"). */
function relativeTime(isoString: string): string {
  const now = Date.now();
  const then = new Date(isoString).getTime();
  const diffMs = now - then;

  if (diffMs < 0) return 'just now';

  const seconds = Math.floor(diffMs / 1000);
  if (seconds < 60) return `${seconds}s ago`;

  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;

  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;

  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

/** Truncate text to a maximum length, appending ellipsis when truncated. */
function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return text.slice(0, max).trimEnd() + '\u2026';
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function WarroomCard({ card, onSelect }: WarroomCardProps) {
  const SourceIcon = SOURCE_ICONS[card.source];
  const assessment = card.overlord_assessment;

  return (
    <motion.div
      whileHover={{ scale: 1.02, y: -2 }}
      transition={{ duration: 0.15 }}
      className="cursor-pointer"
      data-testid={`warroom-card-${card.card_id}`}
    >
      <Card
        className="relative overflow-hidden transition-shadow hover:shadow-md"
        onClick={() => onSelect?.(card.card_id)}
      >
        <CardHeader className="p-3 pb-1">
          {/* Header row: card ID badge + source icon */}
          <div
            className="flex items-center justify-between gap-2"
            data-testid={`card-header-${card.card_id}`}
          >
            <Badge
              variant="secondary"
              className="font-mono text-[10px] shrink-0"
              data-testid={`card-id-badge-${card.card_id}`}
            >
              {card.card_id}
            </Badge>
            <span
              className="flex items-center gap-1 text-xs text-muted-foreground"
              title={SOURCE_LABELS[card.source]}
              data-testid={`card-source-${card.card_id}`}
            >
              <SourceIcon className="h-3.5 w-3.5" />
            </span>
          </div>

          {/* Title */}
          <h4
            className="mt-1 text-sm font-bold leading-tight truncate"
            title={card.title}
            data-testid={`card-title-${card.card_id}`}
          >
            {truncate(card.title, 60)}
          </h4>
        </CardHeader>

        <CardContent className="p-3 pt-1 space-y-2">
          {/* Body preview (first ~120 chars, roughly 2 lines) */}
          <p
            className="text-xs text-muted-foreground leading-relaxed line-clamp-2"
            data-testid={`card-body-${card.card_id}`}
          >
            {card.body}
          </p>

          {/* Tags */}
          {card.tags.length > 0 && (
            <div
              className="flex flex-wrap gap-1"
              data-testid={`card-tags-${card.card_id}`}
            >
              {card.tags.map((tag) => (
                <Badge
                  key={tag}
                  variant="outline"
                  className="text-[10px] px-1.5 py-0"
                >
                  {tag}
                </Badge>
              ))}
            </div>
          )}

          {/* Priority pill */}
          {card.priority_suggestion && (
            <Badge
              className={`text-[10px] ${PRIORITY_COLORS[card.priority_suggestion]}`}
              data-testid={`card-priority-${card.card_id}`}
            >
              {card.priority_suggestion.toUpperCase()}
            </Badge>
          )}

          {/* Overlord assessment indicator */}
          {assessment && (
            <div
              className={`flex items-center gap-1 text-xs ${RECOMMENDATION_CONFIG[assessment.recommendation].colorClass}`}
              data-testid={`card-assessment-${card.card_id}`}
            >
              {(() => {
                const RecIcon = RECOMMENDATION_CONFIG[assessment.recommendation].icon;
                return <RecIcon className="h-3.5 w-3.5" />;
              })()}
              <span className="font-medium">
                {RECOMMENDATION_CONFIG[assessment.recommendation].label}
              </span>
            </div>
          )}

          {/* Timestamp */}
          <div className="flex justify-end">
            <span
              className="text-[10px] text-muted-foreground tabular-nums"
              data-testid={`card-timestamp-${card.card_id}`}
            >
              {relativeTime(card.created_at)}
            </span>
          </div>
        </CardContent>
      </Card>
    </motion.div>
  );
}

export default WarroomCard;
