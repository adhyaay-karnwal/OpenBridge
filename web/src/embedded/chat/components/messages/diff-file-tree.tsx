import {
  useState,
  useEffect,
  useCallback,
  createContext,
  useContext,
  useMemo,
  useRef,
} from 'react';
import { useVirtualizer } from '@tanstack/react-virtual';
import { FolderFillSFSymbolRegular } from '@/assets/sf-symbols/regular/folder.fill';
import { DocumentFillSFSymbolRegular } from '@/assets/sf-symbols/regular/document.fill';
import type { FileDiff } from '../../types/history';
import { TruncateLeft } from '../truncate-left';

type DisplayFileDiff = FileDiff & {
  originalPaths?: string[];
};

// Context for sharing common configuration across the file tree
interface DiffFileTreeContextValue {
  isStreaming: boolean; // Global state: whether content is streaming
  selectedPaths?: Set<string>; // Checkbox selection state (when present, enables diff view mode)
  onSelectionChange?: (paths: Set<string>) => void; // Callback for selection changes
  readOnly: boolean;
  environmentId: string;
}

const DiffFileTreeContext = createContext<DiffFileTreeContextValue | null>(
  null
);

function useDiffFileTreeContext() {
  const context = useContext(DiffFileTreeContext);
  if (!context) {
    throw new Error(
      'useDiffFileTreeContext must be used within DiffFileTreeContext.Provider'
    );
  }
  return context;
}

// Diff file node structure for tree rendering (based on FileDiff)
export interface DiffFileNode {
  // FileDiff fields
  path: string;
  mode: number;
  isDir: boolean;
  isUpdated: boolean;
  isNew: boolean;
  isDeleted: boolean;
  movedFrom?: string;
  timestamp: string;
  size: number;
  originalPaths?: string[];
  // Tree structure
  name: string;
  diff?: DisplayFileDiff;
  exists?: boolean;
  children?: DiffFileNode[];
}

// Collect all paths from a node (recursively for directories)
// Only returns paths for nodes that have a diff (actual diff entries, not synthetic intermediate directories)
function collectAllFilePaths(node: DiffFileNode): string[] {
  const paths: string[] = [];

  // Only include this node's path if it has a diff (not a synthetic intermediate)
  if (node.diff) {
    paths.push(...(node.originalPaths ?? [node.path]));
  }

  // Recursively collect from children
  if (node.isDir && node.children && node.children.length > 0) {
    paths.push(...node.children.flatMap(child => collectAllFilePaths(child)));
  }

  return paths;
}

// Button visibility decision table (pure business logic, no UI state)
interface ButtonVisibilityInput {
  isDir: boolean;
  isDeleted: boolean;
  isUpdated: boolean;
  exists: boolean;
  isDiffView: boolean;
}

interface ButtonVisibilityOutput {
  canPreview: boolean; // Can show Preview button
  canShowFinder: boolean; // Can show "Show in Finder" / "Open" button
}

/**
 * Unified button visibility decision table
 *
 * Rules:
 * 1. Preview: diff view only, non-dir, and (new file OR updated file) - i.e., file exists in workspace
 * 2. Show in Finder: file exists on host (exists=true), or non-deleted in accepted view
 */
function getButtonVisibility(
  input: ButtonVisibilityInput
): ButtonVisibilityOutput {
  const { isDir, isDeleted, isUpdated, exists, isDiffView } = input;

  const isNewOrUpdated = !exists || isUpdated;

  return {
    // Preview: diff view, non-dir, file exists in workspace (new or updated)
    canPreview: isDiffView && !isDir && !isDeleted && isNewOrUpdated,

    // Show in Finder:
    // - In diff view: exists on host
    // - In accepted view: not deleted (file was accepted to host)
    canShowFinder: isDiffView ? exists : !isDeleted,
  };
}

// Collect direct child file paths (non-directory, exists=true) from a folder node
function collectExistingDirectChildFilePaths(node: DiffFileNode): string[] {
  if (!node.isDir || !node.children) return [];
  return node.children
    .filter(child => !child.isDir && child.exists)
    .map(child => child.path);
}

// Open folder in Finder without selecting files
async function openFolder(path: string): Promise<void> {
  try {
    await window.jsb?.MessagesBridge?.openFolder(path);
  } catch (err) {
    console.error('Failed to open folder:', err);
  }
}

