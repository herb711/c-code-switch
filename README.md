# agent-router

[中文](README.md) | [English](README.en.md)

agent-router 是一个面向服务器和纯终端环境的 Claude Code 模型路由安装器。它会安装或复用 Claude Code，写入 `~/.claude/settings.json`，并提供 `ccr` 命令在 MiniMax、DeepSeek V4、Kimi 和 vLLM 之间切换。

本项目不隶属于 Anthropic、MiniMax、DeepSeek、Moonshot AI/Kimi 或 vLLM。

## 安装

要求：`curl`。如果系统里没有 Node.js/npm，脚本会自动安装到用户目录，不需要 sudo。

建议先下载并查看脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/herb711/agent-router/main/install.sh -o install.sh
less install.sh
bash install.sh
```

也可以一行安装：

```bash
curl -fsSL https://raw.githubusercontent.com/herb711/agent-router/main/install.sh | bash
```

如果访问 `nodejs.org` 不稳定，可以先设置镜像：

```bash
export AGENT_ROUTER_NODE_MIRROR=https://npmmirror.com/mirrors/node
```

## 配置向导

安装时运行：

```bash
bash install.sh
```

以后想换模型或换服务商，运行：

```bash
ccr
```

提示里的方括号表示默认值。例如 `[1]`、`[8080]` 都可以直接按回车使用默认值。

### 选择服务商

脚本会显示：

```text
Choose upstream provider:
  1) MiniMax
  2) DeepSeek V4
  3) Kimi
  4) vLLM (OpenAI-compatible)
Provider choice [1]:
```

输入数字后回车：

- 用 MiniMax：直接回车，或输入 `1`
- 用 DeepSeek V4：输入 `2`
- 用 Kimi：输入 `3`
- 用自己的 vLLM：输入 `4`

### 填写服务地址

MiniMax 会让你选国内或国际地址：

```text
Choose MiniMax endpoint:
  1) China mainland: https://api.minimaxi.com/anthropic
  2) International:  https://api.minimax.io/anthropic
Endpoint choice [1]:
```

在国内使用通常直接回车。需要国际站时输入 `2`。

DeepSeek V4 和 Kimi 使用脚本内置的默认地址，一般不需要手动填写。

vLLM 会让你填写 OpenAI-compatible base URL：

```text
OpenAI-compatible base URL [http://127.0.0.1:8000/v1]:
```

如果 vLLM 就在本机默认端口，直接回车。如果 vLLM 在其它机器，填写你的地址，例如：

```text
http://113.249.108.72:15581/v1
```

也可以只填到端口：

```text
http://113.249.108.72:15581
```

脚本会自动补成 `/v1`。

### 选择模型

MiniMax、DeepSeek V4、Kimi 会显示模型菜单，例如：

```text
Primary model:
  1) kimi-k2.5 (recommended for Claude Code)
  2) kimi-k2.6 (latest)
  3) kimi-k2-turbo-preview (faster)
  4) kimi-k2-thinking (thinking)
  5) Custom model name
Model choice [1]:
```

通常直接回车使用推荐模型。要用列表里的其它模型，就输入对应数字。要手动填写模型名，选 `Custom model name` 对应的数字。

vLLM 会先尝试读取服务端模型列表：

```text
Checking models from http://127.0.0.1:8000/v1/models...
Discovered models:
  1) Qwen/Qwen3.6-35B-A3B
  2) Custom model name
Model choice [1]:
```

如果模型被发现，直接回车即可。如果没有发现，会看到：

```text
Could not discover models from http://127.0.0.1:8000/v1/models.
Model name:
```

这时手动输入 vLLM 启动时的模型名，例如：

```text
Qwen/Qwen3.6-35B-A3B
```

### 填写 API key

脚本会提示：

```text
API Key input is hidden. Paste the key, then press Enter.
API Key:
```

粘贴 key 后回车。输入过程不会显示字符，这是正常的。

如果是本机无鉴权 vLLM，会显示：

```text
vLLM API Key input is hidden. Leave empty to use EMPTY for a local vLLM server.
vLLM API Key:
```

本机 vLLM 没有开启鉴权时，直接回车即可。远程 vLLM 或开启鉴权的 vLLM，需要粘贴真实 API key。

再次运行 `ccr` 且服务商不变时，API key 可以留空，脚本会复用已保存的 key。

### 选择连接模式

MiniMax、DeepSeek V4、Kimi 会让你选择连接方式：

```text
Choose Claude Code connection mode:
  1) Direct mode: Claude Code calls Kimi directly. Recommended.
  2) Local proxy mode: install a local 127.0.0.1 proxy, then Claude Code calls the proxy.
