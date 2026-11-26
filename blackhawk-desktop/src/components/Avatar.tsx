import { cn } from '@/lib/utils';

interface Props {
  src?: string;
  fallback?: string;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

const sizes = {
  sm: 'w-6 h-6 text-[10px]',
  md: 'w-8 h-8 text-xs',
  lg: 'w-12 h-12 text-base',
};

export function Avatar({ src, fallback = 'BH', size = 'md', className }: Props) {
  if (src) {
    return (
      <img
        src={src}
        alt="Avatar"
        className={cn('rounded-lg object-cover', sizes[size], className)}
      />
    );
  }

  return (
    <div
      className={cn(
        'rounded-lg bg-primary flex items-center justify-center font-bold text-primary-foreground',
        sizes[size],
        className
      )}
    >
      {fallback}
    </div>
  );
}
