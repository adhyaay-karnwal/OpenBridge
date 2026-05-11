import { describe, expect, it } from 'vitest';
import {
  createToolCallStatusContent,
  describeToolCallSummary,
  getToolCallDisplayName,
  getToolDisplayName,
  tryParseToolCallStatusPayload,
} from '../src/utils/tool-call-status';

function makeArgs(value: unknown): string {
  return JSON.stringify(value);
}

describe('tool call summaries', () => {
  it('formats summaries for all local agent tool types', () => {
    const cases = [
      {
        toolName: 'Read',
        argumentsText: makeArgs({
          path: '/tmp/file.txt',
          environment: 'cloud-vm',
        }),
        expected: 'Read /tmp/file.txt in a safe workspace on this Mac',
      },
      {
        toolName: 'Write',
        argumentsText: makeArgs({ path: '/tmp/file.txt' }),
        expected: 'Write /tmp/file.txt',
      },
      {
        toolName: 'Edit',
        argumentsText: makeArgs({ path: '/tmp/file.txt' }),
        expected: 'Edit /tmp/file.txt',
      },
      {
        toolName: 'Delete',
        argumentsText: makeArgs({ path: '/tmp/build', recursive: true }),
        expected: 'Delete recursively /tmp/build',
      },
      {
        toolName: 'Stat',
        argumentsText: makeArgs({ path: '/tmp/file.txt' }),
        expected: 'Inspect /tmp/file.txt',
      },
      {
        toolName: 'List',
        argumentsText: makeArgs({ path: '/workspace', recursive: true }),
        expected: 'List recursively /workspace',
      },
      {
        toolName: 'Glob',
        argumentsText: makeArgs({ pattern: '**/*.go', path: '/src' }),
        expected: 'Find "**/*.go" in /src',
      },
      {
        toolName: 'Grep',
        argumentsText: makeArgs({
          pattern: 'TODO',
          path: '/src',
          environment: 'cloud-vm',
        }),
        expected: 'Search /src in a safe workspace on this Mac for "TODO"',
      },
      {
        toolName: 'Copy',
        argumentsText: makeArgs({
          src_path: '/tmp/a.txt',
          src_environment: 'cloud-vm',
          dst_path: '/tmp/b.txt',
        }),
        expected:
          'Copy /tmp/a.txt in a safe workspace on this Mac to /tmp/b.txt',
      },
      {
        toolName: 'JavaScript',
        argumentsText: makeArgs({ code: '1 + 1' }),
        expected: 'Run JavaScript',
      },
      {
        toolName: 'Exec',
        argumentsText: makeArgs({
          environment: 'cloud-vm',
          description: 'run tests',
          command: 'npm test',
        }),
        expected: 'Run "run tests" in a safe workspace on this Mac',
      },
      {
        toolName: 'RequestPermission',
        argumentsText: makeArgs({
          environment: 'local-09a0fdaf15d0',
          description: 'install dependency',
        }),
        expected: 'Request permission for "install dependency" on this Mac',
      },
      {
        toolName: 'Exec',
        argumentsText: makeArgs({
          environment: 'local-vm-43b43e03b6ac',
          description: 'render preview',
          command: 'npm run render',
        }),
        expected: 'Run "render preview" in a safe workspace on this Mac',
      },
      {
        toolName: 'wait_for',
        argumentsText: makeArgs({
          reason: 'deployment result',
          timeout_seconds: 90,
        }),
        expected: 'Wait 1m 30s for "deployment result"',
      },
      {
        toolName: 'ExaSearch',
        argumentsText: makeArgs({ query: 'latest openbridge release' }),
        expected: 'Search web for "latest openbridge release"',
      },
      {
        toolName: 'ExaContents',
        argumentsText: makeArgs({
          urls: ['https://docs.example.com/a', 'https://docs.example.com/b'],
        }),
        expected: 'Fetch 2 web pages',
      },
      {
        toolName: 'WebBrowse',
        argumentsText: makeArgs({
          url: 'https://docs.example.com/local-agent',
          goal: 'read setup notes',
        }),
        expected: 'Browse docs.example.com for "read setup notes"',
      },
      {
        toolName: 'cancel_operation',
        argumentsText: makeArgs({
          operation_id: '019d339d-358b-750c-a1ad-29d044444707',
        }),
        expected: 'Cancel operation 019d339d-358',
      },
      {
        toolName: 'ListEnvironments',
        argumentsText: makeArgs({}),
        expected: 'List environments',
      },
      {
        toolName: 'manage_task',
        argumentsText: makeArgs({ action: 'start', title: 'Wire tool UI' }),
        expected: 'Writing todo list for Wire tool UI',
      },
      {
        toolName: 'manage_schedule',
        argumentsText: makeArgs({ action: 'pause', schedule_id: 'sched_123' }),
        expected: 'Pause schedule sched_123',
      },
    ];

    for (const testCase of cases) {
      expect(
        describeToolCallSummary({
          toolName: testCase.toolName,
          argumentsText: testCase.argumentsText,
        })
      ).toBe(testCase.expected);
    }
  });

  it('stores raw arguments inside tool status payloads', () => {
    const payload = tryParseToolCallStatusPayload(
      createToolCallStatusContent({
        toolName: 'Exec',
        argumentsText: makeArgs({
          environment: 'cloud-vm',
          description: 'check logs',
          command: 'tail -n 200 /var/log/app.log',
        }),
        status: 'completed',
      })
    );

    expect(payload).toMatchObject({
      tool_name: 'Exec',
      arguments: makeArgs({
        environment: 'cloud-vm',
        description: 'check logs',
        command: 'tail -n 200 /var/log/app.log',
      }),
      command: 'tail -n 200 /var/log/app.log',
      status: 'completed',
      completed: true,
    });
  });

  it('uses human-readable todo list labels for task manager tool calls', () => {
    expect(getToolDisplayName('manage_task')).toBe('Todo List');
    expect(
      getToolCallDisplayName({
        toolName: 'manage_task',
        argumentsText: makeArgs({ action: 'start', title: 'Audit sandbox' }),
        status: 'running',
      })
    ).toBe('Writing todo list for Audit sandbox');
    expect(
      getToolCallDisplayName({
        toolName: 'manage_task',
        argumentsText: makeArgs({ action: 'update', title: 'Audit sandbox' }),
        status: 'completed',
      })
    ).toBe('Updated todo list for Audit sandbox');
  });
});