// Collapse single-child directory chains
function collapseNode(
  node: DiffFileNode,
  depth: number
): {
  node: DiffFileNode;
  collapsedName: string;
} {
  let currentNode = node;
  // Only preserve leading slash for root nodes (depth === 0)
  const hasLeadingSlash = depth === 0 && node.path.startsWith('/');
  let collapsedName = hasLeadingSlash ? `/${node.name}` : node.name;

  while (
    currentNode.isDir &&
    currentNode.children?.length === 1 &&
    currentNode.children[0].isDir
  ) {
    currentNode = currentNode.children[0];
    collapsedName = `${collapsedName}/${currentNode.name}`;
  }

  return { node: currentNode, collapsedName };
}

// Flattened node for virtual scrolling
interface FlattenedNode {
  node: DiffFileNode;
  depth: number;
  collapsedName: string;
}

// Flatten tree structure for virtual scrolling
function flattenTree(
  nodes: DiffFileNode[],
  depth: number = 0
): FlattenedNode[] {
  const result: FlattenedNode[] = [];

  for (const node of nodes) {
    const { node: collapsedNode, collapsedName } = collapseNode(node, depth);

    result.push({
      node: collapsedNode,
      depth,
      collapsedName,
    });

    if (collapsedNode.children && collapsedNode.children.length > 0) {
      result.push(...flattenTree(collapsedNode.children, depth + 1));
    }
  }

  return result;
}

// Reveal file or folder in Finder
async function revealInFinder(path: string): Promise<void> {
  try {
    await window.jsb?.MessagesBridge?.revealInFinder([path]);
  } catch (err) {
    console.error('Failed to reveal in Finder:', err);
  }
}

// Preview a workspace file (pending accept) in the native preview window
async function previewWorkspaceFile(
  path: string,
  environmentId: string
): Promise<void> {
  try {
    await window.jsb?.MessagesBridge?.previewWorkspaceFile(
      path,
      environmentId,
      null
    );
  } catch (err) {
    console.error('Failed to preview workspace file:', err);
  }
}

// Preview a host file (already accepted) in the native preview window
async function previewHostFile(path: string): Promise<void> {
  try {
    await window.jsb?.MessagesBridge?.previewHostFile(path, null);
  } catch (err) {
    console.error('Failed to preview host file:', err);
  }
}

async function requestFileThumbnail(path: string): Promise<string | null> {
  try {
    const result = await window.jsb?.MessagesBridge?.getFileIcon(path);
    return result ?? null;
  } catch {
    return null;
  }
}

export const DiffFileIcon = ({
  path,
  isDir,
  isExists,
}: {
  path: string;
  isDir: boolean;
  isExists: boolean;
}) => {
  const [iconSrc, setIconSrc] = useState<string | null>(null);

  useEffect(() => {
    if (!isExists || isDir) return;
    let cancelled = false;
    requestFileThumbnail(path).then(src => {
      if (!cancelled) setIconSrc(src);
    });
    return () => {
      cancelled = true;
    };
  }, [path, isExists, isDir]);

  if (iconSrc) {
    return <img src={iconSrc} alt="" className="w-5 h-5 object-contain" />;
  }

  return isDir ? (
    <FolderFillSFSymbolRegular className="text-[13px] text-[#5E9CE5]" />
  ) : (
    <DocumentFillSFSymbolRegular className="text-[16px] text-text-secondary" />
  );
};

export interface DiffFileNodeRendererProps {
  node: DiffFileNode;
  depth: number;
  collapsedName: string;
}

