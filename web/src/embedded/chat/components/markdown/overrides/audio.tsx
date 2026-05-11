import { useState, useRef, useEffect, useCallback } from 'react';
import { cn } from '@/utils/cn';
import { AudioWaveform } from './audio-waveform';
import { interpolate, type Options } from 'flubber';
import { animate, useReducedMotion } from 'motion/react';
import { Menu } from '@/utils/webview-context-menu';
import {
  preparePreviewAsset,
  previewAttachmentSource,
} from '../../messages/file-reference-actions';

type CueStreamdownAudioProps = React.ComponentProps<'audio'> & {
  leadingControl?: React.ReactNode;
  sourcePath?: string;
  environmentId?: string;
  artifactId?: string;
  fileName?: string;
  mimeType?: string;
};

const PLAYBACK_RATES = [0.5, 1, 1.5, 2, 3] as const;

/**
 * Custom audio player component with waveform visualization.
 * Renders a styled player for all audio sources.
 */
export const CueStreamdownAudio = ({
  src,
  className,
  controls: _controls,
  leadingControl,
  sourcePath,
  environmentId,
  artifactId,
  fileName,
  mimeType,
  ...props
}: CueStreamdownAudioProps) => {
  const [error, setError] = useState<string | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [playbackRate, setPlaybackRate] =
    useState<(typeof PLAYBACK_RATES)[number]>(1);
  const audioRef = useRef<HTMLAudioElement>(null);
  const animationRef = useRef<number>();
  const wasPlayingRef = useRef(false);

  // Setup when audio metadata is loaded
  const handleMetadataLoaded = useCallback(() => {
    if (!audioRef.current) {
      return;
    }

    setDuration(audioRef.current.duration);
    if (typeof src === 'string') {
      preparePreviewAsset(src, fileName, mimeType);
    }
  }, [fileName, mimeType, src]);

  useEffect(() => {
    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (audioRef.current) {
      audioRef.current.playbackRate = playbackRate;
    }
  }, [playbackRate, src]);

  const updateProgress = useCallback(() => {
    if (audioRef.current) {
      setCurrentTime(audioRef.current.currentTime);
      if (isPlaying) {
        animationRef.current = requestAnimationFrame(updateProgress);
      }
    }
  }, [isPlaying]);

  useEffect(() => {
    if (isPlaying) {
      animationRef.current = requestAnimationFrame(updateProgress);
    }
    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [isPlaying, updateProgress]);

  const togglePlay = useCallback(() => {
    if (!audioRef.current) return;
    if (isPlaying) {
      audioRef.current.pause();
      setIsPlaying(false);
      return;
    }

    void audioRef.current.play();
    setIsPlaying(true);
  }, [isPlaying]);

  const handleSeekStart = useCallback(
    (nextTime: number) => {
      if (!audioRef.current || duration <= 0) {
        return;
      }

      wasPlayingRef.current = isPlaying;

      if (isPlaying) {
        audioRef.current.pause();
        setIsPlaying(false);
      }

      setCurrentTime(nextTime);
    },
    [duration, isPlaying]
  );

  const handleSeekPreview = useCallback((nextTime: number) => {
    setCurrentTime(nextTime);
  }, []);

  const handleSeekCommit = useCallback(
    (nextTime: number) => {
      if (!audioRef.current || duration <= 0) {
        return;
      }

      audioRef.current.currentTime = nextTime;
      setCurrentTime(nextTime);

      if (wasPlayingRef.current) {
        void audioRef.current.play();
        setIsPlaying(true);
      }
    },
    [duration]
  );

  const formatTime = (time: number) => {
    const minutes = Math.floor(time / 60);
    const seconds = Math.floor(time % 60);
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  };

  const handleContextMenu = useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      const speedMenu = Menu.create();
      for (const rate of PLAYBACK_RATES) {
        speedMenu.pushItem({
          title: `${rate}x`,
          onClick: () => setPlaybackRate(rate),
        });
      }

      const menu = Menu.create();
      const previewSource = typeof src === 'string' ? src : undefined;
      if (previewSource || sourcePath) {
        menu.pushItem({
          title: 'Preview',
          icon: Menu.icon.symbol('document.viewfinder'),
          onClick: () => {
            void previewAttachmentSource(previewSource, {
              fileName,
              mimeType,
              fallbackPath: sourcePath,
              environmentId,
            });
          },
        });
      }

      menu
        .pushItem({
          title: isPlaying ? 'Pause' : 'Play',
          icon: isPlaying
            ? Menu.icon.symbol('pause')
            : Menu.icon.symbol('play'),
          onClick: () => togglePlay(),
        })
        .pushSubmenu({
          title: 'Speed',
          icon: Menu.icon.symbol('gauge.with.dots.needle.67percent'),
          items: speedMenu,
        });

      menu.popup(event);
    },
    [environmentId, fileName, isPlaying, mimeType, sourcePath, src, togglePlay]
  );

  // Error state
  if (error) {
    return (
      <div className="inline-flex flex-col rounded-lg border border-error-fg/35 bg-error-bg p-4">
        <span className="text-sm text-error-fg">{error}</span>
        <code className="mt-1 text-xs text-error-fg">{src}</code>
      </div>
    );
  }

  return (
    <>
      {/* Completely hidden audio element */}
      <audio
        ref={audioRef}
        src={src}
        preload="metadata"
        onTimeUpdate={() => setCurrentTime(audioRef.current?.currentTime || 0)}
        onLoadedMetadata={handleMetadataLoaded}
        onEnded={() => setIsPlaying(false)}
        onError={() => setError('Failed to load audio')}
        style={{ display: 'none' }}
        {...props}
      />

      {/* Custom player UI - matches Figma design */}
      <div
        onContextMenu={handleContextMenu}
        className={cn(
          className,
          'self-start inline-flex max-w-full items-center gap-2 overflow-hidden rounded-xl border border-border bg-surface-overlay px-3 py-2 backdrop-blur-md'
        )}
        data-artifact={artifactId}
      >
        {leadingControl}

        {/* Play/Pause button */}
        <button
          onClick={togglePlay}
          className={cn(
            'shrink-0 size-7.5 rounded-full flex-center p-0',
            'bg-primary text-primary-foreground border-none',
            'cursor-pointer hover:brightness-95'
          )}
          aria-label={isPlaying ? 'Pause' : 'Play'}
        >
          <PlayButtonIcon isPlaying={isPlaying} />
        </button>

        <AudioWaveform
          src={typeof src === 'string' ? src : undefined}
          duration={duration}
          currentTime={currentTime}
          onSeekStart={handleSeekStart}
          onSeekPreview={handleSeekPreview}
          onSeekCommit={handleSeekCommit}
        />

        {/* Time display */}
        <span
          className="w-[37px] shrink-0 text-center text-[13px] font-medium leading-[19px] tracking-[-0.16px] text-text-primary"
          style={{
            fontFamily: 'SF Pro, -apple-system, system-ui, sans-serif',
          }}
        >
          {formatTime(currentTime > 0 ? currentTime : duration)}
        </span>

        <label
          className="relative inline-flex items-center shrink-0"
          aria-label="Playback speed"
        >
          <select
            value={playbackRate}
            onChange={event =>
              setPlaybackRate(
                Number(event.target.value) as (typeof PLAYBACK_RATES)[number]
              )
            }
            className={cn(
              'appearance-none cursor-pointer rounded-full border border-border bg-fill-soft pt-1 pb-1 pl-2 pr-5 text-xs font-medium leading-none text-text-primary',
              'focus:outline-none'
            )}
          >
            {PLAYBACK_RATES.map(rate => (
              <option key={rate} value={rate}>
                {rate}x
              </option>
            ))}
          </select>

          <span
            aria-hidden="true"
            className="pointer-events-none absolute right-2 text-[9px] text-text-tertiary"
          >
            ▼
          </span>
        </label>
      </div>
    </>
  );
};

