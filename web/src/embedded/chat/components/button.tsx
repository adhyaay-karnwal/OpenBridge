import { cn } from '@/utils/cn';

interface ButtonProps {
  children: React.ReactNode;
  onClick: (e: React.MouseEvent) => void;
  variant?: 'primary' | 'secondary';
  disabled?: boolean;
  className?: string;
}

export const Button = ({
  children,
  onClick,
  variant = 'secondary',
  disabled = false,
  className,
}: ButtonProps) => {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={cn(
        'rounded-[8px] border px-[8px] py-[3px] text-[12px] leading-[16px] cursor-pointer transition-all disabled:opacity-50',
        variant === 'primary'
          ? 'border-transparent bg-primary text-primary-highlight hover:brightness-95 active:brightness-90'
          : 'border-border bg-surface-card text-text-primary hover:bg-fill-soft active:bg-fill-medium disabled:bg-surface-card-muted disabled:text-text-tertiary',
        className
      )}
    >
      {children}
    </button>
  );
};
