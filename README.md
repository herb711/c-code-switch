# C-Code-Switch

Headless installer and local relay for configuring Claude Code with MiniMax's Anthropic-compatible API.

Codalane is intended for Linux servers and other terminal-only environments where using a desktop provider switcher is inconvenient. It installs or detects Claude Code, asks the user for their own MiniMax API key and model choice, and writes the Claude Code settings needed to use MiniMax.

This project is not affiliated with Anthropic, MiniMax, or CC Switch.

## Install

Requirements: `curl`. Node.js and npm are installed automatically if missing.

Review the script before running it:

```bash
curl -fsSL https://raw.githubusercontent.com/herb711/c-code-switch/main/install.sh -o install.sh
less install.sh
bash install.sh
```

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/herb711/c-code-switch/main/install.sh | bash
```

## What It Does

- Installs Claude Code with `npm install -g @anthropic-ai/claude-code` if `claude` is not already installed.
- If `npm` is not found, automatically installs Node.js via [fnm](https://github.com/Schniz/fnm) (no sudo required).
- Lets the user choose the MiniMax endpoint:
  - China mainland: `https://api.minimaxi.com/anthropic`
  - International: `https://api.minimax.io/anthropic`
- Lets the user enter their own MiniMax API key.
- Lets the user choose the model name, defaulting to `MiniMax-M2.7`.
- Writes Claude Code environment settings to `~/.claude/settings.json`.
- Optionally installs a local `127.0.0.1` relay for users who want a CC Switch-like proxy flow.

## Test

After installation:

```bash
claude -p '只回复 OK'
```

For interactive Claude Code:

```bash
claude
```

## Security

Codalane does not ship with any API key. Users must provide their own MiniMax API key during installation.

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

