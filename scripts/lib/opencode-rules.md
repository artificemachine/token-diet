## token-diet stack (RTK + tilth + Serena)

RTK = shell command proxy that compresses tool output (60-90% token savings).
tilth = AST-aware code-intel MCP server (replaces grep/cat/find).
Serena = semantic symbol MCP server (symbol-level edits, references).

**Reading and searching code:**
- Use `tilth_read` instead of `cat`/`head`/`tail` — smart outline for large files.
- Use `tilth_search` instead of `grep`/`rg` — returns definitions and usages in one call.
- Use `tilth_files` instead of `find`/`ls` — glob with token counts, respects `.gitignore`.
- Do NOT re-read content already shown inline in a `tilth_search` result.

**Editing code:**
- For symbol-level changes (rename, find-references, replace-body), prefer Serena MCP tools over manual edits.
- If unsure whether a symbol exists, call `tilth_search` first rather than reading whole files.

**Shell commands:**
- RTK wraps shell commands transparently — run them normally, RTK intercepts and compresses output.
- Meta commands: `rtk gain` (RTK savings), `token-diet gain` (combined RTK + tilth + Serena dashboard).

**Budget discipline:**
- Prefer structured tool output over raw `cat`-style reads.
- Use `tilth_read --section` when you only need one function or class.
- Avoid recursive directory listings when a glob would do.
