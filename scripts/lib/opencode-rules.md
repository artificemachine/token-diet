## token-diet stack (Serena + ICM + Context7)

Serena = LSP symbol navigation MCP server (definitions, references, renames).
ICM = persistent cross-tool memory MCP server (recall past decisions, store facts).
Context7 = up-to-date library documentation MCP server (docs, not guesses).

**Reading and searching code:**

- Use Serena's symbol tools for navigation: definitions, references, symbol overviews,
  and symbol-level edits. It is LSP-backed, so it answers precision questions that
  text search cannot (find-references across modules, type hierarchy, renames).
- Fall back to your built-in Read/Grep/Glob for prose, configuration, and small edits —
  Serena earns its cost on symbol work, not on reading a config file.
- Do not re-read a file you have already read in this session; recall the content instead.

**Persistent memory:**

- Use ICM to recall past decisions, prior context, and stored facts across sessions
  instead of re-deriving them.
- Store durable facts (architecture decisions, conventions, gotchas) in ICM so future
  sessions can recall them rather than re-reading whole files.

**Library documentation:**

- When unsure about a library or framework API, query Context7 instead of guessing.
  It resolves the library and returns current docs, which prevents hallucinated APIs.
- Prefer Context7 over web search for library usage questions.

**Shell commands:**

- Run shell commands normally; there is no output-rewriting proxy in this stack.

**Budget discipline:**

- Prefer structured tool output over raw `cat`-style reads.
- Use Serena's symbol overview when you only need one function or class.
- Avoid recursive directory listings when a glob would do.