export const DiffFileNodeRenderer = ({
  node,
  depth,
  collapsedName,
}: DiffFileNodeRendererProps) => {
  // Get shared configuration from context
  const { selectedPaths, onSelectionChange, readOnly, environmentId } =
    useDiffFileTreeContext();
  const [isHovered, setIsHovered] = useState(false);
  const currentNode = node;

  // In diff view (selection mode), files are pending workspace changes
  // In accepted view (AcceptedFilesCard), files have been applied to host
  const isDiffView = !readOnly && selectedPaths !== undefined;

  const handleNameClick = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    if (readOnly) {
      if (currentNode.isDeleted) {
        return;
      }
      if (currentNode.isDir) {
        openFolder(currentNode.path);
      } else {
        revealInFinder(currentNode.path);
      }
      return;
    }

    if (currentNode.isDir) {
      revealInFinder(currentNode.path);
    } else if (isDiffView && !currentNode.isDeleted) {
      // In diff view, preview workspace files (pending changes)
      previewWorkspaceFile(currentNode.path, environmentId);
    } else {
      // In accepted view or deleted files: show on host
      previewHostFile(currentNode.path);
    }
  };

  const handleActionClick = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      if (currentNode.isDir) {
        // For folders: reveal existing direct child files, or just open folder
        const filePaths = collectExistingDirectChildFilePaths(currentNode);
        if (filePaths.length > 0) {
          window.jsb?.MessagesBridge?.revealInFinder(filePaths);
        } else {
          openFolder(currentNode.path);
        }
      } else {
        // For files: reveal single file
        revealInFinder(currentNode.path);
      }
    },
    [currentNode]
  );

  // Checkbox selection logic
  const handleCheckboxToggle = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      if (!selectedPaths || !onSelectionChange) return;
      // Get all paths including directory paths (needed for delete operations during apply)
      const allPaths = collectAllFilePaths(currentNode);
      const allSelected = allPaths.every(p => selectedPaths.has(p));
      const next = new Set(selectedPaths);
      for (const p of allPaths) {
        if (allSelected) next.delete(p);
        else next.add(p);
      }
      onSelectionChange(next);
    },
    [currentNode, selectedPaths, onSelectionChange]
  );

  // Checkbox state for this node
  const checkboxState = useMemo(() => {
    if (!selectedPaths) return 'none' as const;
    // Only count paths that have a diff (actual diff entries, not synthetic intermediates)
    const allPaths = collectAllFilePaths(currentNode);
    const selectedCount = allPaths.filter(p => selectedPaths.has(p)).length;
    if (selectedCount === 0) return 'unchecked' as const;
    if (selectedCount === allPaths.length) return 'checked' as const;
    return 'indeterminate' as const;
  }, [currentNode, selectedPaths]);

  // Get button visibility based on current state (business logic only)
  const buttonVisibility = getButtonVisibility({
    isDir: currentNode.isDir,
    isDeleted: currentNode.isDeleted,
    isUpdated: currentNode.isUpdated,
    exists: currentNode.exists ?? false,
    isDiffView,
  });

  // Apply UI interaction states (hover) on top of business logic
  const showPreview = isHovered && buttonVisibility.canPreview && !readOnly;
  const showFinder = isHovered && buttonVisibility.canShowFinder;

  return (
    <div style={{ paddingLeft: `${depth * 6}px` }}>
      <div
        className="flex items-center gap-[2px] select-none h-6 rounded-[4px] hover:bg-fill-soft p-[2px]"
        onMouseEnter={() => setIsHovered(true)}
        onMouseLeave={() => setIsHovered(false)}
      >
        {/* Checkbox (diff view only) */}
        {isDiffView && (
          <div
            role="checkbox"
            aria-checked={
              checkboxState === 'checked'
                ? true
                : checkboxState === 'indeterminate'
                  ? 'mixed'
                  : false
            }
            className="shrink-0 w-4 h-4 flex items-center justify-center cursor-pointer"
            onClick={handleCheckboxToggle}
          >
            <div
              className={`w-3 h-3 rounded-[3px] border transition-colors ${
                checkboxState === 'checked'
                  ? 'bg-[#0077FF] border-[#0077FF]'
                  : checkboxState === 'indeterminate'
                    ? 'bg-[#0077FF]/50 border-[#0077FF]'
                    : 'border-border-strong hover:border-text-secondary'
              }`}
            >
              {checkboxState === 'checked' && (
                <svg
                  viewBox="0 0 12 12"
                  className="w-full h-full text-primary-highlight"
                >
                  <path
                    d="M3 6l2.5 2.5L9 4"
                    stroke="currentColor"
                    strokeWidth="2"
                    fill="none"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              )}
              {checkboxState === 'indeterminate' && (
                <svg
                  viewBox="0 0 12 12"
                  className="w-full h-full text-primary-highlight"
                >
                  <path
                    d="M3 6h6"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                  />
                </svg>
              )}
            </div>
          </div>
        )}

        {/* Folder/File Icon */}
        <div className="shrink-0 w-5 h-5 flex items-center justify-center">
          {!currentNode.exists && currentNode.movedFrom ? (
            <DiffFileIcon
              path={currentNode.movedFrom}
              isDir={currentNode.isDir}
              isExists={true}
            />
          ) : (
            <DiffFileIcon
              path={currentNode.path}
              isDir={currentNode.isDir}
              isExists={currentNode.exists ?? false}
            />
          )}
        </div>

        {/* Name with movedFrom display and Badge */}
        <div className="flex-1 flex items-center min-w-0 ml-[2px] gap-[4px]">
          <span
            className="text-[13px] leading-[19px] cursor-pointer truncate text-text-primary"
            onClick={handleNameClick}
          >
            {currentNode.movedFrom ? (
              <span className="w-full flex">
                <TruncateLeft className="text-text-secondary line-through max-w-[calc(50%-12px)]">
                  {currentNode.movedFrom}
                </TruncateLeft>
                <span className="mx-1 text-text-tertiary inline-block w-3">
                  →
                </span>
                <TruncateLeft className="max-w-[calc(50%-12px)]">
                  {currentNode.name}
                </TruncateLeft>
              </span>
            ) : (
              collapsedName
            )}
          </span>

          {/* Badge - always show based on node state, shrink-0 to stay visible */}
          {currentNode.diff &&
            (!currentNode.isDeleted &&
            !currentNode.movedFrom &&
            !currentNode.isUpdated ? (
              <span className="shrink-0 px-1 rounded-[9px] text-[12px] bg-[#25D083]/20 text-[#25D083] leading-[16px]">
                NEW
              </span>
            ) : currentNode.isDeleted ? (
              <span className="shrink-0 px-1 rounded-[9px] text-[12px] bg-[#FF444D]/20 text-[#FF747B] leading-[16px]">
                DELETED
              </span>
            ) : (
              currentNode.isUpdated && (
                <span className="shrink-0 px-1 rounded-[9px] text-[12px] bg-[#0077FF4D] text-[#419AFF] leading-[16px]">
                  UPDATED
                </span>
              )
            ))}
        </div>

        {/* Preview Button */}
        {showPreview && (
          <button
            className="text-nowrap px-2 py-0.5 rounded-[4px] text-[12px] leading-[16px] border border-border bg-surface-card text-text-primary hover:bg-fill-soft cursor-pointer"
            onClick={handleNameClick}
          >
            Preview
          </button>
        )}

        {/* Show in Finder / Open Button */}
        {showFinder && (
          <button
            className="text-nowrap px-2 py-0.5 rounded-[4px] text-[12px] leading-[16px] border border-border bg-surface-card text-text-primary hover:bg-fill-soft cursor-pointer"
            onClick={handleActionClick}
          >
            {currentNode.isDir ? 'Open' : 'Show in Finder'}
          </button>
        )}
      </div>
    </div>
  );
};