const PLAY_BUTTON_PATHS = {
  left: 'M8 7.11426V16.7666C8 17.1403 8.0957 17.4183 8.28711 17.6006C8.47852 17.7874 8.70638 17.8809 8.9707 17.8809C9.20768 17.8809 9.44466 17.8148 9.68164 17.6826L13 15.74V8.13L9.68164 6.19824C9.44466 6.06608 9.20768 6 8.9707 6C8.70638 6 8.47852 6.09115 8.28711 6.27344C8.0957 6.45573 8 6.736 8 7.11426Z',
  right:
    'M18.3838 11.3899C18.2562 11.2395 18.0465 11.08 17.7549 10.9113L12.5596 7.87598V15.9975L17.7549 12.9621C18.0465 12.7935 18.2562 12.634 18.3838 12.4836C18.516 12.3287 18.582 12.1464 18.582 11.9367C18.582 11.7225 18.516 11.5402 18.3838 11.3899Z',
} as const;

const PAUSE_BUTTON_PATHS = {
  left: 'M8.97754 17.6758C8.64941 17.6758 8.40332 17.5938 8.23926 17.4297C8.07975 17.2656 8 17.0195 8 16.6914V6.97754C8 6.65397 8.08203 6.41016 8.24609 6.24609C8.41016 6.08203 8.65397 6 8.97754 6H10.584C10.903 6 11.1445 6.07975 11.3086 6.23926C11.4772 6.39876 11.5615 6.64486 11.5615 6.97754V16.6914C11.5615 17.0195 11.4772 17.2656 11.3086 17.4297C11.1445 17.5938 10.903 17.6758 10.584 17.6758H8.97754Z',
  right:
    'M14.1592 17.6758C13.8311 17.6758 13.585 17.5938 13.4209 17.4297C13.2568 17.2656 13.1748 17.0195 13.1748 16.6914V6.97754C13.1748 6.65397 13.2568 6.41016 13.4209 6.24609C13.585 6.08203 13.8311 6 14.1592 6H15.752C16.0801 6 16.3262 6.07975 16.4902 6.23926C16.6543 6.39876 16.7363 6.64486 16.7363 6.97754V16.6914C16.7363 17.0195 16.6543 17.2656 16.4902 17.4297C16.3262 17.5938 16.0801 17.6758 15.752 17.6758H14.1592Z',
} as const;

