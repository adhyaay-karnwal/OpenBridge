import {
  Streamdown,
  type AnimateOptions,
  type StreamdownProps,
  extractTableDataFromElement,
  tableDataToCSV,
  tableDataToMarkdown,
  tableDataToTSV,
} from 'streamdown';
import { CueStreamdownA } from './overrides/a';
import { CueStreamdownCode } from './overrides/code/memo-code';
import { CueStreamdownImg } from './overrides/img';
import { CueStreamdownRecording } from './overrides/recording';
import { CueStreamdownVideo } from './overrides/video';

import { code } from '@streamdown/code';
import { mermaid } from '@streamdown/mermaid';
import { math } from '@streamdown/math';
import { cjk } from '@streamdown/cjk';
import { createPortal } from 'react-dom';
import {
  type MouseEvent as ReactMouseEvent,
  type CSSProperties,
  useCallback,
  useEffect,
  useRef,
  useState,
} from 'react';
import { harden } from 'rehype-harden';
// KaTeX requires CSS
import 'katex/dist/katex.min.css';
import './streamdown.css';
import 'streamdown/styles.css';

type TableDropdownState = {
  kind: 'copy' | 'download';
  left: number;
  top: number;
  table: HTMLTableElement;
};

const tableDropdownButtonClassName =
  'w-full px-3 py-2 text-left text-sm text-popover-foreground transition-colors hover:bg-muted/40';

const tableDropdownMenuStyle = (left: number, top: number): CSSProperties => ({
  left,
  top,
  transform: 'translate3d(-100%, 0, 0)',
  WebkitTransform: 'translate3d(-100%, 0, 0)',
  backgroundColor: 'var(--color-popover)',
  opacity: 1,
  backdropFilter: 'none',
  WebkitBackdropFilter: 'none',
});

const getTableActionKind = (
  button: HTMLButtonElement
): TableDropdownState['kind'] | null => {
  const title = button.getAttribute('title');
  if (title === 'Copy table') {
    return 'copy';
  }
  if (title === 'Download table') {
    return 'download';
  }
  return null;
};

const copyTableToClipboard = async (
  tableElement: HTMLTableElement,
  format: 'md' | 'csv' | 'tsv'
) => {
  const tableData = extractTableDataFromElement(tableElement);
  const plainText =
    format === 'csv'
      ? tableDataToCSV(tableData)
      : format === 'tsv'
        ? tableDataToTSV(tableData)
        : tableDataToMarkdown(tableData);

  if (typeof ClipboardItem === 'undefined') {
    await navigator.clipboard.writeText(plainText);
    return;
  }

  const clipboardItem = new ClipboardItem({
    'text/plain': new Blob([plainText], { type: 'text/plain' }),
    'text/html': new Blob([tableElement.outerHTML], { type: 'text/html' }),
  });

  await navigator.clipboard.write([clipboardItem]);
};

const downloadTable = (
  tableElement: HTMLTableElement,
  format: 'csv' | 'markdown'
) => {
  const tableData = extractTableDataFromElement(tableElement);
  const content =
    format === 'csv'
      ? tableDataToCSV(tableData)
      : tableDataToMarkdown(tableData);
  const extension = format === 'csv' ? 'csv' : 'md';
  const mimeType = format === 'csv' ? 'text/csv' : 'text/markdown';

  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `table.${extension}`;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
};

const rehypePlugins = [
  [
    harden,
    {
      allowedLinkPrefixes: ['*'],
    },
  ],
];

const plugins = {
  code: code,
  mermaid,
  math,
  cjk,
};

const components = {
  a: CueStreamdownA,
  code: CueStreamdownCode,
  img: CueStreamdownImg,
  video: CueStreamdownVideo,
  recording: CueStreamdownRecording,
} as StreamdownProps['components'];

