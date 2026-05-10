# agent-router

[中文](README.md) | [English](README.en.md)

agent-router 是一个面向服务器和纯终端环境的 Claude Code / Codex CLI 模型路由安装器。它会安装或复用 Claude Code 和 Codex CLI，写入 `~/.claude/settings.json` 或 `~/.codex/config.toml`，并统一使用 `ccr` 切换配置。

本项目不隶属于 Anthropic、OpenAI、MiniMax、DeepSeek、Moonshot AI/Kimi 或 vLLM。

## 安装

要求：`curl`。如果系统里没有 Node.js/npm，脚本会自动安装到用户目录，不需要 sudo。

推荐先从 GitHub 下载脚本，查看后再执行：

```bash
curl -fL --connect-timeout 15 --max-time 120 --retry 3 \
  https://raw.githubusercontent.com/herb711/agent-router/main/install.sh -o install.sh
less install.sh
bash install.sh
```

如果 `raw.githubusercontent.com` 访问不稳定，可以使用 jsDelivr Fastly 镜像：

```bash
curl -fL --connect-timeout 15 --max-time 120 --retry 3 \
  https://fastly.jsdelivr.net/gh/herb711/agent-router@main/install.sh -o install.sh
less install.sh
bash install.sh
```

也可以使用 GitHub raw 一键安装：

```bash
curl -fL --connect-timeout 15 --max-time 120 --retry 3 \
  https://raw.githubusercontent.com/herb711/agent-router/main/install.sh | bash
```

如果 GitHub raw 访问不稳定，可以使用镜像一键安装：

```bash
curl -fL --connect-timeout 15 --max-time 120 --retry 3 \
  https://fastly.jsdelivr.net/gh/herb711/agent-router@main/install.sh | bash
```

如果你使用 `raw.githubusercontent.com` 一直没有输出，通常是网络连不上 GitHub raw 域名；`curl -s` 会隐藏下载进度，所以看起来像卡住。上面的 `fastly.jsdelivr.net` 地址在国内网络通常更稳定，也比 `cdn.jsdelivr.net` 更不容易拿到旧缓存。

如果访问 `nodejs.org` 不稳定，可以先设置镜像：

```bash
export AGENT_ROUTER_NODE_MIRROR=https://npmmirror.com/mirrors/node
```

## 配置向导

安装时运行：

```bash
bash install.sh
```

脚本会先询问要配置哪个工具：

```text
Choose target tool:
  1) Claude Code
  2) Codex CLI
  3) Both
Target choice [1]:
```

以后想换模型或换服务商，运行：

```bash
ccr
```

`ccr` 会根据当前已安装的命令自动选择：只安装 Claude Code 时直接进入 Claude Code 配置，只安装 Codex CLI 时直接进入 Codex 配置；如果两个都安装了，才会询问要配置哪一个。

提示里的方括号表示默认值。例如 `[1]`、`[8080]` 都可以直接按回车使用默认值。

### 选择 Claude Code 服务商

配置 Claude Code 时，脚本会显示：

```text
Choose upstream provider:
  1) MiniMax
  2) DeepSeek V4
  3) Zhipu GLM
  4) Kimi
  5) Xiaomi MiMo
  6) Custom OpenAI-compatible / vLLM
Provider choice [1]:
```

输入数字后回车：

- 用 MiniMax：直接回车，或输入 `1`
- 用 DeepSeek V4：输入 `2`
- 用智谱 GLM：输入 `3`
- 用 Kimi：输入 `4`
- 用小米 MiMo：输入 `5`
- 用自己的 vLLM 或其它 OpenAI-compatible 服务：输入 `6`

### 填写服务地址

MiniMax 会让你选国内或国际地址：

```text
Choose MiniMax endpoint:
  1) China mainland: https://api.minimaxi.com/anthropic
  2) International:  https://api.minimax.io/anthropic
Endpoint choice [1]:
```

在国内使用通常直接回车。需要国际站时输入 `2`。

DeepSeek V4、智谱 GLM、Kimi 和小米 MiMo 使用脚本内置的默认地址，一般不需要手动填写。MiMo 的入口页是 `https://mimo.mi.com/`。

Custom OpenAI-compatible / vLLM 会让你填写 OpenAI-compatible base URL：

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

### 配置 Codex CLI

新版 Codex CLI 使用 OpenAI Responses API 协议。国内很多 OpenAI-compatible 服务还停在 Chat Completions，所以安装器会先让你选厂家，再自动带出服务地址。

```text
Choose Codex upstream provider:
  1) MiniMax
  2) DeepSeek
  3) Zhipu GLM
  4) Kimi / Moonshot
  5) Xiaomi MiMo
  6) Custom OpenAI-compatible / vLLM
Provider choice [1]:
```

