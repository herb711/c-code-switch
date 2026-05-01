# agent-router

Headless installer and local relay for configuring Claude Code with MiniMax, DeepSeek, Kimi, or OpenAI-compatible vLLM endpoints.

agent-router is intended for Linux servers and other terminal-only environments where using a desktop provider switcher is inconvenient. It installs or detects Claude Code, asks the user for their own provider API key and model choice, and writes the Claude Code settings needed to use the selected provider.

This project is not affiliated with Anthropic, MiniMax, DeepSeek, Moonshot AI/Kimi, or vLLM.

## Install

Requirements: `curl`. Node.js and npm are installed automatically if missing.

Review the script before running it:

```bash
curl -fsSL https://raw.githubusercontent.com/herb711/agent-router/main/install.sh -o install.sh
less install.sh
bash install.sh
```

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/herb711/agent-router/main/install.sh | bash
```

## What It Does

- Installs Claude Code into `~/.local` with npm if `claude` is not already installed.
- If `npm` is not found, automatically installs Node.js under `~/.local/share/agent-router-node` and links `node`, `npm`, and `npx` into `~/.local/bin` (no sudo required).
- Lets the user choose the upstream provider:
  - MiniMax
  - DeepSeek V4
  - Kimi
  - vLLM (OpenAI-compatible)
- For MiniMax, lets the user choose the endpoint:
  - China mainland: `https://api.minimaxi.com/anthropic`
  - International: `https://api.minimax.io/anthropic`
- For DeepSeek V4, defaults to `https://api.deepseek.com/anthropic`, primary/Sonnet/Opus model `deepseek-v4-pro[1m]`, Haiku/subagent model `deepseek-v4-flash`, and `CLAUDE_CODE_EFFORT_LEVEL=max`.
- For Kimi, defaults to `https://api.moonshot.ai/anthropic`, model `kimi-k2.5`, and `ENABLE_TOOL_SEARCH=false`.
- For vLLM, prompts for an OpenAI-compatible base URL, defaults to local `http://127.0.0.1:8000/v1` when left empty, appends `/v1` if the path is omitted, tries to discover served models from `/models`, asks for a model name when discovery fails, then prompts for the API key. Leaving the vLLM API key empty uses `EMPTY` for local servers.
- Lets the user enter their own provider API key.
- Lets the user choose model names from numbered MiniMax, DeepSeek, and Kimi menus, while vLLM can use discovered `/models` results or a custom model name.
- Writes Claude Code environment settings to `~/.claude/settings.json`.
- Installs a terminal switcher at `~/.local/bin/ccr` for changing provider/model later. It is also available as `agent-router`.
- Optionally installs a local `127.0.0.1` relay at `~/.local/bin/agent-router-proxy` for users who want a proxy flow. vLLM always uses this relay because Claude Code speaks Anthropic Messages API while vLLM serves an OpenAI-compatible API.
- In local proxy mode, DeepSeek uses `x-api-key` authentication while MiniMax and Kimi keep `Authorization: Bearer`.

## Switch Provider or Model

After installation, run:

```bash
~/.local/bin/ccr
```

Use `ccr` directly if `~/.local/bin` is already on your `PATH`. The switcher shows the current Claude Code provider/model, then lets you change between MiniMax, DeepSeek V4, Kimi, and vLLM. If you keep the same provider, you can leave the API key prompt empty to reuse the stored key. If local proxy mode is active, the switcher updates `proxy.env` and restarts the `agent-router-proxy.service` user service when it is running.

## Test

After installation:

```bash
claude -p '只回复 OK'
```

For interactive Claude Code:

```bash
claude
```

If `nodejs.org` is hard to reach from your network, set a Node.js mirror before running the installer:

```bash
export AGENT_ROUTER_NODE_MIRROR=https://npmmirror.com/mirrors/node
```

## Security

agent-router does not ship with any API key. Users must provide their own provider API key during installation.

If local relay mode is enabled, the relay listens on `127.0.0.1` only. Do not expose it to the public internet.

Do not commit generated files such as:

- `~/.claude/settings.json`
- `proxy.env`
- `.env`
- logs containing prompts, responses, or credentials

## License

agent-router is source-available under the PolyForm Noncommercial License 1.0.0.

Non-commercial use is permitted. Commercial use requires a separate written license from the copyright holder. See [COMMERCIAL.md](COMMERCIAL.md).

This is not an OSI-approved open source license.
