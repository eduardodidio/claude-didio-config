import * as React from 'react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import type { CreateCardInput, Priority } from '@/lib/warroomTypes';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

export interface CardCreateFormProps {
  onSubmit: (input: CreateCardInput) => void;
  onCancel: () => void;
  isSubmitting?: boolean;
}

// ---------------------------------------------------------------------------
// Priority options
// ---------------------------------------------------------------------------

const PRIORITY_OPTIONS: Array<{ value: Priority | ''; label: string }> = [
  { value: '', label: 'None' },
  { value: 'low', label: 'Low' },
  { value: 'medium', label: 'Medium' },
  { value: 'high', label: 'High' },
  { value: 'max', label: 'Max' },
];

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function CardCreateForm({
  onSubmit,
  onCancel,
  isSubmitting = false,
}: CardCreateFormProps) {
  const [title, setTitle] = React.useState('');
  const [body, setBody] = React.useState('');
  const [priority, setPriority] = React.useState<Priority | ''>('');
  const [tagsInput, setTagsInput] = React.useState('');
  const [touched, setTouched] = React.useState<Record<string, boolean>>({});
  const [visible, setVisible] = React.useState(false);

  // Trigger enter animation on mount
  React.useEffect(() => {
    const frame = requestAnimationFrame(() => setVisible(true));
    return () => cancelAnimationFrame(frame);
  }, []);

  // ---- Derived state ----
  const titleError = touched.title && !title.trim() ? 'Title is required' : '';
  const bodyError = touched.body && !body.trim() ? 'Body is required' : '';
  const canSubmit = title.trim().length > 0 && body.trim().length > 0;

  // ---- Helpers ----
  const parseTags = (raw: string): string[] =>
    raw
      .split(',')
      .map((t) => t.trim())
      .filter(Boolean);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setTouched({ title: true, body: true });
    if (!canSubmit) return;

    const input: CreateCardInput = {
      title: title.trim(),
      body: body.trim(),
      source: 'operator',
      priority_suggestion: priority || null,
      tags: parseTags(tagsInput),
    };
    onSubmit(input);

    // Reset form
    setTitle('');
    setBody('');
    setPriority('');
    setTagsInput('');
    setTouched({});
  };

  const handleCancel = () => {
    setVisible(false);
    // Allow exit animation to run before calling onCancel
    setTimeout(onCancel, 200);
  };

  // ---- Tag chips preview ----
  const tagChips = parseTags(tagsInput);

  return (
    <div
      data-testid="card-create-form-wrapper"
      className={cn(
        'transition-all duration-200 ease-out overflow-hidden',
        visible
          ? 'max-h-[600px] opacity-100 translate-y-0'
          : 'max-h-0 opacity-0 -translate-y-2',
      )}
    >
      <Card className="border-dashed border-2 border-muted-foreground/30">
        <form onSubmit={handleSubmit} data-testid="card-create-form">
          <CardHeader className="pb-3">
            <CardTitle className="text-base">New War Room Card</CardTitle>
          </CardHeader>

          <CardContent className="space-y-4">
            {/* Title */}
            <div className="space-y-1.5">
              <label
                htmlFor="card-title"
                className="text-sm font-medium leading-none"
              >
                Title <span className="text-destructive">*</span>
              </label>
              <input
                id="card-title"
                data-testid="card-title-input"
                type="text"
                maxLength={200}
                placeholder="What needs attention?"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                onBlur={() => setTouched((t) => ({ ...t, title: true }))}
                className={cn(
                  'flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50',
                  titleError && 'border-destructive',
                )}
              />
              {titleError && (
                <p
                  data-testid="card-title-error"
                  className="text-xs text-destructive"
                >
                  {titleError}
                </p>
              )}
            </div>

            {/* Body */}
            <div className="space-y-1.5">
              <label
                htmlFor="card-body"
                className="text-sm font-medium leading-none"
              >
                Body <span className="text-destructive">*</span>
              </label>
              <textarea
                id="card-body"
                data-testid="card-body-input"
                rows={4}
                placeholder="Describe the situation..."
                value={body}
                onChange={(e) => setBody(e.target.value)}
                onBlur={() => setTouched((t) => ({ ...t, body: true }))}
                className={cn(
                  'flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50 resize-y min-h-[80px]',
                  bodyError && 'border-destructive',
                )}
              />
              {bodyError && (
                <p
                  data-testid="card-body-error"
                  className="text-xs text-destructive"
                >
                  {bodyError}
                </p>
              )}
            </div>

            {/* Priority */}
            <div className="space-y-1.5">
              <label
                htmlFor="card-priority"
                className="text-sm font-medium leading-none"
              >
                Priority suggestion
              </label>
              <select
                id="card-priority"
                data-testid="card-priority-select"
                value={priority}
                onChange={(e) =>
                  setPriority(e.target.value as Priority | '')
                }
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              >
                {PRIORITY_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </div>

            {/* Tags */}
            <div className="space-y-1.5">
              <label
                htmlFor="card-tags"
                className="text-sm font-medium leading-none"
              >
                Tags
              </label>
              <input
                id="card-tags"
                data-testid="card-tags-input"
                type="text"
                placeholder="auth, q1, refactor"
                value={tagsInput}
                onChange={(e) => setTagsInput(e.target.value)}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              />
              {tagChips.length > 0 && (
                <div
                  data-testid="card-tags-chips"
                  className="flex flex-wrap gap-1 pt-1"
                >
                  {tagChips.map((tag) => (
                    <Badge key={tag} variant="secondary" className="text-xs">
                      {tag}
                    </Badge>
                  ))}
                </div>
              )}
            </div>
          </CardContent>

          <CardFooter className="gap-2 justify-end">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={handleCancel}
              data-testid="card-create-cancel"
            >
              Cancel
            </Button>
            <Button
              type="submit"
              size="sm"
              disabled={!canSubmit || isSubmitting}
              data-testid="card-create-submit"
            >
              {isSubmitting ? 'Adding...' : 'Add Card'}
            </Button>
          </CardFooter>
        </form>
      </Card>
    </div>
  );
}