选择 MiniMax、DeepSeek、智谱 GLM、Kimi、小米 MiMo 时，脚本会使用内置 OpenAI-compatible 地址，不需要再填写 URL。只有选择 `Custom OpenAI-compatible / vLLM` 时，才会询问：

```text
OpenAI-compatible base URL [http://127.0.0.1:8000/v1]:
```

填写 API key 后，脚本会自动访问 `${base URL}/models` 获取可用模型，并把结果做成菜单：

```text
Checking models from http://113.249.108.72:15581/v1/models...
Available models:
  1) Qwen/Qwen3.6-35B-A3B
  2) Custom model name
Model choice [1]:
```

如果扫不到模型，但以前配置过模型，脚本会先显示历史模型菜单；没有历史模型时才会让你手动填写模型名：

```text
Could not discover models from http://113.249.108.72:15581/v1/models.
Previously configured models:
  1) Qwen/Qwen3.6-35B-A3B
  2) Custom model name
Model choice [1]:
```

国内很多服务的 OpenAI-compatible 接口实际还是 Chat Completions。脚本会自动为 Codex 安装独立的本地 Responses 适配代理：

```text
~/.local/bin/agent-router-codex-proxy
~/.local/share/agent-router-codex-proxy/proxy.env
~/.config/systemd/user/agent-router-codex-proxy.service
```

这样 Codex 仍然访问本地 `/v1/responses`，由代理再转发到上游 `/chat/completions`。除非你填写的是 OpenAI 官方 Responses 地址，Codex 默认都会走这个适配路径。

### 选择模型

MiniMax、DeepSeek V4、智谱 GLM、Kimi 会显示模型菜单，例如：

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
Claude Code 和 Codex CLI 都会记录成功写入过的模型；下次切换时，菜单会把这些历史模型和服务端发现的模型一起展示，方便直接选回以前用过的模型。

vLLM 会先尝试读取服务端模型列表：

```text
Checking models from http://127.0.0.1:8000/v1/models...
Available models:
  1) Qwen/Qwen3.6-35B-A3B
  2) Custom model name
Model choice [1]:
```

如果模型被发现或历史里已有可用项，直接回车即可。如果没有发现且没有历史，会看到：

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

智谱 GLM、小米 MiMo 和 Custom OpenAI-compatible / vLLM 不会出现这个选择，因为它们固定需要本地代理做协议适配。你会看到：

```text
Zhipu GLM uses an OpenAI-compatible API. Claude Code will use the local Anthropic adapter proxy.
Local proxy port [8080]:
```

智谱 GLM、小米 MiMo 和 Custom OpenAI-compatible / vLLM 会固定使用本地代理做协议适配。这里填的是 Claude Code 连接本机代理的端口，不是上游服务端口。通常直接回车使用 `8080`。如果 `8080` 已被占用，可以输入其它本机空闲端口，例如：

```text
18080
```

### 启动本地代理服务

如果使用智谱 GLM、小米 MiMo、Custom OpenAI-compatible / vLLM，或选择了 Local proxy mode，脚本会询问：

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

Claude Code：

- MiniMax
- DeepSeek V4
- Kimi
- 智谱 GLM，OpenAI-compatible API
- 小米 MiMo，OpenAI-compatible API
- Custom OpenAI-compatible / vLLM

MiniMax、DeepSeek 和 Kimi 走 Anthropic-compatible API，可以直连，也可以走本地代理。

智谱 GLM、小米 MiMo 和 Custom OpenAI-compatible / vLLM 走 OpenAI-compatible `/chat/completions`，而 Claude Code 使用 Anthropic Messages API，所以它们会固定使用本地 `agent-router-proxy` 做协议适配。

Codex CLI：

- 支持 Responses API 的 OpenAI 或兼容服务
- 只支持 Chat Completions 的兼容服务，通过本地 `agent-router-codex-proxy` 适配

## vLLM 流程

vLLM 需要额外注意：

- 智谱 GLM、小米 MiMo 和 Custom OpenAI-compatible / vLLM 固定使用 Local proxy mode，因为需要把 Claude Code 的 Anthropic Messages API 转成 OpenAI-compatible API。
- Custom OpenAI-compatible / vLLM base URL 留空时默认使用本地地址：

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

Claude Code 安装后运行：

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

Codex CLI 也使用同一个 `ccr`。如果系统里同时存在 `claude` 和 `codex`，`ccr` 会显示工具选择菜单；如果只存在其中一个，它会直接进入对应切换流程。

## 测试

命令行测试：

```bash
claude -p 'Reply only OK'
```

Codex 命令行测试：

```bash
codex exec 'Reply only OK'
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
- 新增 Codex CLI 安装，并统一由 `ccr` 根据已安装的 Claude Code / Codex CLI 自动分流。Codex 先选模型，再自动选择 Responses API 或本地 Responses-to-Chat-Completions 适配代理；配置固定使用 `wire_api = "responses"`。
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
