import { motion } from 'motion/react';

export const LoadingDots = () => (
  <span className="inline-flex gap-0.5">
    {[0, 1, 2].map(i => (
      <motion.span
        key={i}
        className="h-1 w-1 rounded-full"
        style={{ backgroundColor: 'var(--color-text-tertiary)' }}
        animate={{ opacity: [0.3, 1, 0.3] }}
        transition={{
          duration: 1,
          repeat: Infinity,
          delay: i * 0.15,
        }}
      />
    ))}
  </span>
);
