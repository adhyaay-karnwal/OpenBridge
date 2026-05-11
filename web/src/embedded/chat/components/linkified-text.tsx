import type { HTMLAttributes } from 'react';
import { useMemo } from 'react';
import { Link } from './link';

// Regex pattern to match URLs
// Matches http://, https://, and www. prefixed URLs
const URL_REGEX =
  /(?:https?:\/\/|www\.)[^\s<>"{}|\\^`[\]]+(?:\([^\s<>"{}|\\^`[\]]*\)|[^\s<>"{}|\\^`[\].,;:!?'")\]])/gi;

interface LinkifiedTextProps extends HTMLAttributes<HTMLSpanElement> {
  /** The text content that may contain URLs */
  text: string;
  /** Optional className for the link elements */
  linkClassName?: string;
}

interface TextPart {
  type: 'text' | 'link';
  content: string;
  href?: string;
}

/**
 * Parses text and extracts URLs, returning an array of text and link parts
 */
function parseTextWithLinks(text: string): TextPart[] {
  const parts: TextPart[] = [];
  let lastIndex = 0;

  // Reset regex state
  URL_REGEX.lastIndex = 0;

  let match: RegExpExecArray | null;
  while ((match = URL_REGEX.exec(text)) !== null) {
    // Add text before the URL
    if (match.index > lastIndex) {
      parts.push({
        type: 'text',
        content: text.slice(lastIndex, match.index),
      });
    }

    // Add the URL
    const url = match[0];
    const href = url.startsWith('www.') ? `https://${url}` : url;
    parts.push({
      type: 'link',
      content: url,
      href,
    });

    lastIndex = match.index + url.length;
  }

  // Add remaining text after last URL
  if (lastIndex < text.length) {
    parts.push({
      type: 'text',
      content: text.slice(lastIndex),
    });
  }

  return parts;
}

/**
 * A component that renders text with URLs converted to clickable links.
 *
 * @example
 * <LinkifiedText text="Check out https://example.com for more info" />
 */
export const LinkifiedText = ({
  text,
  linkClassName,
  ...props
}: LinkifiedTextProps) => {
  const parts = useMemo(() => parseTextWithLinks(text), [text]);

  // If no links found, return plain text
  if (parts.length === 1 && parts[0].type === 'text') {
    return <span {...props}>{text}</span>;
  }

  return (
    <span {...props}>
      {parts.map((part, index) => {
        if (part.type === 'link') {
          return (
            <Link
              key={index.toString()}
              href={part.href}
              className={linkClassName}
            >
              {part.content}
            </Link>
          );
        }
        return <span key={index.toString()}>{part.content}</span>;
      })}
    </span>
  );
};
