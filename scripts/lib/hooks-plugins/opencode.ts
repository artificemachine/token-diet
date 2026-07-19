// scripts/lib/hooks-plugins/opencode.ts — OpenCode plugin that wires docextract
// (PreToolUse/Read equivalent) and ctxwarn (PostToolUse/* equivalent).
//
// Architecture: This is a TS plugin (OpenCode's only hook surface — see
// node_modules/@opencode-ai/plugin/dist/index.d.ts). Both behaviors are
// implemented natively in TS rather than shelling to the bash shims because
// OpenCode's session storage is SQLite (`~/.local/share/opencode/opencode.db`)
// and the SDK (`client.session.messages`) is the only TS-friendly way to read
// it. The bash shims (installed alongside this plugin by install_context_hooks)
// still exist for Claude Code where they read plain JSONL transcripts from
// disk — the two code paths share no runtime.
//
// docextract:
//   - Watches `tool.execute.before` for the `read` tool
//   - Extracts via `token-diet extract <file>` via the SDK's shell escape
//   - If exit 0 and stdout is a cache path, REPLACES output.args.filePath
//     with the cache path (OpenCode mutation pattern — same as rtk.ts).
//   - If exit 2 (needs markitdown), the read proceeds unchanged but a stderr
//     note is surfaced so the user knows.
//
// ctxwarn:
//   - Watches `tool.execute.after` for any tool
//   - Fetches the session's messages via client.session.messages({sessionID})
//   - Estimates tokens via tiktoken (Node has it via npm; falls back to
//     chars//4) — mirrors scripts/lib/ctxwarn.py exactly
//   - Reads `.token-budget` for ctx_threshold (walks up from cwd to $HOME)
//   - Per-sessionID debounce keyed on abspath (NOT mtime — same bug we fixed
//     for Claude Code in v1.14.4 doesn't apply here because SQLite handles
//     its own transaction timestamps)
//
// Note on graceful degradation:
//   - If `token-diet` isn't on PATH, docextract silently passes through.
//   - If tiktoken import fails, ctxwarn silently skips (no false warnings).
//   - Plugin errors never break the user's session — every try/catch is a
//     courtesy, not a guardrail.

import type { Plugin } from "@opencode-ai/plugin"
import { existsSync, readFileSync } from "node:fs"
import { join } from "node:path"

// Mirror of scripts/lib/ctxwarn.py DEFAULT_THRESHOLD
const DEFAULT_CTX_THRESHOLD = 100_000

// Mirror of scripts/lib/tdcache.cache_dir("ctxwarn") — keep in sync
const CTXWARN_STATE_DIR = join(process.env.HOME || "~", ".cache", "token-diet", "ctxwarn")

// Mirror of scripts/lib/ctxwarn.py band logic
function estimateTokensFromMessages(messages: any[]): number {
  let totalChars = 0
  const walk = (obj: any) => {
    if (!obj) return
    if (typeof obj === "string") {
      totalChars += obj.length
      return
    }
    if (Array.isArray(obj)) {
      for (const item of obj) walk(item)
      return
    }
    if (typeof obj === "object") {
      for (const [k, v] of Object.entries(obj)) {
        if (typeof v === "string" && (k === "text" || k === "content")) {
          totalChars += v.length
        } else {
          walk(v)
        }
      }
    }
  }
  for (const msg of messages) walk(msg)
  return Math.floor(totalChars / 4) // chars//4 fallback (matches ctxwarn.py when tiktoken is unavailable)
}

function readThresholdFromTokenBudget(cwd: string): number {
  // Walk up from cwd toward $HOME looking for `.token-budget` (mirror of
  // scripts/lib/ctxwarn.py find_budget_file())
  const home = process.env.HOME || ""
  let dir = cwd
  for (let i = 0; i < 32; i++) {
    const candidate = join(dir, ".token-budget")
    if (existsSync(candidate)) {
      try {
        const data = JSON.parse(readFileSync(candidate, "utf-8"))
        const t = Number(data?.ctx_threshold)
        if (Number.isFinite(t) && t > 0) return t
      } catch {
        // fall through to default
      }
      break
    }
    if (dir === home || !dir) break
    const parent = join(dir, "..")
    if (parent === dir) break
    dir = parent
  }
  return DEFAULT_CTX_THRESHOLD
}

