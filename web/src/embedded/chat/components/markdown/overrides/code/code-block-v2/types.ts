// Re-export types from @streamdown/code for consistency
export type { HighlightResult, HighlightOptions } from '@streamdown/code';

/**
 * A single token in a highlighted line
 * This is a simplified type for internal use, compatible with shiki's TokensResult
 */
export interface HighlightToken {
  content: string;
  color?: string;
  bgColor?: string;
  htmlStyle?: Record<string, string>;
  htmlAttrs?: Record<string, string>;
  offset?: number;
}