Mode [1]:
```

一般直接回车，使用 `Direct mode`。只有你明确想让 Claude Code 先走本机代理时，才输入 `2`。

vLLM 不会出现这个选择，因为它固定需要本地代理做协议适配。你会看到：

```text
vLLM uses an OpenAI-compatible API. Claude Code will use the local Anthropic adapter proxy.
Local proxy port [8080]:
```

这里填的是 Claude Code 连接本机代理的端口，不是 vLLM 服务端口。通常直接回车使用 `8080`。如果 `8080` 已被占用，可以输入其它本机空闲端口，例如：

```text
18080
```

### 启动本地代理服务

如果使用 vLLM 或选择了 Local proxy mode，脚本会询问：

```text
Start proxy as a systemd user service now? [Y/n]:
```

建议直接回车，等同于选择 `Y`。这样代理会注册为 `agent-router-proxy.service`，电脑或服务器重启后会自动启动；以后只要不换模型，通常不需要再运行脚本。

配置完成后，脚本会提示：

```text
Done. Open Claude Code again for the new provider/model to take effect.
```

然后重新打开 Claude Code：

```bash
claude
```

## 支持的模型服务

- MiniMax
- DeepSeek V4
- Kimi
- vLLM，OpenAI-compatible API

MiniMax、DeepSeek 和 Kimi 走 Anthropic-compatible API，可以直连，也可以走本地代理。

vLLM 走 OpenAI-compatible `/chat/completions`，而 Claude Code 使用 Anthropic Messages API，所以 vLLM 会固定使用本地 `agent-router-proxy` 做协议适配。

## vLLM 流程

vLLM 需要额外注意：

- vLLM 固定使用 Local proxy mode，因为需要把 Claude Code 的 Anthropic Messages API 转成 OpenAI-compatible API。
- vLLM base URL 留空时默认使用本地地址：

```text
http://127.0.0.1:8000/v1
```

- 如果只填写 `http://host:port`，脚本会自动补全为 `http://host:port/v1`。
- 脚本会请求 `${base_url}/models` 自动发现模型；发现失败时再手动输入模型名。
- 如果本地 vLLM 没有开启鉴权，API key 可以留空，脚本会写入 `EMPTY`。远程 vLLM 通常需要填写真实 key。

Claude Code 会向模型发送工具定义。为了让 vLLM 更好支持 Claude Code 的工具调用，推荐在 vLLM 服务端启用自动工具调用。以 Qwen3 系列为例：

```bash
vllm serve Qwen/Qwen3.6-35B-A3B \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_xml
```

## 本地代理

vLLM 和可选的本地代理模式会安装：

```text
~/.local/bin/agent-router-proxy
~/.local/share/agent-router-proxy/proxy.env
~/.config/systemd/user/agent-router-proxy.service
```

常用检查命令：

```bash
systemctl --user status agent-router-proxy.service
curl http://127.0.0.1:8080/health
```

`Local proxy port [8080]` 指的是 Claude Code 连接本机代理的端口，不是 vLLM 服务器端口。默认直接回车即可；如果 `8080` 被占用，可以换成 `18080` 等本机空闲端口。

## 切换模型

安装后运行：

```bash
~/.local/bin/ccr
```

如果 `~/.local/bin` 已经在 `PATH` 中，也可以直接运行：

```bash
ccr
```

也会安装一个同义命令：

```bash
agent-router
```

切换器会显示当前 provider、base URL 和模型。保持同一个 provider 时，API key 可以留空以复用已保存的 key。如果本地代理服务正在运行，切换器会更新 `proxy.env` 并重启 `agent-router-proxy.service`。

## 测试

命令行测试：

```bash
claude -p 'Reply only OK'
```

交互模式：

```bash
claude
```

查看当前模型配置：

```bash
grep ANTHROPIC_MODEL ~/.claude/settings.json
curl http://127.0.0.1:8080/health
```

## 版本记录

### 当前版本

- 新增 vLLM OpenAI-compatible API 支持，通过本地 `agent-router-proxy` 适配 Claude Code 的 Anthropic Messages API。
- vLLM 配置流程调整为先填写 base URL，再自动发现 `/models`，发现失败时手动输入模型名，最后填写 API key。
- 修复 systemd 用户服务启动代理时找不到 `node` 的问题。
- 本地代理服务统一命名为 `agent-router-proxy.service`，避免与其他项目重名。
- vLLM 代理默认限制上游 `max_tokens` 为 `4096`，避免部分本地模型因 Claude Code 默认输出长度过大而拒绝请求。
- README 默认改为中文，并新增英文版本 `README.en.md`。

## 安全

agent-router 不内置任何 API key。key 只在安装或切换时由用户输入，并写入当前用户目录下的本地配置。

不要提交这些文件：

- `~/.claude/settings.json`
- `~/.local/share/agent-router-proxy/proxy.env`
- `.env`
- 包含 prompt、响应或凭据的日志

本地代理只监听 `127.0.0.1`。不要把它暴露到公网。

## 许可证

agent-router 使用 PolyForm Noncommercial License 1.0.0 作为 source-available 许可证。

允许非商业使用。商业使用需要获得版权持有者的单独书面授权。详情见 [COMMERCIAL.md](COMMERCIAL.md)。

这不是 OSI 认可的开源许可证。