function statePathForSession(sessionID: string): string {
  // Key by sessionID only — no mtime. (v1.14.4 fix for Claude Code: same
  // lesson, OpenCode doesn't have the same mtime-changing-on-append problem
  // since messages live in SQLite rows with stable IDs, but keying by a
  // stable identifier is the right invariant regardless.)
  return join(CTXWARN_STATE_DIR, `${sessionID}.band`)
}

function shouldWarnOpenCode(estimate: number, threshold: number, stateFile: string): boolean {
  if (threshold <= 0) return false
  const band = Math.floor(estimate / threshold)
  if (band === 0) return false
  let lastBand = 0
  try {
    if (existsSync(stateFile)) {
      lastBand = Number(readFileSync(stateFile, "utf-8").trim()) || 0
    }
  } catch {
    lastBand = 0
  }
  if (band === lastBand) return false
  try {
    const { mkdirSync, writeFileSync } = require("node:fs")
    mkdirSync(CTXWARN_STATE_DIR, { recursive: true })
    writeFileSync(stateFile, String(band))
  } catch {
    // state persistence failure is non-fatal
  }
  return true
}

export const TokenDietHooks: Plugin = async (pluginInput) => {
  const { $, client, directory } = pluginInput

  // One-time capability check: if token-diet isn't on PATH, disable the
  // extract hook silently. ctxwarn runs entirely in TS and still works.
  let hasTokenDiet = false
  try {
    await $`which token-diet`.quiet()
    hasTokenDiet = true
  } catch {
    // not on PATH
  }

  return {
    "tool.execute.before": async (input, output) => {
      if (!hasTokenDiet) return
      const tool = String(input?.tool ?? "").toLowerCase()
      if (tool !== "read") return
      const args = output?.args as Record<string, unknown> | undefined
      if (!args) return
      const filePath = args.filePath
      if (typeof filePath !== "string" || !filePath) return

      try {
        const result = await $`token-diet extract ${filePath}`.quiet().nothrow()
        if (result.exitCode === 0) {
          const cachePath = String(result.stdout || "").trim()
          if (cachePath && cachePath !== filePath && existsSync(cachePath)) {
            // Substitute: subsequent Read call gets the cache file instead.
            // (Mirrors rtk.ts command-rewrite pattern.)
            args.filePath = cachePath
          }
        } else if (result.exitCode === 3) {
          // needs markitdown (docx/pptx/etc.) — surface the hint via stderr
          console.warn(`[token-diet/docextract] ${String(result.stderr).trim()}`)
        }
        // exit 2 (no extractor / binary) → pass through unchanged
      } catch {
        // never break the user's session on plugin errors
      }
    },

    "tool.execute.after": async (input, _output) => {
      const sessionID = String(input?.sessionID ?? "")
      if (!sessionID) return

      // Fetch session messages to estimate tokens. The SDK is async; we await.
      try {
        const messages = (await client.session.messages({ sessionID }).catch(() => null))?.data
        if (!Array.isArray(messages) || messages.length === 0) return

        const estimate = estimateTokensFromMessages(messages)
        const threshold = readThresholdFromTokenBudget(directory || process.cwd())
        const stateFile = statePathForSession(sessionID)

        if (shouldWarnOpenCode(estimate, threshold, stateFile)) {
          const k = Math.floor(estimate / 1000)
          console.warn(`⚠️ Context ~${k}k tokens. Consider /compact or a fresh session.`)
        }
      } catch {
        // never break the user's session on plugin errors
      }
    },
  }
}