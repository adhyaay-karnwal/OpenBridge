const likelyLocalFilesystemPathPattern =
  /^(?:~\/|file:\/\/|[A-Za-z]:[\\/]|\/(?:\.agent|Users|private|var|tmp|home|Volumes)(?:\/|$))/;

const localAttachmentRoutePrefixes = [
  '/v1/user/agent/files/',
  '/v1/storage/',
] as const;

export interface AttachmentDisplayURLParams {
  src?: string | null;
  filePath?: string | null;
  environmentId?: string | null;
}

export function isLikelyLocalFilesystemPath(value: string): boolean {
  return likelyLocalFilesystemPathPattern.test(value);
}

function isDirectBrowserAttachmentURL(value: string): boolean {
  return (
    value.startsWith('data:') ||
    value.startsWith('blob:') ||
    value.startsWith('http://') ||
    value.startsWith('https://') ||
    value.startsWith('/v1/') ||
    value.startsWith('./') ||
    value.startsWith('../')
  );
}

export function normalizeAgentPath(filePath: string): string {
  const trimmed = filePath.trim().replace(/\\/g, '/');
  if (!trimmed || trimmed === '.') {
    return '/';
  }

  const segments: string[] = [];
  for (const segment of trimmed.split('/')) {
    if (!segment || segment === '.') {
      continue;
    }
    if (segment === '..') {
      segments.pop();
      continue;
    }
    segments.push(segment);
  }

  return segments.length > 0 ? `/${segments.join('/')}` : '/';
}

export function buildAgentFileURL(filePath: string): string {
  return normalizeAgentPath(filePath);
}

export function isVFSLikeEnvironmentId(
  value: string | null | undefined
): boolean {
  const normalized = value?.trim().toLowerCase() ?? '';
  return normalized === '' || normalized === 'vfs';
}

function normalizeLocalAttachmentRoute(value: string): string | null {
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  for (const prefix of localAttachmentRoutePrefixes) {
    if (trimmed.startsWith(prefix)) {
      return trimmed;
    }
  }

  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    return null;
  }

  try {
    const url = new URL(trimmed);
    for (const prefix of localAttachmentRoutePrefixes) {
      if (!url.pathname.startsWith(prefix)) {
        continue;
      }
      return url.search ? `${url.pathname}${url.search}` : url.pathname;
    }
  } catch {
    return null;
  }

  return null;
}

export function requiresNativeURLResolution(value: string): boolean {
  return (
    normalizeLocalAttachmentRoute(value) !== null ||
    isLikelyLocalFilesystemPath(value.trim())
  );
}

export function resolveAttachmentDisplayURL(
  params: AttachmentDisplayURLParams
): string | null {
  const filePath = params.filePath?.trim();
  if (filePath && isVFSLikeEnvironmentId(params.environmentId)) {
    return buildAgentFileURL(filePath);
  }

  return resolveBrowserAttachmentURL({ src: params.src });
}

export function resolveBrowserAttachmentURL(params: {
  src?: string | null;
}): string | null {
  const src = params.src?.trim();

  if (src?.startsWith('data:')) {
    return src;
  }

  const localRoute = src ? normalizeLocalAttachmentRoute(src) : null;
  if (localRoute) {
    return localRoute;
  }

  if (src && isDirectBrowserAttachmentURL(src)) {
    return src;
  }

  if (src && isLikelyLocalFilesystemPath(src)) {
    return src;
  }

  if (src) {
    return src;
  }

  return null;
}
