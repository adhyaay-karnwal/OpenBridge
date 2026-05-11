import clsx from 'clsx';
import {
  cloneElement,
  createContext,
  isValidElement,
  useCallback,
  useContext,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type HTMLAttributes,
  type ReactElement,
  type ReactNode,
  type Ref,
} from 'react';
import { createPortal } from 'react-dom';
import { useUtilsBridgeDebugMode } from './use-utils-bridge';

// Utility to merge refs
function mergeRefs<T>(...refs: (Ref<T> | undefined)[]): Ref<T> {
  return (value: T) => {
    refs.forEach(ref => {
      if (typeof ref === 'function') {
        ref(value);
      } else if (ref != null) {
        (ref as React.MutableRefObject<T | null>).current = value;
      }
    });
  };
}

const ICON_SIZE = 14;
const ICON_GAP = 2;

type DebugEntry = {
  id: string;
  title?: string;
  data: unknown;
  position: { top: number; left: number };
};

type DebugContextValue = {
  enabled: boolean;
  register: (
    id: string,
    title: string | undefined,
    data: unknown,
    position: { top: number; left: number }
  ) => void;
  unregister: (id: string) => void;
  updatePosition: (id: string, position: { top: number; left: number }) => void;
};

const DebugContext = createContext<DebugContextValue | null>(null);

/**
 * Provider that manages and renders all debug messages
 * Coordinates positions to prevent overlapping
 */
export const DebugMessageProvider = ({ children }: { children: ReactNode }) => {
  const [entries, setEntries] = useState<Map<string, DebugEntry>>(new Map());
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const debugMode = useUtilsBridgeDebugMode();

  const enabled = debugMode ?? process.env.NODE_ENV === 'development';

  const register = useCallback(
    (
      id: string,
      title: string | undefined,
      data: unknown,
      position: { top: number; left: number }
    ) => {
      setEntries(prev => {
        const next = new Map(prev);
        next.set(id, { id, title, data, position });
        return next;
      });
    },
    []
  );

  const unregister = useCallback((id: string) => {
    setEntries(prev => {
      const next = new Map(prev);
      next.delete(id);
      return next;
    });
  }, []);

  const updatePosition = useCallback(
    (id: string, position: { top: number; left: number }) => {
      setEntries(prev => {
        const entry = prev.get(id);
        if (!entry) return prev;
        const next = new Map(prev);
        next.set(id, { ...entry, position });
        return next;
      });
    },
    []
  );

  const contextValue = useMemo(
    () => ({ enabled, register, unregister, updatePosition }),
    [enabled, register, unregister, updatePosition]
  );

  // Group entries by similar top position (within 20px) and calculate offsets
  const entriesWithOffsets = useMemo(() => {
    const sortedEntries = Array.from(entries.values()).sort(
      (a, b) =>
        a.position.top - b.position.top || a.position.left - b.position.left
    );

    const result: Array<DebugEntry & { offsetX: number }> = [];
    const groups: Map<number, number> = new Map(); // groupTop -> count

    for (const entry of sortedEntries) {
      // Find if there's an existing group within 20px
      let groupKey = -1;
      for (const [top] of groups) {
        if (Math.abs(entry.position.top - top) < 20) {
          groupKey = top;
          break;
        }
      }

      if (groupKey === -1) {
        // New group
        groups.set(entry.position.top, 1);
        result.push({ ...entry, offsetX: 0 });
      } else {
        // Existing group
        const count = groups.get(groupKey) || 0;
        groups.set(groupKey, count + 1);
        result.push({ ...entry, offsetX: count * (ICON_SIZE + ICON_GAP) });
      }
    }

    return result;
  }, [entries]);

  return (
    <DebugContext.Provider value={contextValue}>
      {children}
      {createPortal(
        <>
          {entriesWithOffsets.map(entry => (
            <DebugIcon
              key={entry.id}
              entry={entry}
              offsetX={entry.offsetX}
              isHovered={hoveredId === entry.id}
              onHover={hovered => setHoveredId(hovered ? entry.id : null)}
            />
          ))}
        </>,
        document.body
      )}
    </DebugContext.Provider>
  );
};

