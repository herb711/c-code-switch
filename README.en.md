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

Run this for the first installation:

```bash
bash install.sh
```

Run this later when you want to switch provider or model:

```bash
ccr
```

Square brackets show the default value. For example, `[1]` and `[8080]` mean you can press Enter to use that value.

### Choose Provider

The script shows:

```text
Choose upstream provider:
  1) MiniMax
  2) DeepSeek V4
  3) Kimi
  4) vLLM (OpenAI-compatible)
Provider choice [1]:
```

Type a number and press Enter:

- MiniMax: press Enter, or type `1`
- DeepSeek V4: type `2`
- Kimi: type `3`
- Your own vLLM server: type `4`

### Enter Service URL

MiniMax asks you to choose the China mainland or international endpoint:

```text
Choose MiniMax endpoint:
  1) China mainland: https://api.minimaxi.com/anthropic
  2) International:  https://api.minimax.io/anthropic
Endpoint choice [1]:
```

For China mainland usage, press Enter. For the international endpoint, type `2`.

DeepSeek V4 and Kimi use built-in default endpoints, so you usually do not need to enter a URL manually.

vLLM asks for an OpenAI-compatible base URL:

```text
OpenAI-compatible base URL [http://127.0.0.1:8000/v1]:
```

If vLLM runs on the same machine with the default port, press Enter. If vLLM runs elsewhere, enter your URL, for example:

```text
http://113.249.108.72:15581/v1
```

You may also enter only the host and port:

```text
http://113.249.108.72:15581
```

The script automatically appends `/v1`.

### Choose Model

MiniMax, DeepSeek V4, and Kimi show a model menu, for example:

```text
Primary model:
  1) kimi-k2.5 (recommended for Claude Code)
  2) kimi-k2.6 (latest)
  3) kimi-k2-turbo-preview (faster)
  4) kimi-k2-thinking (thinking)
  5) Custom model name
Model choice [1]:
```

Usually, press Enter to use the recommended model. To use another listed model, type its number. To enter a model name manually, choose the `Custom model name` number.

vLLM first tries to read the model list from the server:

```text
Checking models from http://127.0.0.1:8000/v1/models...
Discovered models:
  1) Qwen/Qwen3.6-35B-A3B
  2) Custom model name
Model choice [1]:
```

If the model is discovered, press Enter. If discovery fails, you will see:

```text
Could not discover models from http://127.0.0.1:8000/v1/models.
Model name:
```

Enter the model name used by your vLLM server, for example:

```text
Qwen/Qwen3.6-35B-A3B
```

### Enter API Key

The script shows:

```text
API Key input is hidden. Paste the key, then press Enter.
API Key:
```

Paste the key and press Enter. The input is hidden, so characters will not appear on screen.

For a local vLLM server without authentication, the script shows:

```text
vLLM API Key input is hidden. Leave empty to use EMPTY for a local vLLM server.
vLLM API Key:
```

If your local vLLM server does not require authentication, press Enter. For a remote vLLM server, or a vLLM server with authentication enabled, paste the real API key.

When running `ccr` again with the same provider, you can leave the API key empty to reuse the stored key.

### Choose Connection Mode

MiniMax, DeepSeek V4, and Kimi ask for the connection mode:

```text
Choose Claude Code connection mode:
  1) Direct mode: Claude Code calls Kimi directly. Recommended.
  2) Local proxy mode: install a local 127.0.0.1 proxy, then Claude Code calls the proxy.
Mode [1]:
```

Usually, press Enter to use `Direct mode`. Choose `2` only when you explicitly want Claude Code to go through a local proxy first.

vLLM does not show this choice because it always needs the local adapter proxy. You will see:

```text
vLLM uses an OpenAI-compatible API. Claude Code will use the local Anthropic adapter proxy.
Local proxy port [8080]:
```

This is the local proxy port used by Claude Code. It is not the vLLM server port. Usually, press Enter to use `8080`. If `8080` is already occupied, enter another free local port, for example:

```text
18080
```

### Start Local Proxy Service

If you use vLLM or choose local proxy mode, the script asks:

```text
Start proxy as a systemd user service now? [Y/n]:
```

Press Enter to choose `Y`. This registers `agent-router-proxy.service`, so the proxy starts automatically after the machine reboots. If you do not switch models later, you usually do not need to run the script again.

After configuration, the script shows:

```text
Done. Open Claude Code again for the new provider/model to take effect.
```

Then open Claude Code again:

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
