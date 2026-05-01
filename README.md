# agent-router

Headless installer and local relay for configuring Claude Code with MiniMax or DeepSeek's Anthropic-compatible API.

Codalane is intended for Linux servers and other terminal-only environments where using a desktop provider switcher is inconvenient. It installs or detects Claude Code, asks the user for their own provider API key and model choice, and writes the Claude Code settings needed to use the selected provider.

This project is not affiliated with Anthropic, MiniMax, DeepSeek, or CC Switch.

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
- If `npm` is not found, automatically installs Node.js under `~/.local/share/codalane-node` and links `node`, `npm`, and `npx` into `~/.local/bin` (no sudo required).
- Lets the user choose the upstream provider:
  - MiniMax
  - DeepSeek V4
- For MiniMax, lets the user choose the endpoint:
  - China mainland: `https://api.minimaxi.com/anthropic`
  - International: `https://api.minimax.io/anthropic`
- For DeepSeek V4, defaults to `https://api.deepseek.com/anthropic`, primary/Sonnet/Opus model `deepseek-v4-pro[1m]`, Haiku/subagent model `deepseek-v4-flash`, and `CLAUDE_CODE_EFFORT_LEVEL=max`.
- Lets the user enter their own provider API key.
- Lets the user choose model names from numbered MiniMax and DeepSeek menus, while still allowing custom model names.
- Writes Claude Code environment settings to `~/.claude/settings.json`.
- Installs a terminal switcher at `~/.local/bin/ccr` for changing provider/model later. It is also available as `cc-router`, `codalane`, and `codalane-switch`.
- Optionally installs a local `127.0.0.1` relay for users who want a CC Switch-like proxy flow.
- In local proxy mode, DeepSeek uses `x-api-key` authentication while MiniMax keeps `Authorization: Bearer`.

## Switch Provider or Model

After installation, run:

```bash
~/.local/bin/ccr
```

Use `ccr` directly if `~/.local/bin` is already on your `PATH`. The switcher shows the current Claude Code provider/model, then lets you change between MiniMax and DeepSeek V4. If you keep the same provider, you can leave the API key prompt empty to reuse the stored key. If local proxy mode is active, the switcher updates `proxy.env` and restarts the user service when it is running.

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
export CODALANE_NODE_MIRROR=https://npmmirror.com/mirrors/node
```

## Security

Codalane does not ship with any API key. Users must provide their own provider API key during installation.

If local relay mode is enabled, the relay listens on `127.0.0.1` only. Do not expose it to the public internet.

Do not commit generated files such as:

- `~/.claude/settings.json`
- `proxy.env`
- `.env`
- logs containing prompts, responses, or credentials

## License

Codalane is source-available under the PolyForm Noncommercial License 1.0.0.

Non-commercial use is permitted. Commercial use requires a separate written license from the copyright holder. See [COMMERCIAL.md](COMMERCIAL.md).

This is not an OSI-approved open source license.