const DebugIcon = ({
  entry,
  offsetX,
  isHovered,
  onHover,
}: {
  entry: DebugEntry;
  offsetX: number;
  isHovered: boolean;
  onHover: (hovered: boolean) => void;
}) => {
  const [copied, setCopied] = useState(false);

  const handleDoubleClick = useCallback(() => {
    const text = JSON.stringify(entry.data, null, 2);
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1000);
    });
  }, [entry.data]);

  return (
    <div
      style={{
        position: 'absolute',
        top: entry.position.top,
        left: entry.position.left + offsetX,
        zIndex: isHovered ? 10000 : 9999,
        userSelect: 'none',
      }}
      onMouseEnter={() => onHover(true)}
      onMouseLeave={() => onHover(false)}
    >
      {/* Debug icon */}
      <div
        onDoubleClick={handleDoubleClick}
        style={{
          width: `${ICON_SIZE}px`,
          height: `${ICON_SIZE}px`,
          borderRadius: '3px',
          backgroundColor: copied
            ? 'rgba(0, 200, 0, 0.9)'
            : isHovered
              ? 'rgba(255, 0, 0, 0.9)'
              : 'rgba(255, 0, 0, 0.5)',
          color: 'white',
          fontSize: '9px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          cursor: 'pointer',
          userSelect: 'none',
          transition: 'background-color 0.15s',
        }}
      >
        {copied ? '✓' : '🐛'}
      </div>

      {/* Tooltip with JSON data */}
      {isHovered && (
        <div
          style={{
            position: 'absolute',
            top: '16px',
            left: '0',
            backgroundColor: 'rgba(30, 30, 30, 0.95)',
            border: '1px solid rgba(255, 0, 0, 0.5)',
            borderRadius: '6px',
            padding: '8px',
            width: '400px',
            height: '300px',
            overflow: 'auto',
            boxShadow: '0 4px 12px rgba(0, 0, 0, 0.3)',
          }}
        >
          {entry.title && (
            <div
              style={{ fontSize: '10px', fontWeight: 'bold', color: '#ff6b6b' }}
            >
              {entry.title}
            </div>
          )}
          <pre
            style={{
              margin: 0,
              padding: 0,
              fontSize: '8px',
              lineHeight: '1.4',
              color: '#ff6b6b',
              whiteSpace: 'pre-wrap',
              wordBreak: 'break-all',
              fontFamily: 'ui-monospace, monospace',
            }}
          >
            {JSON.stringify(entry.data, null, 2)}
          </pre>
        </div>
      )}
    </div>
  );
};

type DebugMessageProps = HTMLAttributes<HTMLDivElement> & {
  data: unknown;
  title?: string;
  children: ReactNode;
  /** When true, clones the child element and adds ref to it instead of wrapping in a div */
  asChild?: boolean;
};

/**
 * Debug container component for displaying raw JSON data of messages
 * Wraps children in a div and uses that div's position for the debug icon
 * Registers with DebugMessageProvider which handles rendering
 * All other props are passed through to the container div
 *
 * When asChild is true, it clones the child element and adds a ref to get position
 */
export const DebugMessage = ({
  data,
  children,
  asChild = false,
  title,
  className,
  ...divProps
}: DebugMessageProps) => {
  const id = useId();
  const containerRef = useRef<HTMLElement>(null);
  const context = useContext(DebugContext);

  useEffect(() => {
    if (!context) return;
    if (!context.enabled) return;

    const updatePosition = () => {
      if (containerRef.current) {
        const rect = containerRef.current.getBoundingClientRect();
        const position = {
          top: rect.top + window.scrollY,
          left: rect.left + window.scrollX,
        };
        context.updatePosition(id, position);
      }
    };

    // Initial register
    if (containerRef.current) {
      const rect = containerRef.current.getBoundingClientRect();
      context.register(id, title, data, {
        top: rect.top + window.scrollY,
        left: rect.left + window.scrollX,
      });
    }

    // Update position on scroll and resize
    window.addEventListener('scroll', updatePosition, true);
    window.addEventListener('resize', updatePosition);

    return () => {
      context.unregister(id);
      window.removeEventListener('scroll', updatePosition, true);
      window.removeEventListener('resize', updatePosition);
    };
  }, [context, id, data, title]);

  // asChild mode: clone the child and add ref
  if (asChild) {
    if (!isValidElement(children)) {
      console.warn(
        'DebugMessage: asChild requires a single valid React element as children'
      );
      return <>{children}</>;
    }

    const child = children as ReactElement<{ ref?: Ref<HTMLElement> }>;
    return cloneElement(child, {
      ref: mergeRefs(containerRef, child.props.ref),
    });
  }

  // TODO: add a div wrapper may influence the layout of the children
  return (
    <div
      ref={containerRef as Ref<HTMLDivElement>}
      className={clsx('hide-if-empty', className)}
      {...divProps}
    >
      {children}
    </div>
  );
};
