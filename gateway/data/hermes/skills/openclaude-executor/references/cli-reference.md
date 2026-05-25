# OpenClaude CLI Reference (v0.13.0)

Captured from `openclaude --help` on 2026-05-23.

```
Usage: openclaude [options] [command] [prompt]

OpenClaude - starts an interactive session by default, use -p/--print for non-interactive output

Arguments:
  prompt                                            Your prompt

Options:
  --add-dir <directories...>                        Additional directories to allow tool access to
  --agent <agent>                                   Agent for the current session. Overrides the 'agent' setting.
  --agents <json>                                   JSON object defining custom agents
  --allow-dangerously-skip-permissions              Enable bypassing all permission checks as an option
  --allowedTools, --allowed-tools <tools...>        Comma or space-separated list of tool names to allow
  --append-system-prompt <prompt>                   Append a system prompt to the default system prompt
  --bare                                            Minimal mode: skip hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, keychain reads, and CLAUDE.md auto-discovery
  --betas <betas...>                                Beta headers to include in API requests (API key users only)
  --chrome                                          Enable Claude in Chrome integration
  -c, --continue                                    Continue the most recent conversation in the current directory
  --dangerously-skip-permissions                    Bypass all permission checks
  -d, --debug [filter]                              Enable debug mode with optional category filtering
  --debug-file <path>                               Write debug logs to a specific file path
  --disable-slash-commands                          Disable all skills
  --disallowedTools, --disallowed-tools <tools...>  Comma or space-separated list of tool names to deny
  --effort <level>                                  Effort level (low, medium, high, max)
  --fallback-model <model>                          Enable automatic fallback (only works with --print)
  --file <specs...>                                 File resources to download at startup
  --fork-session                                    When resuming, create a new session ID
  --from-pr [value]                                 Resume a session linked to a PR by number/URL
  -h, --help                                        Display help for command
  --ide                                             Automatically connect to IDE on startup
  --include-hook-events                             Include all hook lifecycle events in the output stream (only with --output-format=stream-json)
  --include-partial-messages                        Include partial message chunks as they arrive (only with --print and --output-format=stream-json)
  --input-format <format>                           Input format: "text" (default), or "stream-json"
  --json-schema <schema>                            JSON Schema for structured output validation
  --max-budget-usd <amount>                         Maximum dollar amount to spend on API calls (only works with --print)
  --mcp-config <configs...>                         Load MCP servers from JSON files or strings
  --mcp-debug                                       [DEPRECATED. Use --debug instead]
  --model <model>                                   Model for the current session
  -n, --name <name>                                 Set a display name for this session
  --no-chrome                                       Disable Claude in Chrome integration
  --no-session-persistence                          Disable session persistence (only works with --print)
  --output-format <format>                          Output format: "text" (default), "json", or "stream-json"
  --permission-mode <mode>                          Permission mode: acceptEdits, bypassPermissions, default, dontAsk, plan, auto
  --plugin-dir <path>                               Load plugins from a directory for this session only
  -p, --print                                       Print response and exit (non-interactive)
  --provider <provider>                             AI provider to use (anthropic, openai, gemini, github, bedrock, vertex, ollama)
  --replay-user-messages                            Re-emit user messages from stdin back on stdout for acknowledgment
  -r, --resume [value]                              Resume a conversation by session ID
  --session-id <uuid>                               Use a specific session ID for the conversation
  --setting-sources <sources>                       Comma-separated list of setting sources to load (user, project, local)
  --settings <file-or-json>                         Path to a settings JSON file or a JSON string
  --strict-mcp-config                               Only use MCP servers from --mcp-config
  --system-prompt <prompt>                          System prompt to use for the session
  --tmux                                            Create a tmux session for the worktree (requires --worktree)
  --tools <tools...>                                Specify the list of available tools from the built-in set
  --verbose                                         Override verbose mode setting from config
  -v, --version                                     Output the version number
  -w, --worktree [name]                             Create a new git worktree for this session

Commands:
  agents                                            List configured agents
  auth                                              Manage authentication
  auto-mode                                         Inspect auto mode classifier configuration
  doctor                                            Check the health of your OpenClaude auto-updater
  install [options] [target]                        Install OpenClaude native build
  mcp                                               Configure and manage MCP servers
  plugin|plugins                                    Manage OpenClaude plugins
  setup-token                                       Set up a long-lived authentication token
  update|upgrade                                    Check for updates and install if available
```

## Provider ↔ Environment Variables

| Provider | Flag | Env Var |
|----------|------|---------|
| Anthropic | `--provider anthropic` | `ANTHROPIC_API_KEY` |
| OpenAI | `--provider openai` | `OPENAI_API_KEY` |
| Google Gemini | `--provider gemini` | `GEMINI_API_KEY` |
| GitHub Models | `--provider github` | `GITHUB_TOKEN` |
| AWS Bedrock | `--provider bedrock` | AWS credentials |
| GCP Vertex | `--provider vertex` | GCP credentials |
| Ollama | `--provider ollama` | local runtime |

## Default Model

Provider `anthropic`, model `claude-sonnet-4-6` — shown at startup.