// Create a synthetic directory node (for intermediate directories without diff)
function createSyntheticDir(path: string, name: string): DiffFileNode {
  return {
    path,
    name,
    mode: 0,
    isDir: true,
    isNew: false,
    isUpdated: false,
    isDeleted: false,
    timestamp: new Date(0).toISOString(),
    size: 0,
    children: [],
  };
}

// Create a node from FileDiff
function createNodeFromDiff(
  diff: DisplayFileDiff,
  path: string,
  name: string
): DiffFileNode {
  return {
    ...diff,
    path,
    name,
    diff: diff,
    isNew: !diff.isUpdated && !diff.isDeleted,
    originalPaths: diff.originalPaths,
    children: diff.isDir ? [] : undefined,
  };
}

// Internal node type with Map for O(1) child lookup during tree construction
interface TreeBuildNode {
  node: DiffFileNode;
  childrenMap: Map<string, TreeBuildNode>;
}

// Convert flat FileDiff[] to tree structure DiffFileNode[]
export function convertFileDiffsToTree(diffs: FileDiff[]): DiffFileNode[] {
  if (diffs.length === 0) return [];
  const displayDiffs = aggregateAppBundleDiffs(diffs);

  // Virtual root with Map for O(1) child lookup
  const root: TreeBuildNode = {
    node: createSyntheticDir('', ''),
    childrenMap: new Map(),
  };

  // Insert a diff into the tree, creating intermediate directories as needed
  for (const diff of displayDiffs) {
    const hasLeadingSlash = diff.path.startsWith('/');
    const pathParts = diff.path.split('/').filter(Boolean);
    if (pathParts.length === 0) continue;

    let current = root;

    for (let i = 0; i < pathParts.length; i++) {
      const partName = pathParts[i];
      const isLastPart = i === pathParts.length - 1;

      // O(1) lookup using Map
      let childBuild = current.childrenMap.get(partName);

      if (isLastPart) {
        // Target node (file or directory from diff)
        if (childBuild) {
          // Merge diff properties into existing node
          Object.assign(childBuild.node, {
            ...diff,
            name: partName,
            diff: diff,
            isNew: !diff.isUpdated && !diff.isDeleted,
            originalPaths: diff.originalPaths,
            children: childBuild.node.children || (diff.isDir ? [] : undefined),
          });
        } else {
          // Create new node
          const newNode = createNodeFromDiff(diff, diff.path, partName);
          childBuild = { node: newNode, childrenMap: new Map() };
          current.childrenMap.set(partName, childBuild);
          current.node.children!.push(newNode);
        }
      } else {
        // Intermediate directory
        if (!childBuild) {
          // Build cumulative path for this level
          const partPath =
            (hasLeadingSlash ? '/' : '') + pathParts.slice(0, i + 1).join('/');
          const newNode = createSyntheticDir(partPath, partName);
          childBuild = { node: newNode, childrenMap: new Map() };
          current.childrenMap.set(partName, childBuild);
          current.node.children!.push(newNode);
        }
        current = childBuild;
      }
    }
  }

  return root.node.children || [];
}

