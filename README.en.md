# agent-router

[中文](README.md) | [English](README.en.md)

agent-router is a headless Claude Code provider installer and switcher for servers and terminal-only environments. It installs or reuses Claude Code, writes `~/.claude/settings.json`, and provides the `ccr` command for switching between MiniMax, DeepSeek V4, Kimi, and vLLM.

This project is not affiliated with Anthropic, MiniMax, DeepSeek, Moonshot AI/Kimi, or vLLM.

## Install

Requirement: `curl`. If Node.js/npm is missing, the installer can install Node.js under the user directory without sudo.

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

If `nodejs.org` is hard to reach from your network, set a mirror first:

```bash
export AGENT_ROUTER_NODE_MIRROR=https://npmmirror.com/mirrors/node
```

## Configuration Guide

After running `install.sh` or `ccr`, follow the prompts:

1. Choose a model provider: MiniMax, DeepSeek V4, Kimi, or vLLM
2. Select or enter the service URL
3. Choose a listed model or enter a custom model name
4. Enter the API key for that service
5. Choose the connection mode
   - Direct mode: Claude Code requests the upstream service directly
   - Local proxy mode: Claude Code requests the local `agent-router-proxy`, which forwards to the upstream service
6. If local proxy mode is selected, enter the local proxy port; press Enter to use the default `8080`
7. If prompted to start the systemd user service, choose `Y` so the proxy can restart automatically after reboot

After configuration, open Claude Code again:

```bash
claude
```

## Supported Providers

- MiniMax
- DeepSeek V4
- Kimi
- vLLM, OpenAI-compatible API

MiniMax, DeepSeek, and Kimi use Anthropic-compatible APIs. They can be used directly or through the local proxy.

vLLM exposes OpenAI-compatible `/chat/completions`, while Claude Code speaks the Anthropic Messages API. For that reason, vLLM always uses the local `agent-router-proxy` adapter.

## vLLM Flow

vLLM needs a few extra notes:

- vLLM always uses local proxy mode because Claude Code's Anthropic Messages API must be adapted to an OpenAI-compatible API.
- If the vLLM base URL is left empty, the default local URL is used:

```text
http://127.0.0.1:8000/v1
```

- If you enter only `http://host:port`, the script automatically normalizes it to `http://host:port/v1`.
- The script requests `${base_url}/models` to discover served models. If discovery fails, enter the model name manually.
- If your local vLLM server does not require authentication, leave the API key empty and the script will store `EMPTY`. Remote vLLM servers usually require a real key.

Claude Code sends tool definitions to the model. For better Claude Code tool support, enable auto tool calling on the vLLM server. For Qwen3-family models:

```bash
vllm serve Qwen/Qwen3.6-35B-A3B \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_xml
```

## Local Proxy

vLLM and optional local proxy mode install:

```text
~/.local/bin/agent-router-proxy
~/.local/share/agent-router-proxy/proxy.env
~/.config/systemd/user/agent-router-proxy.service
```

Useful checks:

```bash
systemctl --user status agent-router-proxy.service
curl http://127.0.0.1:8080/health
```

`Local proxy port [8080]` is the local port Claude Code uses to reach the adapter. It is not your vLLM server port. Press Enter to use the default, or choose another local free port such as `18080` if `8080` is occupied.

## Switch Provider or Model

After installation, run:

```bash
~/.local/bin/ccr
```

If `~/.local/bin` is already on your `PATH`, run:

```bash
ccr
```

An alias is also installed:

```bash
agent-router
```

The switcher shows the current provider, base URL, and model. If you keep the same provider, you can leave the API key prompt empty to reuse the stored key. If local proxy mode is active, the switcher updates `proxy.env` and restarts `agent-router-proxy.service` when it is running.

## Test

Command-line test:

```bash
claude -p 'Reply only OK'
```

Interactive Claude Code:

```bash
claude
```

Check the current model configuration:

```bash
grep ANTHROPIC_MODEL ~/.claude/settings.json
curl http://127.0.0.1:8080/health
```

## Changelog

### Current Version

- Added vLLM OpenAI-compatible API support through the local `agent-router-proxy` adapter for Claude Code's Anthropic Messages API.
- Changed the vLLM setup flow to ask for the base URL first, discover `/models`, ask for a manual model name only when discovery fails, and prompt for the API key last.
- Fixed the systemd user service failing to start the proxy when `node` is not on systemd's default `PATH`.
- Renamed the local proxy service to `agent-router-proxy.service` to avoid collisions with other projects.
- Added a default vLLM upstream `max_tokens` cap of `4096` to avoid rejections from local models when Claude Code requests very large completions.
- Made Chinese the default GitHub README and added `README.en.md` for English.

## Security

agent-router does not ship with any API key. Users provide keys during installation or switching, and the values are written only to local user configuration files.

Do not commit generated files such as:

- `~/.claude/settings.json`
- `~/.local/share/agent-router-proxy/proxy.env`
- `.env`
- logs containing prompts, responses, or credentials

The local proxy listens on `127.0.0.1` only. Do not expose it to the public internet.

## License

agent-router is source-available under the PolyForm Noncommercial License 1.0.0.

Non-commercial use is permitted. Commercial use requires a separate written license from the copyright holder. See [COMMERCIAL.md](COMMERCIAL.md).

This is not an OSI-approved open source license.
