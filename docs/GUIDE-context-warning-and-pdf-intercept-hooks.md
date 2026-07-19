# Integrating Context-Size Warning + PDF/Doc Intercept Hooks

Both are Claude Code **hooks** configured in `settings.json`. They fire on different hook events and each runs a small Python script — no LLM calls, near-zero token cost.

## Source Tips (verbatim)

These token-optimization tips prompted this guide. Verbatim, followed by our status.

> There are lots of things you can do. Honestly claude itself taught me all the tricks so just start asking it (next reset). Some quick ones:
>
> - start fresh sessions constantly. Every time you do a different task, even if its closely related, start a new conversation.
> - make a /handoff skill to support point 1. You can also make a hook that reminds you in chat when context is getting big.
> - use Haiku (cheaper) for non-reasoning tasks. Greps, orienting to a file or job, big reads, etc. Use sonnet or higher for planning.
> - create hooks that use Python to read/grep for you programatically and give claude a summary. Massive reduction in tokens.
> - install Caveman (set to highest setting) and use Graphify/Obsidian as a map so claude spends less time searching.
> - stay within the cache time. If you leave your computer for 45+ minutes, dont continue a conversation. Start a new one.
> - spend time optimising what loads in to every conversation. Skills, mcp, tools, your claude md and other mds. Check whats being put in and ask how to minimise it for your use case.
> - dont upload pdfs and docs when you can help it. Create a hook that intercepts them and gets Python to extract it first. Only plain text should be given to claude to minimise tool use etc.
> - set up an automated system that starts your claude window at certain times (mine goes at 5:30am). When I start work at 9 I can go nuts for an hour and I get a reset at 10:30. This does probably increase weekly limit spend.

### Tip status

| Tip | Status |
|---|---|
| Fresh sessions constantly | Habit — no artifact |
| /handoff skill + context-size hook | `/handoff-update` exists; **context-size hook documented below** |
| Haiku for non-reasoning tasks | Covered by `/modrouter` |
| Python read/grep hooks -> summary | Related, not built |
| Caveman highest + Obsidian map | Caveman active; vault exists |
| Cache-time 45min rule | Habit |
| Optimize what loads per conversation | Open task |
| PDF/doc intercept hook | **Documented below** |
| Auto-start session at set time | Open task (cron / `/schedule`) |

## 1. Context-Size Warning Hook

**Problem:** Claude Code has no native "context getting big" ping. The hook must estimate size itself.

**Mechanism:** A `PostToolUse` hook (fires after every tool call) or a `UserPromptSubmit` hook (fires each user turn). The script reads the current session transcript JSONL, sums approximate tokens, and warns when over a threshold.

**Flow:**
1. Hook fires. It receives the session transcript path via the hook stdin JSON (`transcript_path` / `$CLAUDE_TRANSCRIPT_PATH`).
2. Python reads the JSONL, estimates tokens (`chars / 4` cheap, or `tiktoken` for exact).
3. If over threshold (e.g. 100k, matching Gate 15), it prints a warning to stdout. Hook stdout is injected into the chat as context.
4. Claude sees: `⚠️ Context ~120k tokens. Consider /compact or a fresh session.`

**Cost:** near-zero. Reads a file, counts, prints. No model call.

**Gotcha:** Don't warn on *every* `PostToolUse` — noisy. Debounce: warn once per N calls or only above threshold, storing last-warned state in a temp file.

## 2. PDF/Doc Intercept Hook

**Problem:** Feeding a PDF/docx to Claude burns huge tokens and causes tool churn. Extract plain text with Python first.

**Mechanism:** A `PreToolUse` hook matched on the `Read` tool. It inspects `file_path`. If the extension is `.pdf/.docx/.pptx/.xlsx`:
1. **Block** the raw Read (hook returns deny / exit code 2).
2. Extract text via Python (`markitdown`, `pypdf`, `pdfplumber`, `python-docx`).
3. Write the extracted `.txt`/`.md` to the scratchpad.
4. Return a message telling Claude to read the extracted file instead.

**Flow:**
```
Read(foo.pdf)
  -> PreToolUse hook fires
  -> sees .pdf
  -> deny + run extractor
  -> returns "extracted to /scratch/foo.md, read that instead"
  -> Claude reads plain text (cheap)
```

**Best extractor:** Microsoft `markitdown` converts PDF/docx/pptx/xlsx to clean markdown in one tool. Fall back to `pdfplumber` for table-heavy PDFs.

**Gotcha:** The hook must be fast — extraction synchronously blocks the tool. Big PDFs are slow. Mitigate by caching extraction on file hash and skipping when the `.txt` already exists.

## Scope: Which File Types

The PDF/doc intercept is **not** "catch any binary." It is an allowlist by extension, split into two categories:

**1. Extractable docs** — hook extracts to text:
- `.pdf .docx .pptx .xlsx` (markitdown covers all)
- easily extend: `.epub .rtf .odt .csv .html`
- markitdown can also OCR images and transcribe audio if desired

**2. Real binaries** — no text inside, different handling:
- images (`.png .jpg`) — Claude reads these natively as vision; do **not** intercept.
- `.zip .tar .exe .so .bin .db` — no meaningful text. Hook should **block + warn** ("binary, skipped"), not extract.

```python
EXTRACT = {".pdf", ".docx", ".pptx", ".xlsx", ".epub", ".rtf", ".odt", ".csv", ".html", ".htm"}
NATIVE  = {".png", ".jpg", ".jpeg", ".gif", ".webp"}   # let Read handle (vision)
# everything else binary -> block with "no text extractor"
```

Note: this is a different layer from the global pre-commit check 1f, which blocks *committing* binaries. This hook governs *reading* documents into context cheaply.

## Placement
Both live in the same `settings.json` `hooks` block, as two separate scripts:
- Context warning: `PostToolUse` (or `UserPromptSubmit`).
- PDF intercept: `PreToolUse` matched on `Read`.