function aggregateAppBundleDiffs(diffs: FileDiff[]): DisplayFileDiff[] {
  const passthrough: DisplayFileDiff[] = [];
  const bundles = new Map<string, FileDiff[]>();

  for (const diff of diffs) {
    const bundlePath = appBundleRoot(diff.path);
    if (!bundlePath) {
      passthrough.push(diff);
      continue;
    }
    bundles.set(bundlePath, [...(bundles.get(bundlePath) ?? []), diff]);
  }

  const aggregated = Array.from(bundles.entries()).map(
    ([bundlePath, bundleDiffs]) =>
      aggregateAppBundleDiff(bundlePath, bundleDiffs)
  );

  return [...passthrough, ...aggregated].sort((a, b) =>
    a.path.localeCompare(b.path, undefined, {
      numeric: true,
      sensitivity: 'base',
    })
  );
}

function aggregateAppBundleDiff(
  bundlePath: string,
  diffs: FileDiff[]
): DisplayFileDiff {
  const allDeleted = diffs.every(diff => diff.isDeleted);
  const allMoved = diffs.every(diff => Boolean(diff.movedFrom));
  const allCreated = diffs.every(
    diff => !diff.isDeleted && !diff.isUpdated && !diff.movedFrom
  );
  const movedFrom = allMoved ? commonMovedAppBundleRoot(diffs) : undefined;
  const showAsMoved = Boolean(movedFrom);
  const timestamps = diffs.map(diff => diff.timestamp).sort();
  const newestTimestamp =
    timestamps[timestamps.length - 1] ?? new Date(0).toISOString();

  return {
    path: bundlePath,
    mode: diffs[0]?.mode ?? 0,
    isDir: true,
    isUpdated: !allDeleted && !allCreated && !showAsMoved,
    isDeleted: allDeleted,
    movedFrom,
    timestamp: newestTimestamp,
    size: diffs.reduce((sum, diff) => sum + Math.max(0, diff.size ?? 0), 0),
    originalPaths: Array.from(new Set(diffs.map(diff => diff.path))),
  };
}

function commonMovedAppBundleRoot(diffs: FileDiff[]): string | undefined {
  const roots = diffs
    .map(diff => (diff.movedFrom ? appBundleRoot(diff.movedFrom) : undefined))
    .filter((path): path is string => Boolean(path));
  if (roots.length !== diffs.length) return undefined;
  const first = roots[0];
  return roots.every(root => root === first) ? first : undefined;
}

function appBundleRoot(path: string): string | undefined {
  const hasLeadingSlash = path.startsWith('/');
  const parts = path.split('/').filter(Boolean);
  const appIndex = parts.findIndex(part => part.endsWith('.app'));
  if (appIndex < 0) return undefined;
  const root = parts.slice(0, appIndex + 1).join('/');
  return hasLeadingSlash ? `/${root}` : root;
}

