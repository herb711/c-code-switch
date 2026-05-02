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

运行 `install.sh` 或 `ccr` 后，按提示完成配置：

1. 选择模型服务提供方：MiniMax、DeepSeek V4、Kimi 或 vLLM
2. 按提示选择或填写服务地址
3. 选择脚本列出的模型，或输入自定义模型名
4. 输入对应服务的 API key
5. 选择连接模式
   - Direct mode：Claude Code 直接请求上游服务
   - Local proxy mode：Claude Code 先请求本地 `agent-router-proxy`，再由代理转发到上游服务
6. 如果选择本地代理，填写本地代理端口，默认 `8080` 直接回车即可
7. 如果提示是否启动 systemd 用户服务，建议选择 `Y`，这样重启后代理会自动启动

配置完成后，重新打开 Claude Code：

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
