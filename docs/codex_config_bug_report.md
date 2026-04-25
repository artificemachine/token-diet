# Bug Report: TOML Syntax Error in `~/.codex/config.toml`

## Status: Resolved
**Date:** April 24, 2026  
**Component:** Codex CLI Configuration  
**Reporter:** Gemini CLI  

---

## 1. Problem Description
When attempting to start the Codex CLI (`codex`), the application failed with a fatal error regarding the configuration file.

### Error Message:
```text
[DANGER] codex FULL permission (Bypassing Sandbox) !!
Error loading config.toml:
~/.codex/config.toml:144:10: unclosed table, expected `]`
    |
144 | ["--from", "git+https://github.com/celstnblacc/serena", "serena", "start-mcp-server", "--context=codex", "--project-from-cwd"]
    |          ^
```

## 2. Root Cause Analysis
The TOML parser encountered array literals at the top level of the configuration file without associated keys. In TOML, square brackets at the start of a line are reserved for **Tables** (e.g., `[table_name]`) or **Arrays of Tables** (e.g., `[[table_name]]`).

The following stray lines were identified as violating the TOML specification:
- **Line 141:** `["--mcp"]`
- **Line 144:** `["--from", "git+https://github.com/celstnblacc/serena", ...]`
- **Line 154:** `["--mcp"]`

These lines appear to have been accidental pastes or remnants of command-line arguments that were incorrectly inserted into the text file, causing the parser to expect a valid table name or closing bracket.

## 3. Resolution Steps

### Step 1: Backup
Created a backup of the existing configuration to prevent data loss:
```bash
cp ~/.codex/config.toml ~/.codex/config.toml.bak
```

### Step 2: Identification
Identified the specific line numbers using `cat -n` and `sed` to verify context.

### Step 3: Rectification
Used `sed` to remove the problematic lines from the configuration file:
```bash
sed -e '141d' -e '144d' -e '154d' ~/.codex/config.toml.bak > ~/.codex/config.toml
```

### Step 4: Verification
Executed the Codex CLI to confirm successful initialization:
```bash
codex --version
# Output: codex-cli 0.121.0
```

## 4. Final Configuration State (Fragment)
The cleaned section of the config now correctly defines the MCP servers without stray arrays:

```toml
[mcp_servers.pencil]
command = "/Applications/Pencil.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-arm64"
args = [ "--app", "desktop" ]

[mcp_servers.tilth.tools.tilth_read]
approval_mode = "approve"

[marketplaces.openai-bundled]
# ...
```

## 5. Recommendations
- **MCP Server Configuration:** If the user intends to add `serena` as an MCP server, use the standard `[mcp_servers.NAME]` format:
  ```toml
  [mcp_servers.serena]
  command = "uvx"
  args = ["--from", "git+https://github.com/celstnblacc/serena", "serena", "start-mcp-server", "--context=codex", "--project-from-cwd"]
  ```
- **Validation:** Always validate TOML syntax after manual edits using a linter or the CLI's own error reporting before committing changes.
