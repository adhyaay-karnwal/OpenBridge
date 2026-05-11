import { useEffect } from 'react';
import { AnimatePresence, motion, useAnimationControls } from 'framer-motion';

const randomInRange = (min: number, max: number) =>
  Math.random() * (max - min) + min;

export const LoadingDot = ({
  show = true,
  className,
}: {
  show?: boolean;
  className?: string;
}) => {
  const controls = useAnimationControls();

  useEffect(() => {
    let isActive = true;

    if (!show) {
      controls.stop();
      controls.set({ scale: 1 });
      return;
    }

    const runBreathingLoop = async () => {
      while (isActive) {
        const inhaleScale = randomInRange(1.08, 1.28);
        const exhaleScale = randomInRange(0.85, 0.97);

        const inhaleDuration = randomInRange(0.7, 1.4);
        const exhaleDuration = randomInRange(0.8, 1.6);
        const restDuration = randomInRange(0.3, 0.7);

        // oxlint-disable-next-line no-await-in-loop
        await controls.start({
          scale: inhaleScale,
          transition: {
            duration: inhaleDuration,
            ease: 'easeInOut',
          },
        });

        if (!isActive) break;

        // oxlint-disable-next-line no-await-in-loop
        await controls.start({
          scale: exhaleScale,
          transition: {
            duration: exhaleDuration,
            ease: 'easeInOut',
          },
        });

        if (!isActive) break;

        // oxlint-disable-next-line no-await-in-loop
        await controls.start({
          scale: 1,
          transition: {
            duration: restDuration,
            ease: 'easeInOut',
          },
        });
      }
    };

    runBreathingLoop();

    return () => {
      isActive = false;
      controls.stop();
    };
  }, [controls, show]);

  return (
    <AnimatePresence>
      {show && (
        <motion.svg
          key="loading-dot"
          width="1em"
          height="1em"
          viewBox="0 0 16 16"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          exit={{ scale: 0 }}
          transition={{ duration: 0.2, ease: 'easeOut' }}
          className={className}
        >
          <motion.circle
            animate={controls}
            initial={{ scale: 1 }}
            cx="8"
            cy="8"
            r="6"
            fill="currentColor"
            strokeWidth="0"
            style={{ originX: 0.5, originY: 0.5 }}
          />
        </motion.svg>
      )}
    </AnimatePresence>
  );
};
