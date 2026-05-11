import { useEffect, useMemo, useRef, useState } from 'react';
import { CueStreamdownAudio } from './audio';

type RecordingProps = React.HTMLAttributes<HTMLElement> & {
  path?: string;
  src?: string;
};

type RecordingSession = {
  stream: MediaStream;
  audioContext: AudioContext;
  source: MediaStreamAudioSourceNode;
  processor: ScriptProcessorNode;
  muteGain: GainNode;
  chunks: Float32Array[];
  sampleRate: number;
  startedAtMs: number;
  recordedSamples: number;
  secondSums: number[];
  secondCounts: number[];
  waveformIntervalId: number | null;
};

const BAR_SPACING = 5;
const BAR_STROKE_WIDTH = 2;
const WAVEFORM_HEIGHT = 26;
const MIN_BAR_HEIGHT = 4;
const SECONDS_PER_BAR = 0.5;
const MAX_SAMPLES = 50;
const MAX_DURATION = SECONDS_PER_BAR * MAX_SAMPLES;
const WAVEFORM_REFRESH_INTERVAL_MS = 100;

function extractVmUrl(raw: string): string | null {
  const match = raw.match(/vm:\/\/[^\s"'`<>]+/i);
  if (!match) {
    return null;
  }
  return match[0];
}

function collectChildrenText(children: React.ReactNode): string[] {
  if (children == null) {
    return [];
  }

  if (typeof children === 'string' || typeof children === 'number') {
    return [String(children)];
  }

  if (Array.isArray(children)) {
    return children.flatMap(collectChildrenText);
  }

  if (
    typeof children === 'object' &&
    children !== null &&
    'props' in children &&
    typeof (children as { props?: { children?: React.ReactNode } }).props ===
      'object'
  ) {
    return collectChildrenText(
      (children as { props?: { children?: React.ReactNode } }).props?.children
    );
  }

  return [];
}

function extractPath(
  path: unknown,
  src: unknown,
  children: React.ReactNode
): string | null {
  const candidates: string[] = [];
  const pushIfString = (value: unknown) => {
    if (typeof value === 'string' && value.trim()) {
      candidates.push(value.trim());
    }
  };

  pushIfString(path);
  pushIfString(src);
  for (const text of collectChildrenText(children)) {
    pushIfString(text);
  }

  for (const candidate of candidates) {
    const vmUrl = extractVmUrl(candidate);
    if (vmUrl) {
      return vmUrl;
    }
  }

  return null;
}

function withCacheBust(url: string, nonce: number): string {
  const separator = url.includes('?') ? '&' : '?';
  return `${url}${separator}recording_nonce=${nonce}`;
}

function formatTime(seconds: number): string {
  const wholeSeconds = Math.max(0, Math.floor(seconds));
  const minutes = Math.floor(wholeSeconds / 60);
  const restSeconds = wholeSeconds % 60;
  return `${minutes.toString().padStart(2, '0')}:${restSeconds.toString().padStart(2, '0')}`;
}

function getSampleCount(audioDuration: number): number {
  if (!Number.isFinite(audioDuration) || audioDuration <= 0) {
    return 1;
  }
  if (audioDuration > MAX_DURATION) {
    return MAX_SAMPLES;
  }
  return Math.max(1, Math.ceil(audioDuration / SECONDS_PER_BAR));
}

function createPlaceholderWaveform(sampleCount: number): number[] {
  return Array.from({ length: sampleCount }, () => 0.1);
}

function mapAverageAmplitudeToBar(average: number): number {
  return Math.max(0.1, Math.min(1, average * 40));
}

function buildWaveformFromSecondBuckets(
  secondSums: number[],
  secondCounts: number[],
  elapsedSeconds: number
): number[] {
  const sampleCount = getSampleCount(elapsedSeconds);
  if (sampleCount <= 0) {
    return [];
  }

  const totalBars = Math.max(1, Math.ceil(elapsedSeconds / SECONDS_PER_BAR));
  if (totalBars <= 0) {
    return createPlaceholderWaveform(sampleCount);
  }

  // <=25s: one bar per 0.5s. Completed bars remain stable; only current bar keeps changing.
  if (elapsedSeconds <= MAX_DURATION) {
    const bars: number[] = [];
    for (let i = 0; i < sampleCount; i++) {
      const sum = secondSums[i] ?? 0;
      const count = secondCounts[i] ?? 0;
      bars.push(count > 0 ? mapAverageAmplitudeToBar(sum / count) : 0.1);
    }
    return bars;
  }

  // >25s: keep 50 bars and increase covered time window per bar.
  const sourceBarsPerBar = totalBars / sampleCount;
  const bars: number[] = [];
  for (let i = 0; i < sampleCount; i++) {
    const startSecond = Math.floor(i * sourceBarsPerBar);
    const endSecond = Math.min(
      totalBars,
      Math.floor((i + 1) * sourceBarsPerBar)
    );

    let weightedSum = 0;
    let weightedCount = 0;
    for (let second = startSecond; second < endSecond; second++) {
      const count = secondCounts[second] ?? 0;
      if (count <= 0) {
        continue;
      }
      weightedSum += secondSums[second] ?? 0;
      weightedCount += count;
    }
    bars.push(
      weightedCount > 0
        ? mapAverageAmplitudeToBar(weightedSum / weightedCount)
        : 0.1
    );
  }

  return bars;
}

function mergePcmChunks(chunks: Float32Array[]): Float32Array {
  const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const merged = new Float32Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.length;
  }
  return merged;
}

function writeWavString(view: DataView, offset: number, value: string) {
  for (let i = 0; i < value.length; i++) {
    view.setUint8(offset + i, value.charCodeAt(i));
  }
}

function encodeWav(pcmData: Float32Array, sampleRate: number): ArrayBuffer {
  const bytesPerSample = 2;
  const dataSize = pcmData.length * bytesPerSample;
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);

  writeWavString(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeWavString(view, 8, 'WAVE');
  writeWavString(view, 12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * bytesPerSample, true);
  view.setUint16(32, bytesPerSample, true);
  view.setUint16(34, 16, true);
  writeWavString(view, 36, 'data');
  view.setUint32(40, dataSize, true);

  let offset = 44;
  for (let i = 0; i < pcmData.length; i++) {
    const sample = Math.max(-1, Math.min(1, pcmData[i]));
    const intSample = sample < 0 ? sample * 0x8000 : sample * 0x7fff;
    view.setInt16(offset, intSample, true);
    offset += bytesPerSample;
  }

  return buffer;
}

async function closeRecordingSession(session: RecordingSession | null) {
  if (!session) {
    return;
  }

  if (session.waveformIntervalId !== null) {
    window.clearInterval(session.waveformIntervalId);
  }

  session.processor.onaudioprocess = null;
  session.source.disconnect();
  session.processor.disconnect();
  session.muteGain.disconnect();
  session.stream.getTracks().forEach(track => track.stop());
  await session.audioContext.close();
}

export const CueStreamdownRecording = ({
  path,
  src,
  children,
  className,
}: RecordingProps) => {
  const targetPath = useMemo(
    () => extractPath(path, src, children),
    [path, src, children]
  );

  const [isRecording, setIsRecording] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [waveformData, setWaveformData] = useState<number[]>(
    createPlaceholderWaveform(10)
  );
  const [recordedPath, setRecordedPath] = useState<string | null>(null);
  const [previewNonce, setPreviewNonce] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const sessionRef = useRef<RecordingSession | null>(null);

  useEffect(() => {
    return () => {
      void closeRecordingSession(sessionRef.current);
      sessionRef.current = null;
    };
  }, []);

  const startRecording = async () => {
    if (!targetPath || isRecording || isSaving) {
      return;
    }
    if (!targetPath.toLowerCase().endsWith('.wav')) {
      setError('Recording path must end with .wav');
      return;
    }
    if (!navigator.mediaDevices?.getUserMedia) {
      setError('Microphone recording is not supported in this environment');
      return;
    }

    setError(null);
    setElapsedSeconds(0);
    setRecordedPath(null);
    setWaveformData(createPlaceholderWaveform(getSampleCount(1)));

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const audioContext = new AudioContext();
      const source = audioContext.createMediaStreamSource(stream);

      const processor = audioContext.createScriptProcessor(4096, 1, 1);
      const muteGain = audioContext.createGain();
      muteGain.gain.value = 0;
      const chunks: Float32Array[] = [];

      processor.onaudioprocess = event => {
        const activeSession = sessionRef.current;
        if (!activeSession) {
          return;
        }
        const input = event.inputBuffer.getChannelData(0);
        chunks.push(new Float32Array(input));

        // Aggregate amplitude by 0.5-second bars so old bars remain stable during recording.
        let sampleIndex = activeSession.recordedSamples;
        for (let i = 0; i < input.length; i++) {
          const secondIndex = Math.floor(
            sampleIndex / (activeSession.sampleRate * SECONDS_PER_BAR)
          );
          activeSession.secondSums[secondIndex] =
            (activeSession.secondSums[secondIndex] ?? 0) + Math.abs(input[i]);
          activeSession.secondCounts[secondIndex] =
            (activeSession.secondCounts[secondIndex] ?? 0) + 1;
          sampleIndex += 1;
        }
        activeSession.recordedSamples = sampleIndex;
      };

      source.connect(processor);
      processor.connect(muteGain);
      muteGain.connect(audioContext.destination);

      const session: RecordingSession = {
        stream,
        audioContext,
        source,
        processor,
        muteGain,
        chunks,
        sampleRate: audioContext.sampleRate,
        startedAtMs: Date.now(),
        recordedSamples: 0,
        secondSums: [],
        secondCounts: [],
        waveformIntervalId: null,
      };
      sessionRef.current = session;
      setIsRecording(true);

      const updateWaveform = () => {
        const activeSession = sessionRef.current;
        if (!activeSession) {
          return;
        }
        const seconds = (Date.now() - activeSession.startedAtMs) / 1000;
        setWaveformData(
          buildWaveformFromSecondBuckets(
            activeSession.secondSums,
            activeSession.secondCounts,
            seconds
          )
        );
        setElapsedSeconds(seconds);
      };
      updateWaveform();
      session.waveformIntervalId = window.setInterval(
        updateWaveform,
        WAVEFORM_REFRESH_INTERVAL_MS
      );
    } catch (e) {
      await closeRecordingSession(sessionRef.current);
      sessionRef.current = null;
      setIsRecording(false);
      const message =
        e instanceof Error ? e.message : 'Failed to start recording';
      setError(message);
    }
  };

  const stopAndSaveRecording = async () => {
    if (!targetPath || !isRecording || isSaving) {
      return;
    }

    const session = sessionRef.current;
    sessionRef.current = null;
    setIsRecording(false);
    setIsSaving(true);
    setError(null);

    try {
      await closeRecordingSession(session);
      if (!session) {
        throw new Error('No active recording session');
      }

      const pcmData = mergePcmChunks(session.chunks);
      if (pcmData.length === 0) {
        throw new Error('No audio was captured');
      }

      const wavBuffer = encodeWav(pcmData, session.sampleRate);
      const uploadResponse = await fetch(targetPath, {
        method: 'POST',
        body: new Uint8Array(wavBuffer),
      });
      if (!uploadResponse.ok) {
        const details = await uploadResponse.text();
        throw new Error(
          details || `Failed to save recording (${uploadResponse.status})`
        );
      }

      let savedPath = targetPath;
      const contentType = uploadResponse.headers.get('content-type') || '';
      if (contentType.includes('application/json')) {
        const payload = await uploadResponse.json();
        if (
          payload &&
          typeof payload.path === 'string' &&
          payload.path.startsWith('vm://')
        ) {
          savedPath = payload.path;
        }
      }

      const nextPath = savedPath || targetPath;
      setRecordedPath(nextPath);
      setPreviewNonce(prev => prev + 1);
      setElapsedSeconds(pcmData.length / session.sampleRate);
    } catch (e) {
      const message =
        e instanceof Error ? e.message : 'Failed to save recording';
      setError(message);
    } finally {
      setIsSaving(false);
    }
  };

  const previewPath = recordedPath
    ? withCacheBust(recordedPath, previewNonce)
    : null;

  if (!targetPath) {
    return (
      <div className="inline-flex flex-col gap-1 rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-600">
        <span>Invalid recording tag</span>
        <code className="text-xs text-red-500">
          Use: {'<recording path="vm:///.../voice.wav"></recording>'}
        </code>
      </div>
    );
  }

  if (!isRecording && !previewPath) {
    return (
      <div
        className={`inline-flex max-w-full flex-col gap-2 ${className ?? ''}`}
      >
        <button
          type="button"
          onClick={startRecording}
          disabled={isSaving}
          style={{
            flexShrink: 0,
            width: '30px',
            height: '30px',
            borderRadius: '999px',
            backgroundColor: '#FF3B30',
            border: 'none',
            cursor: isSaving ? 'not-allowed' : 'pointer',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: 0,
            color: 'white',
            opacity: isSaving ? 0.6 : 1,
          }}
          aria-label="Start recording"
        >
          <span
            style={{
              width: '10px',
              height: '10px',
              borderRadius: '999px',
              backgroundColor: 'white',
            }}
          />
        </button>
        {isSaving ? (
          <div className="text-xs text-zinc-500">Saving...</div>
        ) : null}
        {error ? <div className="text-xs text-red-600">{error}</div> : null}
      </div>
    );
  }

  if (isRecording) {
    return (
      <div
        className={`inline-flex max-w-full flex-col gap-2 ${className ?? ''}`}
      >
        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '8px',
            backgroundColor: 'rgba(255, 255, 255, 0.2)',
            borderRadius: '16px',
            padding: '8px 11px',
            maxWidth: '420px',
          }}
        >
          <button
            type="button"
            onClick={stopAndSaveRecording}
            disabled={isSaving}
            style={{
              flexShrink: 0,
              width: '30px',
              height: '30px',
              borderRadius: '999px',
              backgroundColor: '#D70015',
              border: 'none',
              cursor: isSaving ? 'not-allowed' : 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              padding: 0,
              color: 'white',
              opacity: isSaving ? 0.6 : 1,
            }}
            aria-label="Stop and save recording"
          >
            <span
              style={{
                width: '10px',
                height: '10px',
                borderRadius: '2px',
                backgroundColor: 'white',
              }}
            />
          </button>

          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              padding: '2px 8px',
              flexGrow: 1,
              flexShrink: 0,
            }}
          >
            <svg
              width={
                waveformData.length > 0
                  ? (waveformData.length - 1) * BAR_SPACING + BAR_STROKE_WIDTH
                  : (getSampleCount(elapsedSeconds || 1) - 1) * BAR_SPACING +
                    BAR_STROKE_WIDTH
              }
              height={WAVEFORM_HEIGHT}
              style={{ overflow: 'visible', userSelect: 'none' }}
            >
              {(waveformData.length > 0
                ? waveformData
                : createPlaceholderWaveform(getSampleCount(elapsedSeconds || 1))
              ).map((value, index) => {
                const barHeight = Math.max(
                  value * WAVEFORM_HEIGHT,
                  MIN_BAR_HEIGHT
                );
                const x = index * BAR_SPACING + BAR_STROKE_WIDTH / 2;
                const y1 = (WAVEFORM_HEIGHT - barHeight) / 2;
                const y2 = y1 + barHeight;
                return (
                  <line
                    key={`${x}-${barHeight}`}
                    x1={x}
                    y1={y1}
                    x2={x}
                    y2={y2}
                    stroke="rgba(255, 255, 255, 0.9)"
                    strokeWidth={BAR_STROKE_WIDTH}
                    strokeLinecap="round"
                  />
                );
              })}
            </svg>
          </div>

          <span
            style={{
              flexShrink: 0,
              color: 'white',
              fontSize: '13px',
              fontFamily: 'SF Pro, -apple-system, system-ui, sans-serif',
              fontWeight: 500,
              width: '37px',
              textAlign: 'center',
              lineHeight: '19px',
              letterSpacing: '-0.16px',
            }}
          >
            {formatTime(elapsedSeconds)}
          </span>
        </div>
        {isSaving ? (
          <div className="text-xs text-zinc-500">Saving...</div>
        ) : null}
        {error ? <div className="text-xs text-red-600">{error}</div> : null}
      </div>
    );
  }

  return (
    <div className={`inline-flex max-w-full flex-col gap-2 ${className ?? ''}`}>
      <CueStreamdownAudio
        src={previewPath ?? undefined}
        controls
        leadingControl={
          <button
            type="button"
            onClick={startRecording}
            disabled={isSaving}
            style={{
              flexShrink: 0,
              width: '30px',
              height: '30px',
              borderRadius: '999px',
              backgroundColor: '#FF3B30',
              border: 'none',
              cursor: isSaving ? 'not-allowed' : 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              padding: 0,
              color: 'white',
              opacity: isSaving ? 0.6 : 1,
            }}
            aria-label="Re-record"
            title="Re-record"
          >
            <span
              style={{
                width: '10px',
                height: '10px',
                borderRadius: '999px',
                backgroundColor: 'white',
              }}
            />
          </button>
        }
      />
      {isSaving ? <div className="text-xs text-zinc-500">Saving...</div> : null}
      {error ? <div className="text-xs text-red-600">{error}</div> : null}
    </div>
  );
};
