import { describe, expect, it } from 'vitest';
import {
  isLikelyLocalFilesystemPath,
  requiresNativeURLResolution,
  resolveAttachmentDisplayURL,
  resolveBrowserAttachmentURL,
} from '../src/utils/agent-file-url';

describe('resolveBrowserAttachmentURL', () => {
  it('keeps direct browser URLs intact', () => {
    expect(
      resolveBrowserAttachmentURL({
        src: '/v1/user/agent/files/data/report.pdf',
      })
    ).toBe('/v1/user/agent/files/data/report.pdf');

    expect(
      resolveBrowserAttachmentURL({
        src: 'https://cdn.example.com/file.mp4',
      })
    ).toBe('https://cdn.example.com/file.mp4');

    expect(
      resolveBrowserAttachmentURL({
        src: 'https://local.agent.test/v1/user/agent/files/data/report.pdf',
      })
    ).toBe('/v1/user/agent/files/data/report.pdf');
  });

  it('does not treat the local agent files route as a host filesystem path', () => {
    expect(
      isLikelyLocalFilesystemPath(
        '/v1/user/agent/files/.agent/deliveries/image.png'
      )
    ).toBe(false);
  });

  it('keeps local filesystem sources for native-side resolution', () => {
    expect(
      resolveBrowserAttachmentURL({
        src: '/Users/test/Pictures/local.png',
      })
    ).toBe('/Users/test/Pictures/local.png');
  });

  it('marks local agent file routes for native-side resolution', () => {
    expect(
      requiresNativeURLResolution(
        '/v1/user/agent/files/.agent/deliveries/cat.png'
      )
    ).toBe(true);
    expect(
      requiresNativeURLResolution(
        'https://local.agent.test/v1/user/agent/files/.agent/deliveries/cat.png'
      )
    ).toBe(true);
    expect(requiresNativeURLResolution('/v1/storage/object-123')).toBe(true);
    expect(requiresNativeURLResolution('https://cdn.example.com/cat.png')).toBe(
      false
    );
  });

  it('prefers local file refs for attachment display URLs', () => {
    expect(
      resolveAttachmentDisplayURL({
        src: 'https://local.agent.test/v1/user/agent/files/.agent/deliveries/wrong.png',
        filePath: '/.agent/deliveries/session/call/cat.png',
        environmentId: 'vfs',
      })
    ).toBe('/.agent/deliveries/session/call/cat.png');
  });
});
