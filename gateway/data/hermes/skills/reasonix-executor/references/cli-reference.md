# Reasonix CLI Reference

Captured from `reasonix --help` on 2026-05-23.

```
Usage: reasonix [options] [command]

DeepSeek-native agent framework — built for cache hits and cheap tokens.

Options:
  -V, --version                  output the version number
  -c, --continue                 Resume the most recently used chat session without showing the picker
  -h, --help                     display help for command

Commands:
  setup                          Interactive wizard — API key, preset, MCP servers. Re-run any time to reconfigure.
  code [options] [dir]           Code-editing chat — filesystem tools rooted at <dir> (default: cwd), coding system prompt, v4-flash baseline.
  chat [options]                 Interactive Ink TUI with live cache/cost panel.
  run [options] <task>           Run a single task non-interactively, streaming output.
  acp [options]                  Run reasonix as an Agent Client Protocol (ACP) agent on stdio NDJSON JSON-RPC
  desktop [options]              Headless JSON-RPC chat for the desktop client (internal)
  stats [transcript]             Show usage dashboard.
  doctor [options]               One-command health check.
  commit [options]               Draft a commit message from the staged diff.
  sessions [options] [name]      List saved chat sessions, or inspect one by name.
  prune-sessions [options]       Delete saved sessions idle ≥N days (default 90). Use --dry-run to preview.
  events [options] <name>        Pretty-print the kernel event-log sidecar.
  replay [options] <transcript>  Interactive Ink TUI to scrub through a transcript.
  diff [options] <a> <b>         Compare two transcripts in a split-pane Ink TUI.
  mcp                            Model Context Protocol helpers — discover servers, test your setup.
  version                        Print Reasonix version.
  update [options]               Check for a newer Reasonix and install it.
  index [options]                Build (or incrementally refresh) a local semantic search index.
```

## Key Notes

- **Default model:** DeepSeek v4-flash (baseline)
- **`run` mode** is the non-interactive equivalent of OpenClaude's `-p` / `--print`
- **`code [dir]`** adds filesystem tool access rooted at the directory
- **`chat`** has no filesystem tools — pure conversation
- **`commit`** reads `git diff --staged` to draft commit messages
- **Cost:** 4.35B tokens for < $2 with DeepSeek v4-flash
