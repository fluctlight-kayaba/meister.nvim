# meister — Roadmap

## Vision

Seamless AI integration from Neovim — talk to AI coding agents the same way you
edit code, without leaving the editor. Think opencode.nvim or Avante, but instead
of embedding its own AI, meister is a thin client that drives **existing AI
harnesses** already running on the machine: Claude Code, OpenCode, Codex,
Antigravity, and others. You stay in Neovim; the harness stays the source of
truth for the conversation.

The annotation review loop is the first feature built on this integration layer —
not the whole plugin.

## Architecture

meister is a Neovim-native front-end over pluggable AI harnesses. A provider
abstraction adapts each harness's control surface (send prompt, read status,
stream output) to a common interface Neovim can drive.

| Layer | Module | Role |
|---|---|---|
| Providers | `provider/opencode.lua`, … | one per harness — adapt send/status/control to a common interface |
| Config | `config.lua` | provider selection, send template, highlight options |
| Features | `annotate.lua`, `card.lua`, `input.lua`, `render.lua` | features built on the provider layer (annotation is first) |
| Persistence | `store.lua` | per-feature storage under `<gitdir>/meister/` (annotations today) |
| Entry | `plugin/meister.lua` | commands, keymaps, autocmds |

## Done

**Annotation feature** — the first feature on the integration layer:

- **Input** — inline float, multi-line, auto-grows (min 3), `Enter save · Esc cancel` hint.
- **Persistence** — write-through on add/clear, keyed to repo-relative path in the git dir.
- **Display** — extmark cards (buffer content, not window-scoped), full-width with margin, multi-line, gray theme.
- **Auto-load** — annotations restore on `BufReadPost` and for already-open buffers.
- **Send-back (baseline)** — `:Meister send` collects notes and pushes a formatted prompt to OpenCode.

**Provider layer** — OpenCode adapter (send prompt). Provider interface defined;
adding a harness = implementing one module.

## Next milestone — scoped send to OpenCode

Today `send()` sweeps every *loaded* buffer indiscriminately. Make sending
intentional and complete:

- **Current buffer** — send only the annotations on the buffer under the cursor.
- **All** — send every annotation persisted in the repo (read from `store`, not
  just loaded buffers), so notes on files you haven't opened this session are included.
- Surface both explicitly: `:Meister send` (current) / `:Meister send all`, plus keymaps.
- Confirm/preview count before pushing; keep `clear_after_send` per-scope.

## Later / Backlog

- **More harnesses** — Claude Code, Codex, Antigravity adapters.
- **Conversation surface** — chat/review panel inside Neovim that mirrors the
  active harness session (status, streaming output, history).
- **Diff review** — annotate directly on agent-produced hunks; two-way loop that
  surfaces the harness's response/patch back into the review.
- **Session awareness** — detect which harness is running, route commands to it.
- Multi-agent / per-session note grouping.
