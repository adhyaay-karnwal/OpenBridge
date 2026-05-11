import { cn } from '@/utils/cn';
import { Link } from '../../link';

export const CueStreamdownA = ({
  children,
  className,
  ...props
}: React.ComponentProps<'a'>) => {
  return (
    <Link className={cn(className)} {...props}>
      {children}
    </Link>
  );
};