export const CueStreamdown = ({
  animated = true,
  ...props
}: Omit<StreamdownProps, 'components'>) => {
  const rootRef = useRef<HTMLDivElement>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const [tableDropdown, setTableDropdown] = useState<TableDropdownState | null>(
    null
  );
  const animatedProps = !animated
    ? false
    : ({
        sep: 'char',
        duration: 500,
        easing: 'ease',
        animation: 'blurIn',
        ...(typeof animated === 'object' ? animated : {}),
      } satisfies AnimateOptions);

  useEffect(() => {
    if (!tableDropdown) {
      return;
    }

    const handlePointerDown = (event: MouseEvent) => {
      const path = event.composedPath();
      if (dropdownRef.current && path.includes(dropdownRef.current)) {
        return;
      }
      setTableDropdown(null);
    };

    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setTableDropdown(null);
      }
    };

    const handleViewportChange = () => {
      setTableDropdown(null);
    };

    document.addEventListener('mousedown', handlePointerDown);
    document.addEventListener('keydown', handleEscape);
    window.addEventListener('resize', handleViewportChange);
    window.addEventListener('scroll', handleViewportChange, true);

    return () => {
      document.removeEventListener('mousedown', handlePointerDown);
      document.removeEventListener('keydown', handleEscape);
      window.removeEventListener('resize', handleViewportChange);
      window.removeEventListener('scroll', handleViewportChange, true);
    };
  }, [tableDropdown]);

  const handleTableActionCapture = useCallback(
    (event: ReactMouseEvent<HTMLDivElement>) => {
      const target = event.target;
      if (!(target instanceof Element)) {
        return;
      }

      const button = target.closest('button');
      if (!(button instanceof HTMLButtonElement) || button.disabled) {
        return;
      }

      const actionKind = getTableActionKind(button);
      if (!actionKind) {
        return;
      }

      const wrapper = button.closest('[data-streamdown="table-wrapper"]');
      if (!wrapper || !rootRef.current?.contains(wrapper)) {
        return;
      }

      const table = wrapper.querySelector('table[data-streamdown="table"]');
      if (!(table instanceof HTMLTableElement)) {
        return;
      }

      event.preventDefault();
      event.stopPropagation();

      const rect = button.getBoundingClientRect();
      setTableDropdown(current =>
        current &&
        current.kind === actionKind &&
        current.table === table &&
        current.left === rect.right &&
        current.top === rect.bottom + 4
          ? null
          : {
              kind: actionKind,
              left: rect.right,
              top: rect.bottom + 4,
              table,
            }
      );
    },
    []
  );

  const dropdownMenu = tableDropdown
    ? createPortal(
        <div
          className="table-action-menu fixed z-99999 min-w-[120px] overflow-hidden rounded-md border border-border text-popover-foreground shadow-lg"
          ref={dropdownRef}
          style={tableDropdownMenuStyle(tableDropdown.left, tableDropdown.top)}
        >
          <div aria-hidden="true" className="table-action-menu-backdrop" />
          <div className="table-action-menu-content">
            {tableDropdown.kind === 'copy' ? (
              <>
                <button
                  className={tableDropdownButtonClassName}
                  onClick={() => {
                    void copyTableToClipboard(tableDropdown.table, 'md');
                    setTableDropdown(null);
                  }}
                  type="button"
                >
                  Markdown
                </button>
                <button
                  className={tableDropdownButtonClassName}
                  onClick={() => {
                    void copyTableToClipboard(tableDropdown.table, 'csv');
                    setTableDropdown(null);
                  }}
                  type="button"
                >
                  CSV
                </button>
                <button
                  className={tableDropdownButtonClassName}
                  onClick={() => {
                    void copyTableToClipboard(tableDropdown.table, 'tsv');
                    setTableDropdown(null);
                  }}
                  type="button"
                >
                  TSV
                </button>
              </>
            ) : (
              <>
                <button
                  className={tableDropdownButtonClassName}
                  onClick={() => {
                    downloadTable(tableDropdown.table, 'csv');
                    setTableDropdown(null);
                  }}
                  type="button"
                >
                  CSV
                </button>
                <button
                  className={tableDropdownButtonClassName}
                  onClick={() => {
                    downloadTable(tableDropdown.table, 'markdown');
                    setTableDropdown(null);
                  }}
                  type="button"
                >
                  Markdown
                </button>
              </>
            )}
          </div>
        </div>,
        document.body
      )
    : null;

  return (
    <div onClickCapture={handleTableActionCapture} ref={rootRef}>
      <Streamdown
        {...props}
        isAnimating={!!animated}
        animated={animatedProps}
        plugins={plugins}
        components={components}
        rehypePlugins={rehypePlugins as StreamdownProps['rehypePlugins']}
      />
      {dropdownMenu}
    </div>
  );
};
