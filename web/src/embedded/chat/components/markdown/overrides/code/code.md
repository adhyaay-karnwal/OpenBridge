# Description

Since we need to customize code-block's behavior (e.g. override download logic, replace icon with SF Symbol, limit code block height), should provide a custom CodeBlock Component.

So we fork from the source code of `Streamdown` and modify it directly.

# Structure

- [CodeBlock](https://github.com/vercel/streamdown/blob/main/packages/streamdown/lib/code-block) → [./code-block](./code-block)
- [Mermaid](https://github.com/vercel/streamdown/blob/main/packages/streamdown/lib/mermaid) → [./mermaid](./mermaid)
- [MemoCode](https://github.com/vercel/streamdown/blob/main/packages/streamdown/lib/components.tsx) → [./memo-code](./memo-code.tsx)