// Hook to check file existence for DiffFileNode
function useDiffFileExistence(nodes: DiffFileNode[]): DiffFileNode[] {
  const [markedNodes, setMarkedNodes] = useState<DiffFileNode[]>(nodes);

  useEffect(() => {
    let cancelled = false;

    const checkExistence = async () => {
      const paths = nodes.flatMap(node => collectAllFilePaths(node));

      if (paths.length === 0) {
        setMarkedNodes(nodes);
        return;
      }

      try {
        const existsMap =
          await window.jsb?.MessagesBridge?.checkFilesExist(paths);

        if (cancelled) return;
        if (existsMap) {
          const markExistence = (nodeList: DiffFileNode[]): DiffFileNode[] => {
            return nodeList.map(node => ({
              ...node,
              exists: node.originalPaths
                ? node.originalPaths.some(path => existsMap[path])
                : (existsMap[node.path] ?? false),
              children: node.children
                ? markExistence(node.children)
                : undefined,
            }));
          };
          const result = markExistence(nodes);
          setMarkedNodes(result);
        } else {
          setMarkedNodes(nodes);
        }
      } catch {
        if (!cancelled) {
          setMarkedNodes(nodes);
        }
      }
    };

    checkExistence();

    return () => {
      cancelled = true;
    };
  }, [nodes]);

  return markedNodes;
}

export interface DiffFileTreeProps {
  diffs: FileDiff[];
  isStreaming?: boolean;
  selectedPaths?: Set<string>;
  onSelectionChange?: (paths: Set<string>) => void;
  maxHeight?: number;
  readOnly?: boolean;
  environmentId?: string;
}

// Row height in pixels (h-6 = 24px)
const ROW_HEIGHT = 24;
// Default max height for virtual scroll container
const DEFAULT_MAX_HEIGHT = 400;

export const DiffFileTree = ({
  diffs,
  isStreaming = false,
  selectedPaths,
  onSelectionChange,
  maxHeight = DEFAULT_MAX_HEIGHT,
  readOnly = false,
  environmentId = '',
}: DiffFileTreeProps) => {
  const parentRef = useRef<HTMLDivElement>(null);

  // Convert FileDiff[] to DiffFileNode[] tree structure (preserves status from input)
  const treeNodes = useMemo(() => {
    const result = convertFileDiffsToTree(diffs);
    return result;
  }, [diffs]);
  const existenceMarkedNodes = useDiffFileExistence(treeNodes);

  // Flatten tree for virtual scrolling
  const flattenedNodes = useMemo(() => {
    const result = flattenTree(existenceMarkedNodes);
    return result;
  }, [existenceMarkedNodes]);

  // Calculate container height: use actual content height if smaller than max
  const contentHeight = flattenedNodes.length * ROW_HEIGHT;
  const containerHeight = Math.min(contentHeight, maxHeight);

  const virtualizer = useVirtualizer({
    count: flattenedNodes.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => ROW_HEIGHT,
    overscan: 5,
  });

  // Create context value with all shared configuration
  const contextValue: DiffFileTreeContextValue = {
    isStreaming,
    selectedPaths,
    onSelectionChange,
    readOnly,
    environmentId,
  };

  return (
    <DiffFileTreeContext.Provider value={contextValue}>
      <div
        ref={parentRef}
        className="overflow-auto"
        style={{ height: containerHeight }}
      >
        <div
          style={{
            height: virtualizer.getTotalSize(),
            width: '100%',
            position: 'relative',
          }}
        >
          {virtualizer.getVirtualItems().map(virtualRow => {
            const { node, depth, collapsedName } =
              flattenedNodes[virtualRow.index];
            return (
              <div
                key={node.path}
                style={{
                  position: 'absolute',
                  top: 0,
                  left: 0,
                  width: '100%',
                  height: ROW_HEIGHT,
                  transform: `translateY(${virtualRow.start}px)`,
                }}
              >
                <DiffFileNodeRenderer
                  node={node}
                  depth={depth}
                  collapsedName={collapsedName}
                />
              </div>
            );
          })}
        </div>
      </div>
    </DiffFileTreeContext.Provider>
  );
};
