import { useCallback, useEffect, useId, useRef, useState } from 'react';

type AudioWaveformProps = {
  src?: string;
  duration: number;
  currentTime: number;
  onSeekStart?: (nextTime: number) => void;
  onSeekPreview?: (nextTime: number) => void;
  onSeekCommit?: (nextTime: number) => void;
};

const SECONDS_PER_BAR = 0.5;
const MAX_DURATION = 25;
const BAR_SPACING = 5;
const BAR_STROKE_WIDTH = 2;
const MIN_SAMPLES = 10;
const MAX_SAMPLES = 45;
const WAVEFORM_HEIGHT = 26;
const MIN_BAR_HEIGHT = 4;
const DEFAULT_PLACEHOLDER_DURATION = 5;

const clamp = (value: number, min: number, max: number) =>
  Math.min(Math.max(value, min), max);

const getSampleCount = (audioDuration: number) => {
  if (!Number.isFinite(audioDuration) || audioDuration <= 0) {
    return MIN_SAMPLES;
  }

  if (audioDuration > MAX_DURATION) {
    return MAX_SAMPLES;
  }

  return Math.max(
    MIN_SAMPLES,
    Math.min(MAX_SAMPLES, Math.ceil(audioDuration / SECONDS_PER_BAR))
  );
};

const createPlaceholderWaveform = (sampleCount: number) =>
  Array.from({ length: sampleCount }, () => 0.1);

const buildWaveformData = (rawData: Float32Array, sampleCount: number) => {
  const blockSize = Math.floor(rawData.length / sampleCount);
  if (blockSize <= 0) {
    return createPlaceholderWaveform(sampleCount);
  }

  const filteredData: number[] = [];

  for (let index = 0; index < sampleCount; index++) {
    let sum = 0;

    for (let sampleIndex = 0; sampleIndex < blockSize; sampleIndex++) {
      sum += Math.abs(rawData[index * blockSize + sampleIndex]);
    }

    filteredData.push(sum / blockSize);
  }

  const maxValue = Math.max(...filteredData);

  return filteredData.map(value =>
    maxValue > 0 ? Math.max(0.1, value / maxValue) : 0.1
  );
};

const WaveformBars = ({ data, stroke }: { data: number[]; stroke: string }) => (
  <>
    {data.map((value, index) => {
      const barHeight = Math.max(value * WAVEFORM_HEIGHT, MIN_BAR_HEIGHT);
      const x = index * BAR_SPACING + BAR_STROKE_WIDTH / 2;
      const y1 = (WAVEFORM_HEIGHT - barHeight) / 2;
      const y2 = y1 + barHeight;

      return (
        <line
          key={`${stroke}-${index}`}
          x1={x}
          y1={y1}
          x2={x}
          y2={y2}
          stroke={stroke}
          strokeWidth={BAR_STROKE_WIDTH}
          strokeLinecap="round"
        />
      );
    })}
  </>
);

export const AudioWaveform = ({
  src,
  duration,
  currentTime,
  onSeekStart,
  onSeekPreview,
  onSeekCommit,
}: AudioWaveformProps) => {
  const [waveformData, setWaveformData] = useState<number[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const waveformRef = useRef<SVGSVGElement>(null);
  const uniqueId = useId().replace(/:/g, '');

  useEffect(() => {
    setWaveformData([]);

    if (!src || duration <= 0) {
      return;
    }

    const sampleCount = getSampleCount(duration);
    let isCancelled = false;
    let audioContext: AudioContext | null = null;

    const closeAudioContext = () => {
      if (audioContext && audioContext.state !== 'closed') {
        void audioContext.close();
      }
    };

    const loadWaveform = async () => {
      try {
        const response = await fetch(src);
        const arrayBuffer = await response.arrayBuffer();

        if (isCancelled) {
          return;
        }

        audioContext = new AudioContext();
        const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

        if (isCancelled) {
          closeAudioContext();
          return;
        }

        const nextWaveform = buildWaveformData(
          audioBuffer.getChannelData(0),
          sampleCount
        );

        if (!isCancelled) {
          setWaveformData(nextWaveform);
        }
      } catch (error) {
        console.warn('Waveform generation failed:', error);

        if (!isCancelled) {
          setWaveformData(createPlaceholderWaveform(sampleCount));
        }
      } finally {
        closeAudioContext();
      }
    };

    void loadWaveform();

    return () => {
      isCancelled = true;
      closeAudioContext();
    };
  }, [duration, src]);

  const displayWaveform =
    waveformData.length > 0
      ? waveformData
      : createPlaceholderWaveform(
          getSampleCount(duration || DEFAULT_PLACEHOLDER_DURATION)
        );
  const waveformWidth =
    (displayWaveform.length - 1) * BAR_SPACING + BAR_STROKE_WIDTH;
  const progress = duration > 0 ? clamp(currentTime / duration, 0, 1) : 0;
  const playedWidth = waveformWidth * progress;
  const maskId = `${uniqueId}-wave-mask`;

  const getSeekTimeFromClientX = useCallback(
    (clientX: number) => {
      if (!waveformRef.current || duration <= 0) {
        return null;
      }

      const rect = waveformRef.current.getBoundingClientRect();
      const offsetX = clamp(clientX - rect.left, 0, rect.width);

      return (offsetX / rect.width) * duration;
    },
    [duration]
  );

  const handleMouseDown = (event: React.MouseEvent<SVGSVGElement>) => {
    if (event.button !== 0 || event.ctrlKey) {
      return;
    }

    const nextTime = getSeekTimeFromClientX(event.clientX);
    if (nextTime === null) {
      return;
    }

    event.preventDefault();
    setIsDragging(true);
    onSeekStart?.(nextTime);
  };

  useEffect(() => {
    if (!isDragging) {
      return;
    }

    const handleMouseMove = (event: MouseEvent) => {
      const nextTime = getSeekTimeFromClientX(event.clientX);

      if (nextTime !== null) {
        onSeekPreview?.(nextTime);
      }
    };

    const handleMouseUp = (event: MouseEvent) => {
      const nextTime = getSeekTimeFromClientX(event.clientX);

      if (nextTime !== null) {
        onSeekCommit?.(nextTime);
      }

      setIsDragging(false);
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);

    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [getSeekTimeFromClientX, isDragging, onSeekCommit, onSeekPreview]);

  return (
    <div className="flex items-center px-2 py-0.5">
      <svg
        ref={waveformRef}
        onMouseDown={handleMouseDown}
        width={waveformWidth}
        height={WAVEFORM_HEIGHT}
        style={{
          cursor:
            duration > 0 ? (isDragging ? 'grabbing' : 'pointer') : 'default',
          overflow: 'visible',
          userSelect: 'none',
        }}
      >
        <defs>
          <mask id={maskId} maskUnits="userSpaceOnUse">
            <rect
              x={0}
              y={0}
              width={playedWidth}
              height={WAVEFORM_HEIGHT}
              fill="white"
            />
          </mask>
        </defs>

        <WaveformBars
          data={displayWaveform}
          stroke="var(--color-audio-waveform-unplayed)"
        />

        <g mask={`url(#${maskId})`}>
          <WaveformBars
            data={displayWaveform}
            stroke="var(--color-text-primary)"
          />
        </g>
      </svg>
    </div>
  );
};