const PLAY_BUTTON_MORPH_DURATION = 180;
const PLAY_BUTTON_MORPH_OPTIONS = { maxSegmentLength: 0.25 } satisfies Options;

const getPlayButtonIconPaths = (isPlaying: boolean) =>
  isPlaying ? PAUSE_BUTTON_PATHS : PLAY_BUTTON_PATHS;

const PlayButtonIcon = ({ isPlaying }: { isPlaying: boolean }) => {
  const shouldReduceMotion = useReducedMotion();
  const initialPathsRef = useRef(getPlayButtonIconPaths(isPlaying));
  const leftPathRef = useRef<SVGPathElement>(null);
  const rightPathRef = useRef<SVGPathElement>(null);
  const hasMountedRef = useRef(false);
  const previousIsPlayingRef = useRef(isPlaying);
  const animationRef = useRef<ReturnType<typeof animate> | null>(null);

  useEffect(() => {
    const leftPath = leftPathRef.current;
    const rightPath = rightPathRef.current;
    const nextPaths = getPlayButtonIconPaths(isPlaying);

    if (!leftPath || !rightPath) {
      return;
    }

    if (!hasMountedRef.current) {
      hasMountedRef.current = true;
      previousIsPlayingRef.current = isPlaying;
      return;
    }

    const previousIsPlaying = previousIsPlayingRef.current;
    previousIsPlayingRef.current = isPlaying;

    animationRef.current?.stop();

    if (shouldReduceMotion) {
      leftPath.setAttribute('d', nextPaths.left);
      rightPath.setAttribute('d', nextPaths.right);
      return;
    }

    if (previousIsPlaying === isPlaying) {
      leftPath.setAttribute('d', nextPaths.left);
      rightPath.setAttribute('d', nextPaths.right);
      return;
    }

    const leftFrom =
      leftPath.getAttribute('d') ??
      getPlayButtonIconPaths(previousIsPlaying).left;
    const rightFrom =
      rightPath.getAttribute('d') ??
      getPlayButtonIconPaths(previousIsPlaying).right;
    const leftInterpolator = interpolate(
      leftFrom,
      nextPaths.left,
      PLAY_BUTTON_MORPH_OPTIONS
    );
    const rightInterpolator = interpolate(
      rightFrom,
      nextPaths.right,
      PLAY_BUTTON_MORPH_OPTIONS
    );

    animationRef.current = animate(0, 1, {
      duration: PLAY_BUTTON_MORPH_DURATION / 1000,
      ease: 'easeInOut',
      onUpdate: latest => {
        leftPath.setAttribute('d', leftInterpolator(latest));
        rightPath.setAttribute('d', rightInterpolator(latest));
      },
      onComplete: () => {
        leftPath.setAttribute('d', nextPaths.left);
        rightPath.setAttribute('d', nextPaths.right);
      },
    });

    return () => {
      animationRef.current?.stop();
    };
  }, [isPlaying, shouldReduceMotion]);

  return (
    <svg
      aria-hidden="true"
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path ref={leftPathRef} d={initialPathsRef.current.left} fill="white" />
      <path ref={rightPathRef} d={initialPathsRef.current.right} fill="white" />
    </svg>
  );
};
