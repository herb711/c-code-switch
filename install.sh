#!/usr/bin/env bash
set -euo pipefail

APP_NAME="agent-router"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
PROXY_DIR="${HOME}/.local/share/agent-router-proxy"
PROXY_BIN="${PROXY_DIR}/proxy.js"
PROXY_ENV="${PROXY_DIR}/proxy.env"
USER_BIN_DIR="${HOME}/.local/bin"
NODE_ROOT="${HOME}/.local/share/agent-router-node"
NODE_VERSION="${AGENT_ROUTER_NODE_VERSION:-20.18.1}"
PROXY_LAUNCHER="${USER_BIN_DIR}/agent-router-proxy"
SWITCHER_BIN="${USER_BIN_DIR}/ccr"
SWITCHER_ALIAS="${USER_BIN_DIR}/agent-router"
SERVICE_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SERVICE_DIR}/agent-router-proxy.service"

say() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_user_bin_dir() {
  mkdir -p "$USER_BIN_DIR"
  export PATH="${USER_BIN_DIR}:${PATH}"
}

node_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s' "x64" ;;
    aarch64|arm64) printf '%s' "arm64" ;;
    *) die "unsupported CPU architecture for automatic Node.js install: $(uname -m)" ;;
  esac
}

download_node_archive() {
  local version="$1"
  local arch="$2"
  local output="$3"
  local archive="node-v${version}-linux-${arch}.tar.xz"
  local base_urls=(
    "${AGENT_ROUTER_NODE_MIRROR:-https://nodejs.org/dist}"
    "https://npmmirror.com/mirrors/node"
  )
  local base_url

  for base_url in "${base_urls[@]}"; do
    say "Downloading Node.js from ${base_url}..."
    if curl -fL --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 3 \
      "${base_url}/v${version}/${archive}" -o "$output"; then
      return 0
    fi
  done

  return 1
}

link_node_commands() {
  local node_dir="$1"
  local cmd

  ensure_user_bin_dir
  for cmd in node npm npx; do
    [ -x "${node_dir}/bin/${cmd}" ] || die "Node.js install is missing ${cmd}."
    ln -sf "${node_dir}/bin/${cmd}" "${USER_BIN_DIR}/${cmd}"
  done
}

read_from_tty() {
  local prompt="$1"
  local silent="${2:-0}"
  local value

  [ -r /dev/tty ] || die "interactive input requires a TTY. Run this script from a terminal."

  printf '%s' "$prompt" >/dev/tty
  if [ "$silent" = "1" ]; then
    IFS= read -r -s value </dev/tty || die "failed to read input from terminal."
    printf '\n' >/dev/tty
  else
    IFS= read -r value </dev/tty || die "failed to read input from terminal."
  fi

  value="$(printf '%s' "$value" | LC_ALL=C tr -d '\000-\037\177')"
  printf '%s' "$value"
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value
  value="$(read_from_tty "${prompt} [${default}]: ")"
  printf '%s' "${value:-$default}"
}

prompt_secret() {
  local prompt="$1"
  local value
  value="$(read_from_tty "${prompt}: " 1)"
  printf '%s' "$value"
}

prompt_required_secret() {
  local prompt="$1"
  local value

  while true; do
    value="$(prompt_secret "$prompt")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
    printf '%s\n' "Input was empty. Paste your key, then press Enter. The key will not be shown while typing." >/dev/tty
  done
}

prompt_required() {
  local prompt="$1"
  local value

  while true; do
    value="$(read_from_tty "${prompt}: ")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
    printf '%s\n' "Input was empty. Enter a value, then press Enter." >/dev/tty
  done
}

tty_say() {
  printf '%s\n' "$*" >/dev/tty
}

model_note() {
  local model="$1"

  if [ "$model" = "MiniMax-M2.7" ]; then
    printf '%s' "recommended"
  elif [ "$model" = "MiniMax-M2.7-highspeed" ]; then
    printf '%s' "recommended high-speed"
  elif [ "$model" = "deepseek-v4-pro[1m]" ]; then
    printf '%s' "recommended primary, 1M context"
  elif [ "$model" = "deepseek-v4-flash" ]; then
    printf '%s' "recommended small/fast"
  elif [ "$model" = "kimi-k2.5" ]; then
    printf '%s' "recommended for Claude Code"
  elif [ "$model" = "kimi-k2.6" ]; then
    printf '%s' "latest"
  elif [ "$model" = "kimi-k2-turbo-preview" ]; then
    printf '%s' "faster"
  elif [ "$model" = "kimi-k2-thinking" ]; then
    printf '%s' "thinking"
  fi
}

select_model_menu() {
  local provider="$1"
  local kind="$2"
  local default_model="$3"
  local prompt="$4"
  local models=()
  local model
  local note
  local i
  local choice
  local custom_choice
  local default_choice=1

  case "${provider}:${kind}" in
    minimax:primary|minimax:small)
      models=(
        "MiniMax-M2.7"
        "MiniMax-M2.7-highspeed"
        "MiniMax-M2.5"
        "MiniMax-M2.5-highspeed"
        "MiniMax-M2.1"
        "MiniMax-M2.1-highspeed"
        "MiniMax-M2"
      )
      ;;
    deepseek:primary)
      models=(
        "deepseek-v4-pro[1m]"
        "deepseek-v4-pro"
        "deepseek-v4-flash"
      )
      ;;
    deepseek:small)
      models=(
        "deepseek-v4-flash"
        "deepseek-v4-pro"
        "deepseek-v4-pro[1m]"
      )
      ;;
    kimi:primary|kimi:small)
      models=(
        "kimi-k2.5"
        "kimi-k2.6"
        "kimi-k2-turbo-preview"
        "kimi-k2-thinking"
        "kimi-k2-thinking-turbo"
        "kimi-k2-0905-preview"
        "kimi-k2-0711-preview"
      )
      ;;
    *)
      printf '%s' "$(prompt_default "$prompt" "$default_model")"
      return
      ;;
  esac

  custom_choice=$((${#models[@]} + 1))
  for i in "${!models[@]}"; do
    if [ "${models[$i]}" = "$default_model" ]; then
      default_choice=$((i + 1))
    fi
  done
  if ! printf '%s\n' "${models[@]}" | grep -Fxq "$default_model"; then
    default_choice="$custom_choice"
  fi

  tty_say "$prompt:"
  for i in "${!models[@]}"; do
    model="${models[$i]}"
    note="$(model_note "$model")"
    if [ -n "$note" ]; then
      tty_say "  $((i + 1))) ${model} (${note})"
    else
      tty_say "  $((i + 1))) ${model}"
    fi
  done
  tty_say "  ${custom_choice}) Custom model name"

  choice="$(prompt_default 'Model choice' "$default_choice")"
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    if [ "$choice" -ge 1 ] && [ "$choice" -le "${#models[@]}" ]; then
      printf '%s' "${models[$((choice - 1))]}"
      return
    fi
    if [ "$choice" -eq "$custom_choice" ]; then
      printf '%s' "$(prompt_default 'Custom model name' "$default_model")"
      return
    fi
  fi

  printf '%s' "$choice"
}

normalize_openai_base_url() {
  local base_url="${1:-http://127.0.0.1:8000/v1}"
  base_url="${base_url%/}"
  case "$base_url" in
    */v1) printf '%s' "$base_url" ;;
    *) printf '%s' "${base_url}/v1" ;;
  esac
}

discover_openai_models() {
  local base_url="$1"
  local models_url="${base_url%/}/models"

  need_cmd curl || return 1
  need_cmd node || return 1

  curl -fsS --connect-timeout 5 --max-time 10 "$models_url" 2>/dev/null | node -e '
const chunks = [];
process.stdin.on("data", chunk => chunks.push(chunk));
process.stdin.on("end", () => {
  const payload = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  const models = Array.isArray(payload.data) ? payload.data : [];
  for (const model of models) {
    if (model && typeof model.id === "string" && model.id.length > 0) {
      console.log(model.id);
    }
  }
});
' 2>/dev/null
}

select_discovered_model_menu() {
  local prompt="$1"
  shift
  local models=("$@")
  local i
  local choice
  local custom_choice
  local default_choice=1

  custom_choice=$((${#models[@]} + 1))

  tty_say "$prompt:"
  for i in "${!models[@]}"; do
    tty_say "  $((i + 1))) ${models[$i]}"
  done
  tty_say "  ${custom_choice}) Custom model name"

  choice="$(prompt_default 'Model choice' "$default_choice")"
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    if [ "$choice" -ge 1 ] && [ "$choice" -le "${#models[@]}" ]; then
      printf '%s' "${models[$((choice - 1))]}"
      return
    fi
    if [ "$choice" -eq "$custom_choice" ]; then
      printf '%s' "$(prompt_required 'Custom model name')"
      return
    fi
  fi

  printf '%s' "$choice"
}

select_openai_model_from_base_url() {
  local base_url="$1"
  local fallback_model="${2:-}"
  local model_lines
  local models=()
  local model

  tty_say "Checking models from ${base_url%/}/models..."
  if model_lines="$(discover_openai_models "$base_url")" && [ -n "$model_lines" ]; then
    while IFS= read -r model; do
      [ -n "$model" ] && models+=("$model")
    done <<< "$model_lines"

    if [ "${#models[@]}" -gt 0 ]; then
      select_discovered_model_menu "Discovered models" "${models[@]}"
      return
    fi
  fi

  tty_say "Could not discover models from ${base_url%/}/models."
  if [ -n "$fallback_model" ]; then
    printf '%s' "$(prompt_default 'Model name' "$fallback_model")"
  else
    printf '%s' "$(prompt_required 'Model name')"
  fi
}

confirm() {
  local prompt="$1"
  local default="${2:-Y}"
  local suffix="[Y/n]"
  local answer
  if [ "$default" = "N" ]; then
    suffix="[y/N]"
  fi
  answer="$(read_from_tty "${prompt} ${suffix}: ")"
  answer="${answer:-$default}"
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

backup_if_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    local backup="${file}.backup.$(date +%s)"
    cp "$file" "$backup"
    say "Backed up existing file: $backup"
  fi
}

install_npm_if_needed() {
  ensure_user_bin_dir

  if need_cmd npm; then
    return
  fi

  if ! need_cmd curl; then
    die "curl is not installed. Install curl first, then rerun this script."
  fi
  if ! need_cmd tar; then
    die "tar is not installed. Install tar first, then rerun this script."
  fi

  local arch
  arch="$(node_arch)"
  local node_dir="${NODE_ROOT}/node-v${NODE_VERSION}-linux-${arch}"

  say "npm not found. Installing Node.js ${NODE_VERSION} to ${NODE_ROOT} (no sudo required)..."

  if [ ! -x "${node_dir}/bin/npm" ]; then
    local tmp_dir
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-router-node.XXXXXX")"
    local archive="${tmp_dir}/node.tar.xz"

    download_node_archive "$NODE_VERSION" "$arch" "$archive" \
      || die "Failed to download Node.js. Check network access to nodejs.org or set AGENT_ROUTER_NODE_MIRROR."

    mkdir -p "$node_dir"
    tar -xJf "$archive" -C "$node_dir" --strip-components=1 \
      || die "Failed to extract Node.js archive."
  fi

  link_node_commands "$node_dir"

  if ! need_cmd npm; then
    die "Node.js installed but npm still not found. Add ${USER_BIN_DIR} to PATH, then rerun this script."
  fi

  say "Node.js and npm installed: $(node --version) / $(npm --version)"
}

install_claude_code() {
  if need_cmd claude; then
    say "Claude Code already installed: $(command -v claude)"
    claude --version || true
    return
  fi

  install_npm_if_needed

  say "Installing Claude Code with npm..."
  ensure_user_bin_dir
  npm install -g --prefix "${HOME}/.local" @anthropic-ai/claude-code

  if ! need_cmd claude; then
    die "Claude Code installed, but claude was not found on PATH. Add ${USER_BIN_DIR} to PATH, then rerun this script."
  fi
}

write_direct_settings() {
  local base_url="$1"
  local api_key="$2"
  local model="$3"
  local small_model="${4:-$3}"
  local effort_level="${5:-}"
  local large_model="${6:-$3}"
  local subagent_model="${7:-$small_model}"
  local disable_nonstreaming_fallback="${8:-}"
  local enable_tool_search="${9:-}"
  local extra_env_lines=""

  if [ -n "$disable_nonstreaming_fallback" ]; then
    extra_env_lines="$(printf '%s,\n    "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK": "%s"' "$extra_env_lines" "$disable_nonstreaming_fallback")"
  fi
  if [ -n "$effort_level" ]; then
    extra_env_lines="$(printf '%s,\n    "CLAUDE_CODE_EFFORT_LEVEL": "%s"' "$extra_env_lines" "$effort_level")"
  fi
  if [ -n "$enable_tool_search" ]; then
    extra_env_lines="$(printf '%s,\n    "ENABLE_TOOL_SEARCH": "%s"' "$extra_env_lines" "$enable_tool_search")"
  fi

  mkdir -p "$CLAUDE_DIR"
  chmod 700 "$CLAUDE_DIR"
  backup_if_exists "$SETTINGS_FILE"

  umask 077
  cat > "$SETTINGS_FILE" <<EOF_SETTINGS
{
  "env": {
    "ANTHROPIC_BASE_URL": "${base_url}",
    "ANTHROPIC_AUTH_TOKEN": "${api_key}",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "ANTHROPIC_MODEL": "${model}",
    "ANTHROPIC_SMALL_FAST_MODEL": "${small_model}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${large_model}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${large_model}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${small_model}",
    "CLAUDE_CODE_SUBAGENT_MODEL": "${subagent_model}"${extra_env_lines}
  }
}
EOF_SETTINGS
  chmod 600 "$SETTINGS_FILE"
  say "Wrote Claude Code settings: $SETTINGS_FILE"
}

write_proxy_files() {
  local provider="$1"
  local base_url="$2"
  local api_key="$3"
  local port="$4"
  local auth_header="$5"
  local api_format="${6:-anthropic}"

  mkdir -p "$PROXY_DIR" "$USER_BIN_DIR"
  chmod 700 "$PROXY_DIR"

  cat > "$PROXY_BIN" <<'EOF_PROXY'
#!/usr/bin/env node
const http = require('http');
const https = require('https');
const { URL } = require('url');

const port = Number(process.env.PORT || '8080');
const provider = process.env.AGENT_ROUTER_PROVIDER || 'minimax';
const apiKey = process.env.UPSTREAM_API_KEY || process.env.MINIMAX_API_KEY;
const baseUrl = process.env.UPSTREAM_BASE_URL || process.env.MINIMAX_BASE_URL || 'https://api.minimaxi.com/anthropic';
const authHeader = (process.env.UPSTREAM_AUTH_HEADER || (provider === 'deepseek' ? 'x-api-key' : 'authorization')).toLowerCase();
const apiFormat = (process.env.UPSTREAM_API_FORMAT || 'anthropic').toLowerCase();
const normalizedApiFormat = apiFormat === 'openai' ? 'openai-chat' : apiFormat;
const maxTokensLimit = Number(process.env.UPSTREAM_MAX_TOKENS || (provider === 'vllm' ? '4096' : '0'));

if (!apiKey) {
  console.error('UPSTREAM_API_KEY is required');
  process.exit(1);
}

if (!['authorization', 'bearer', 'x-api-key'].includes(authHeader)) {
  console.error(`Unsupported UPSTREAM_AUTH_HEADER: ${authHeader}`);
  process.exit(1);
}

if (!['anthropic', 'openai-chat'].includes(normalizedApiFormat)) {
  console.error(`Unsupported UPSTREAM_API_FORMAT: ${apiFormat}`);
  process.exit(1);
}

const upstream = new URL(baseUrl.replace(/\/+$/, ''));
const client = upstream.protocol === 'https:' ? https : http;

function sendJson(res, status, payload) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(payload));
}

function authHeaders() {
  if (authHeader === 'x-api-key') {
    return { 'x-api-key': apiKey };
  }
  return { authorization: `Bearer ${apiKey}` };
}

function upstreamPath(suffix) {
  const basePath = upstream.pathname.replace(/\/+$/, '');
  return `${basePath}/${suffix.replace(/^\/+/, '')}`;
}

function textFromContent(content) {
  if (content == null) {
    return '';
  }
  if (typeof content === 'string') {
    return content;
  }
  if (!Array.isArray(content)) {
    if (typeof content.text === 'string') {
      return content.text;
    }
    return JSON.stringify(content);
  }

  return content
    .map(block => {
      if (!block) {
        return '';
      }
      if (typeof block === 'string') {
        return block;
      }
      if (block.type === 'text' && typeof block.text === 'string') {
        return block.text;
      }
      if (block.type === 'tool_result') {
        return textFromContent(block.content);
      }
      if (typeof block.text === 'string') {
        return block.text;
      }
      return '';
    })
    .filter(Boolean)
    .join('\n');
}

function parseJsonObject(value) {
  if (!value) {
    return {};
  }
  try {
    const parsed = JSON.parse(value);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed;
    }
    return { value: parsed };
  } catch {
    return {};
  }
}

function finishReasonToStopReason(reason) {
  if (reason === 'length') {
    return 'max_tokens';
  }
  if (reason === 'tool_calls' || reason === 'function_call') {
    return 'tool_use';
  }
  if (reason === 'stop') {
    return 'end_turn';
  }
  return reason || 'end_turn';
}

function convertToolChoice(choice) {
  if (!choice) {
    return undefined;
  }
  if (typeof choice === 'string') {
    return choice;
  }
  if (choice.type === 'auto') {
    return 'auto';
  }
  if (choice.type === 'any') {
    return 'required';
  }
  if (choice.type === 'tool' && choice.name) {
    return { type: 'function', function: { name: choice.name } };
  }
  return undefined;
}

function anthropicToOpenAI(body) {
  const messages = [];
  const systemText = textFromContent(body.system);
  if (systemText) {
    messages.push({ role: 'system', content: systemText });
  }

  for (const message of body.messages || []) {
    const role = message.role === 'assistant' ? 'assistant' : 'user';
    const content = message.content;

    if (role === 'assistant' && Array.isArray(content)) {
      const textParts = [];
      const toolCalls = [];
      for (const block of content) {
        if (!block) {
          continue;
        }
        if (block.type === 'tool_use') {
          toolCalls.push({
            id: block.id || `call_${toolCalls.length}`,
            type: 'function',
            function: {
              name: block.name || 'tool',
              arguments: JSON.stringify(block.input || {})
            }
          });
        } else {
          const text = textFromContent([block]);
          if (text) {
            textParts.push(text);
          }
        }
      }
      const openAIMessage = { role: 'assistant', content: textParts.join('\n') || null };
      if (toolCalls.length > 0) {
        openAIMessage.tool_calls = toolCalls;
      }
      messages.push(openAIMessage);
      continue;
    }

    if (role === 'user' && Array.isArray(content)) {
      const textParts = [];
      const toolResults = [];
      for (const block of content) {
        if (block && block.type === 'tool_result') {
          toolResults.push({
            role: 'tool',
            tool_call_id: block.tool_use_id,
            content: textFromContent(block.content)
          });
        } else {
          const text = textFromContent([block]);
          if (text) {
            textParts.push(text);
          }
        }
      }
      if (textParts.length > 0) {
        messages.push({ role: 'user', content: textParts.join('\n') });
      }
      for (const toolResult of toolResults) {
        messages.push(toolResult);
      }
      if (textParts.length === 0 && toolResults.length === 0) {
        messages.push({ role: 'user', content: '' });
      }
      continue;
    }

    messages.push({ role, content: textFromContent(content) });
  }

  const openAIRequest = {
    model: body.model,
    messages,
    stream: !!body.stream
  };

  if (typeof body.max_tokens === 'number') {
    openAIRequest.max_tokens = maxTokensLimit > 0 ? Math.min(body.max_tokens, maxTokensLimit) : body.max_tokens;
  }
  if (typeof body.temperature === 'number') {
    openAIRequest.temperature = body.temperature;
  }
  if (typeof body.top_p === 'number') {
    openAIRequest.top_p = body.top_p;
  }
  if (Array.isArray(body.stop_sequences) && body.stop_sequences.length > 0) {
    openAIRequest.stop = body.stop_sequences;
  }
  if (Array.isArray(body.tools) && body.tools.length > 0) {
    openAIRequest.tools = body.tools.map(tool => ({
      type: 'function',
      function: {
        name: tool.name,
        description: tool.description || '',
        parameters: tool.input_schema || { type: 'object', properties: {} }
      }
    }));
    const toolChoice = convertToolChoice(body.tool_choice);
    if (toolChoice) {
      openAIRequest.tool_choice = toolChoice;
    }
  }

  return openAIRequest;
}

function openAIToAnthropic(payload, requestedModel) {
  const choice = (payload.choices || [])[0] || {};
  const message = choice.message || {};
  const content = [];

  if (message.content) {
    content.push({ type: 'text', text: Array.isArray(message.content) ? textFromContent(message.content) : String(message.content) });
  }

  for (const call of message.tool_calls || []) {
    content.push({
      type: 'tool_use',
      id: call.id || `call_${content.length}`,
      name: (call.function && call.function.name) || 'tool',
      input: parseJsonObject(call.function && call.function.arguments)
    });
  }

  if (content.length === 0) {
    content.push({ type: 'text', text: '' });
  }

  return {
    id: payload.id || `msg_${Date.now()}`,
    type: 'message',
    role: 'assistant',
    model: payload.model || requestedModel,
    content,
    stop_reason: finishReasonToStopReason(choice.finish_reason),
    stop_sequence: null,
    usage: {
      input_tokens: (payload.usage && payload.usage.prompt_tokens) || 0,
      output_tokens: (payload.usage && payload.usage.completion_tokens) || 0
    }
  };
}

function sendSse(res, event, data) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

function pipeOpenAIStreamToAnthropic(proxyRes, res, requestedModel) {
  if ((proxyRes.statusCode || 500) >= 400) {
    res.writeHead(proxyRes.statusCode || 502, { ...proxyRes.headers, 'x-proxied-by': 'agent-router-proxy-server' });
    proxyRes.pipe(res);
    return;
  }

  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache',
    connection: 'keep-alive',
    'x-proxied-by': 'agent-router-proxy-server'
  });

  const messageId = `msg_${Date.now()}`;
  let nextBlockIndex = 0;
  let currentTextIndex = null;
  let stopReason = 'end_turn';
  let usage = { output_tokens: 0 };
  let finished = false;
  const toolStates = new Map();

  sendSse(res, 'message_start', {
    type: 'message_start',
    message: {
      id: messageId,
      type: 'message',
      role: 'assistant',
      model: requestedModel,
      content: [],
      stop_reason: null,
      stop_sequence: null,
      usage: { input_tokens: 0, output_tokens: 0 }
    }
  });

  function closeTextBlock() {
    if (currentTextIndex != null) {
      sendSse(res, 'content_block_stop', { type: 'content_block_stop', index: currentTextIndex });
      currentTextIndex = null;
    }
  }

  function writeTextDelta(text) {
    if (currentTextIndex == null) {
      currentTextIndex = nextBlockIndex++;
      sendSse(res, 'content_block_start', {
        type: 'content_block_start',
        index: currentTextIndex,
        content_block: { type: 'text', text: '' }
      });
    }
    sendSse(res, 'content_block_delta', {
      type: 'content_block_delta',
      index: currentTextIndex,
      delta: { type: 'text_delta', text }
    });
  }

  function startToolBlock(state) {
    if (state.started) {
      return;
    }
    closeTextBlock();
    state.blockIndex = nextBlockIndex++;
    state.started = true;
    sendSse(res, 'content_block_start', {
      type: 'content_block_start',
      index: state.blockIndex,
      content_block: {
        type: 'tool_use',
        id: state.id || `call_${state.key}`,
        name: state.name || 'tool',
        input: {}
      }
    });
    if (state.buffer) {
      sendSse(res, 'content_block_delta', {
        type: 'content_block_delta',
        index: state.blockIndex,
        delta: { type: 'input_json_delta', partial_json: state.buffer }
      });
      state.buffer = '';
    }
  }

  function finishStream() {
    if (finished) {
      return;
    }
    finished = true;

    if (nextBlockIndex === 0) {
      writeTextDelta('');
    }
    closeTextBlock();
    for (const state of toolStates.values()) {
      startToolBlock(state);
      sendSse(res, 'content_block_stop', { type: 'content_block_stop', index: state.blockIndex });
    }
    sendSse(res, 'message_delta', {
      type: 'message_delta',
      delta: { stop_reason: stopReason, stop_sequence: null },
      usage
    });
    sendSse(res, 'message_stop', { type: 'message_stop' });
    res.end();
  }

  function processChunk(payload) {
    const choice = (payload.choices || [])[0] || {};
    const delta = choice.delta || {};
    if (payload.usage) {
      usage = { output_tokens: payload.usage.completion_tokens || 0 };
    }
    if (choice.finish_reason) {
      stopReason = finishReasonToStopReason(choice.finish_reason);
    }
    if (delta.content) {
      writeTextDelta(delta.content);
    }
    for (const toolCall of delta.tool_calls || []) {
      const key = toolCall.index == null ? toolStates.size : toolCall.index;
      const state = toolStates.get(key) || { key, id: '', name: '', buffer: '', started: false, blockIndex: null };
      if (toolCall.id) {
        state.id = toolCall.id;
      }
      if (toolCall.function && toolCall.function.name) {
        state.name = toolCall.function.name;
      }
      const argDelta = toolCall.function && toolCall.function.arguments ? toolCall.function.arguments : '';
      if (argDelta) {
        if (state.started) {
          sendSse(res, 'content_block_delta', {
            type: 'content_block_delta',
            index: state.blockIndex,
            delta: { type: 'input_json_delta', partial_json: argDelta }
          });
        } else {
          state.buffer += argDelta;
        }
      }
      if (state.name && !state.started) {
        startToolBlock(state);
      }
      toolStates.set(key, state);
    }
  }

  let buffer = '';
  proxyRes.on('data', chunk => {
    buffer += chunk.toString('utf8');
    const events = buffer.split(/\r?\n\r?\n/);
    buffer = events.pop() || '';
    for (const eventText of events) {
      const data = eventText
        .split(/\r?\n/)
        .filter(line => line.startsWith('data:'))
        .map(line => line.slice(5).trimStart())
        .join('\n');
      if (!data) {
        continue;
      }
      if (data.trim() === '[DONE]') {
        finishStream();
        return;
      }
      try {
        processChunk(JSON.parse(data));
      } catch (err) {
        sendSse(res, 'error', { type: 'error', error: { type: 'proxy_parse_error', message: err.message } });
      }
    }
  });
  proxyRes.on('end', finishStream);
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    sendJson(res, 200, { status: 'ok', provider, api_format: normalizedApiFormat });
    return;
  }

  const requestPath = req.url.split('?')[0];
  if (req.method !== 'POST' || requestPath !== '/v1/messages') {
    sendJson(res, 404, { error: 'not found' });
    return;
  }

  const chunks = [];
  req.on('data', chunk => chunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    let outgoingBody = body;
    let targetPath = upstreamPath('/v1/messages');
    let requestedModel = provider;
    let openAIRequest = null;

    if (normalizedApiFormat === 'openai-chat') {
      try {
        const anthropicRequest = JSON.parse(body.toString('utf8'));
        requestedModel = anthropicRequest.model || requestedModel;
        openAIRequest = anthropicToOpenAI(anthropicRequest);
        outgoingBody = Buffer.from(JSON.stringify(openAIRequest));
        targetPath = upstreamPath('/chat/completions');
      } catch (err) {
        sendJson(res, 400, { error: `invalid Anthropic request for OpenAI adapter: ${err.message}` });
        return;
      }
    }

    const options = {
      hostname: upstream.hostname,
      port: upstream.port || (upstream.protocol === 'https:' ? 443 : 80),
      path: targetPath,
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...authHeaders(),
        'anthropic-version': req.headers['anthropic-version'] || '2023-06-01',
        'anthropic-beta': req.headers['anthropic-beta'] || '',
        'content-length': outgoingBody.length
      }
    };

    if (normalizedApiFormat === 'openai-chat') {
      delete options.headers['anthropic-version'];
      delete options.headers['anthropic-beta'];
    }

    if (!options.headers['anthropic-beta']) {
      delete options.headers['anthropic-beta'];
    }

    const proxyReq = client.request(options, proxyRes => {
      if (normalizedApiFormat === 'openai-chat') {
        if (openAIRequest && openAIRequest.stream) {
          pipeOpenAIStreamToAnthropic(proxyRes, res, requestedModel);
          return;
        }

        const responseChunks = [];
        proxyRes.on('data', chunk => responseChunks.push(chunk));
        proxyRes.on('end', () => {
          const rawResponse = Buffer.concat(responseChunks);
          if ((proxyRes.statusCode || 500) >= 400) {
            res.writeHead(proxyRes.statusCode || 502, { ...proxyRes.headers, 'x-proxied-by': 'agent-router-proxy-server' });
            res.end(rawResponse);
            return;
          }

          try {
            const payload = JSON.parse(rawResponse.toString('utf8'));
            sendJson(res, proxyRes.statusCode || 200, openAIToAnthropic(payload, requestedModel));
          } catch (err) {
            sendJson(res, 502, { error: `failed to parse OpenAI-compatible response: ${err.message}` });
          }
        });
        return;
      }

      const headers = { ...proxyRes.headers, 'x-proxied-by': 'agent-router-proxy-server' };
      res.writeHead(proxyRes.statusCode || 502, headers);
      proxyRes.pipe(res);
    });

    proxyReq.on('error', err => {
      sendJson(res, 502, { error: `upstream error: ${err.message}` });
    });

    proxyReq.write(outgoingBody);
    proxyReq.end();
  });
});

server.listen(port, '127.0.0.1', () => {
  console.log(`agent-router-proxy listening on http://127.0.0.1:${port}`);
  console.log(`forwarding ${provider} (${normalizedApiFormat}) to ${baseUrl}`);
});
EOF_PROXY
  chmod 700 "$PROXY_BIN"

  umask 077
  cat > "$PROXY_ENV" <<EOF_ENV
AGENT_ROUTER_PROVIDER=${provider}
UPSTREAM_BASE_URL=${base_url}
UPSTREAM_API_KEY=${api_key}
UPSTREAM_AUTH_HEADER=${auth_header}
UPSTREAM_API_FORMAT=${api_format}
PORT=${port}
EOF_ENV
  chmod 600 "$PROXY_ENV"

cat > "$PROXY_LAUNCHER" <<EOF_LAUNCHER
#!/usr/bin/env bash
set -euo pipefail
export PATH="${USER_BIN_DIR}:\${PATH}"
set -a
. "${PROXY_ENV}"
set +a
exec node "${PROXY_BIN}" "\$@"
EOF_LAUNCHER
  chmod 700 "$PROXY_LAUNCHER"

  say "Installed local proxy: $PROXY_LAUNCHER"
}

write_proxy_service() {
  if ! need_cmd systemctl; then
    say "systemctl not found; skipping systemd user service."
    return
  fi

  mkdir -p "$SERVICE_DIR"
  cat > "$SERVICE_FILE" <<EOF_SERVICE
[Unit]
Description=agent-router provider proxy for Claude Code
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${PROXY_LAUNCHER}
Restart=always
RestartSec=5
Environment=HOME=${HOME}
Environment=PATH=${USER_BIN_DIR}:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
EOF_SERVICE

  systemctl --user daemon-reload
  systemctl --user enable --now agent-router-proxy.service
  say "Started user service: agent-router-proxy.service"
}

write_switcher_command() {
  mkdir -p "$USER_BIN_DIR"

  cat > "$SWITCHER_BIN" <<'EOF_SWITCHER'
#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
PROXY_DIR="${HOME}/.local/share/agent-router-proxy"
PROXY_BIN="${PROXY_DIR}/proxy.js"
PROXY_ENV="${PROXY_DIR}/proxy.env"
USER_BIN_DIR="${HOME}/.local/bin"
PROXY_LAUNCHER="${USER_BIN_DIR}/agent-router-proxy"
SERVICE_FILE="${HOME}/.config/systemd/user/agent-router-proxy.service"

say() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

read_from_tty() {
  local prompt="$1"
  local silent="${2:-0}"
  local value

  [ -r /dev/tty ] || die "interactive input requires a TTY. Run this command from a terminal."

  printf '%s' "$prompt" >/dev/tty
  if [ "$silent" = "1" ]; then
    IFS= read -r -s value </dev/tty || die "failed to read input from terminal."
    printf '\n' >/dev/tty
  else
    IFS= read -r value </dev/tty || die "failed to read input from terminal."
  fi

  value="$(printf '%s' "$value" | LC_ALL=C tr -d '\000-\037\177')"
  printf '%s' "$value"
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value
  value="$(read_from_tty "${prompt} [${default}]: ")"
  printf '%s' "${value:-$default}"
}

prompt_secret() {
  local prompt="$1"
  local value
  value="$(read_from_tty "${prompt}: " 1)"
  printf '%s' "$value"
}

prompt_required_secret() {
  local prompt="$1"
  local value

  while true; do
    value="$(prompt_secret "$prompt")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
    printf '%s\n' "Input was empty. Paste your key, then press Enter. The key will not be shown while typing." >/dev/tty
  done
}

prompt_required() {
  local prompt="$1"
  local value

  while true; do
    value="$(read_from_tty "${prompt}: ")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
    printf '%s\n' "Input was empty. Enter a value, then press Enter." >/dev/tty
  done
}

tty_say() {
  printf '%s\n' "$*" >/dev/tty
}

model_note() {
  local model="$1"

  if [ "$model" = "MiniMax-M2.7" ]; then
    printf '%s' "recommended"
  elif [ "$model" = "MiniMax-M2.7-highspeed" ]; then
    printf '%s' "recommended high-speed"
  elif [ "$model" = "deepseek-v4-pro[1m]" ]; then
    printf '%s' "recommended primary, 1M context"
  elif [ "$model" = "deepseek-v4-flash" ]; then
    printf '%s' "recommended small/fast"
  elif [ "$model" = "kimi-k2.5" ]; then
    printf '%s' "recommended for Claude Code"
  elif [ "$model" = "kimi-k2.6" ]; then
    printf '%s' "latest"
  elif [ "$model" = "kimi-k2-turbo-preview" ]; then
    printf '%s' "faster"
  elif [ "$model" = "kimi-k2-thinking" ]; then
    printf '%s' "thinking"
  fi
}

select_model_menu() {
  local provider="$1"
  local kind="$2"
  local default_model="$3"
  local prompt="$4"
  local models=()
  local model
  local note
  local i
  local choice
  local custom_choice
  local default_choice=1

  case "${provider}:${kind}" in
    minimax:primary|minimax:small)
      models=(
        "MiniMax-M2.7"
        "MiniMax-M2.7-highspeed"
        "MiniMax-M2.5"
        "MiniMax-M2.5-highspeed"
        "MiniMax-M2.1"
        "MiniMax-M2.1-highspeed"
        "MiniMax-M2"
      )
      ;;
    deepseek:primary)
      models=(
        "deepseek-v4-pro[1m]"
        "deepseek-v4-pro"
        "deepseek-v4-flash"
      )
      ;;
    deepseek:small)
      models=(
        "deepseek-v4-flash"
        "deepseek-v4-pro"
        "deepseek-v4-pro[1m]"
      )
      ;;
    kimi:primary|kimi:small)
      models=(
        "kimi-k2.5"
        "kimi-k2.6"
        "kimi-k2-turbo-preview"
        "kimi-k2-thinking"
        "kimi-k2-thinking-turbo"
        "kimi-k2-0905-preview"
        "kimi-k2-0711-preview"
      )
      ;;
    *)
      printf '%s' "$(prompt_default "$prompt" "$default_model")"
      return
      ;;
  esac

  custom_choice=$((${#models[@]} + 1))
  for i in "${!models[@]}"; do
    if [ "${models[$i]}" = "$default_model" ]; then
      default_choice=$((i + 1))
    fi
  done
  if ! printf '%s\n' "${models[@]}" | grep -Fxq "$default_model"; then
    default_choice="$custom_choice"
  fi

  tty_say "$prompt:"
  for i in "${!models[@]}"; do
    model="${models[$i]}"
    note="$(model_note "$model")"
    if [ -n "$note" ]; then
      tty_say "  $((i + 1))) ${model} (${note})"
    else
      tty_say "  $((i + 1))) ${model}"
    fi
  done
  tty_say "  ${custom_choice}) Custom model name"

  choice="$(prompt_default 'Model choice' "$default_choice")"
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    if [ "$choice" -ge 1 ] && [ "$choice" -le "${#models[@]}" ]; then
      printf '%s' "${models[$((choice - 1))]}"
      return
    fi
    if [ "$choice" -eq "$custom_choice" ]; then
      printf '%s' "$(prompt_default 'Custom model name' "$default_model")"
      return
    fi
  fi

  printf '%s' "$choice"
}

normalize_openai_base_url() {
  local base_url="${1:-http://127.0.0.1:8000/v1}"
  base_url="${base_url%/}"
  case "$base_url" in
    */v1) printf '%s' "$base_url" ;;
    *) printf '%s' "${base_url}/v1" ;;
  esac
}

discover_openai_models() {
  local base_url="$1"
  local models_url="${base_url%/}/models"

  need_cmd curl || return 1
  need_cmd node || return 1

  curl -fsS --connect-timeout 5 --max-time 10 "$models_url" 2>/dev/null | node -e '
const chunks = [];
process.stdin.on("data", chunk => chunks.push(chunk));
process.stdin.on("end", () => {
  const payload = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  const models = Array.isArray(payload.data) ? payload.data : [];
  for (const model of models) {
    if (model && typeof model.id === "string" && model.id.length > 0) {
      console.log(model.id);
    }
  }
});
' 2>/dev/null
}

select_discovered_model_menu() {
  local prompt="$1"
  shift
  local models=("$@")
  local i
  local choice
  local custom_choice
  local default_choice=1

  custom_choice=$((${#models[@]} + 1))

  tty_say "$prompt:"
  for i in "${!models[@]}"; do
    tty_say "  $((i + 1))) ${models[$i]}"
  done
  tty_say "  ${custom_choice}) Custom model name"

  choice="$(prompt_default 'Model choice' "$default_choice")"
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    if [ "$choice" -ge 1 ] && [ "$choice" -le "${#models[@]}" ]; then
      printf '%s' "${models[$((choice - 1))]}"
      return
    fi
    if [ "$choice" -eq "$custom_choice" ]; then
      printf '%s' "$(prompt_required 'Custom model name')"
      return
    fi
  fi

  printf '%s' "$choice"
}

select_openai_model_from_base_url() {
  local base_url="$1"
  local fallback_model="${2:-}"
  local model_lines
  local models=()
  local model

  tty_say "Checking models from ${base_url%/}/models..."
  if model_lines="$(discover_openai_models "$base_url")" && [ -n "$model_lines" ]; then
    while IFS= read -r model; do
      [ -n "$model" ] && models+=("$model")
    done <<< "$model_lines"

    if [ "${#models[@]}" -gt 0 ]; then
      select_discovered_model_menu "Discovered models" "${models[@]}"
      return
    fi
  fi

  tty_say "Could not discover models from ${base_url%/}/models."
  if [ -n "$fallback_model" ]; then
    printf '%s' "$(prompt_default 'Model name' "$fallback_model")"
  else
    printf '%s' "$(prompt_required 'Model name')"
  fi
}

backup_if_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    local backup="${file}.backup.$(date +%s)"
    cp "$file" "$backup"
    say "Backed up existing file: $backup"
  fi
}

settings_env_value() {
  local key="$1"
  [ -f "$SETTINGS_FILE" ] || return 1
  awk -v key="\"${key}\"" '
    index($0, key) {
      sub(/^[^:]*:[[:space:]]*"/, "")
      sub(/",?[[:space:]]*$/, "")
      print
      exit
    }
  ' "$SETTINGS_FILE"
}

env_file_value() {
  local file="$1"
  local key="$2"
  [ -f "$file" ] || return 1
  sed -n "s/^${key}=//p" "$file" | head -n 1
}

current_mode() {
  local base_url
  base_url="$(settings_env_value ANTHROPIC_BASE_URL || true)"
  case "$base_url" in
    http://127.0.0.1:*|http://localhost:*) printf '%s' "2" ;;
    *) printf '%s' "1" ;;
  esac
}

current_provider() {
  local base_url
  base_url="$(settings_env_value ANTHROPIC_BASE_URL || true)"
  case "$base_url" in
    http://127.0.0.1:*|http://localhost:*)
      local proxy_provider
      proxy_provider="$(env_file_value "$PROXY_ENV" AGENT_ROUTER_PROVIDER || true)"
      case "$proxy_provider" in
        qwen) printf '%s' "vllm" ;;
        *) printf '%s' "$proxy_provider" ;;
      esac
      ;;
    *deepseek*) printf '%s' "deepseek" ;;
    *moonshot*|*kimi*) printf '%s' "kimi" ;;
    *vllm*) printf '%s' "vllm" ;;
    *minimax*|*minimaxi*) printf '%s' "minimax" ;;
    *) return 1 ;;
  esac
}

current_api_key() {
  if [ "$(current_mode)" = "2" ]; then
    env_file_value "$PROXY_ENV" UPSTREAM_API_KEY || true
  else
    settings_env_value ANTHROPIC_AUTH_TOKEN || true
  fi
}

current_proxy_port() {
  local base_url
  base_url="$(settings_env_value ANTHROPIC_BASE_URL || true)"
  case "$base_url" in
    http://127.0.0.1:*|http://localhost:*)
      base_url="${base_url#http://127.0.0.1:}"
      base_url="${base_url#http://localhost:}"
      printf '%s' "${base_url%%/*}"
      ;;
    *) printf '%s' "8080" ;;
  esac
}

write_direct_settings() {
  local base_url="$1"
  local api_key="$2"
  local model="$3"
  local small_model="${4:-$3}"
  local effort_level="${5:-}"
  local large_model="${6:-$3}"
  local subagent_model="${7:-$small_model}"
  local disable_nonstreaming_fallback="${8:-}"
  local enable_tool_search="${9:-}"
  local extra_env_lines=""

  if [ -n "$disable_nonstreaming_fallback" ]; then
    extra_env_lines="$(printf '%s,\n    "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK": "%s"' "$extra_env_lines" "$disable_nonstreaming_fallback")"
  fi
  if [ -n "$effort_level" ]; then
    extra_env_lines="$(printf '%s,\n    "CLAUDE_CODE_EFFORT_LEVEL": "%s"' "$extra_env_lines" "$effort_level")"
  fi
  if [ -n "$enable_tool_search" ]; then
    extra_env_lines="$(printf '%s,\n    "ENABLE_TOOL_SEARCH": "%s"' "$extra_env_lines" "$enable_tool_search")"
  fi

  mkdir -p "$CLAUDE_DIR"
  chmod 700 "$CLAUDE_DIR"
  backup_if_exists "$SETTINGS_FILE"

  umask 077
  cat > "$SETTINGS_FILE" <<EOF_SETTINGS
{
  "env": {
    "ANTHROPIC_BASE_URL": "${base_url}",
    "ANTHROPIC_AUTH_TOKEN": "${api_key}",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "ANTHROPIC_MODEL": "${model}",
    "ANTHROPIC_SMALL_FAST_MODEL": "${small_model}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${large_model}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${large_model}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${small_model}",
    "CLAUDE_CODE_SUBAGENT_MODEL": "${subagent_model}"${extra_env_lines}
  }
}
EOF_SETTINGS
  chmod 600 "$SETTINGS_FILE"
  say "Wrote Claude Code settings: $SETTINGS_FILE"
}

write_proxy_files() {
  local provider="$1"
  local base_url="$2"
  local api_key="$3"
  local port="$4"
  local auth_header="$5"
  local api_format="${6:-anthropic}"

  mkdir -p "$PROXY_DIR" "$USER_BIN_DIR"
  chmod 700 "$PROXY_DIR"

  cat > "$PROXY_BIN" <<'EOF_PROXY'
#!/usr/bin/env node
const http = require('http');
const https = require('https');
const { URL } = require('url');

const port = Number(process.env.PORT || '8080');
const provider = process.env.AGENT_ROUTER_PROVIDER || 'minimax';
const apiKey = process.env.UPSTREAM_API_KEY || process.env.MINIMAX_API_KEY;
const baseUrl = process.env.UPSTREAM_BASE_URL || process.env.MINIMAX_BASE_URL || 'https://api.minimaxi.com/anthropic';
const authHeader = (process.env.UPSTREAM_AUTH_HEADER || (provider === 'deepseek' ? 'x-api-key' : 'authorization')).toLowerCase();
const apiFormat = (process.env.UPSTREAM_API_FORMAT || 'anthropic').toLowerCase();
const normalizedApiFormat = apiFormat === 'openai' ? 'openai-chat' : apiFormat;
const maxTokensLimit = Number(process.env.UPSTREAM_MAX_TOKENS || (provider === 'vllm' ? '4096' : '0'));

if (!apiKey) {
  console.error('UPSTREAM_API_KEY is required');
  process.exit(1);
}

if (!['authorization', 'bearer', 'x-api-key'].includes(authHeader)) {
  console.error(`Unsupported UPSTREAM_AUTH_HEADER: ${authHeader}`);
  process.exit(1);
}

if (!['anthropic', 'openai-chat'].includes(normalizedApiFormat)) {
  console.error(`Unsupported UPSTREAM_API_FORMAT: ${apiFormat}`);
  process.exit(1);
}

const upstream = new URL(baseUrl.replace(/\/+$/, ''));
const client = upstream.protocol === 'https:' ? https : http;

function sendJson(res, status, payload) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(payload));
}

function authHeaders() {
  if (authHeader === 'x-api-key') {
    return { 'x-api-key': apiKey };
  }
  return { authorization: `Bearer ${apiKey}` };
}

function upstreamPath(suffix) {
  const basePath = upstream.pathname.replace(/\/+$/, '');
  return `${basePath}/${suffix.replace(/^\/+/, '')}`;
}

function textFromContent(content) {
  if (content == null) {
    return '';
  }
  if (typeof content === 'string') {
    return content;
  }
  if (!Array.isArray(content)) {
    if (typeof content.text === 'string') {
      return content.text;
    }
    return JSON.stringify(content);
  }

  return content
    .map(block => {
      if (!block) {
        return '';
      }
      if (typeof block === 'string') {
        return block;
      }
      if (block.type === 'text' && typeof block.text === 'string') {
        return block.text;
      }
      if (block.type === 'tool_result') {
        return textFromContent(block.content);
      }
      if (typeof block.text === 'string') {
        return block.text;
      }
      return '';
    })
    .filter(Boolean)
    .join('\n');
}

function parseJsonObject(value) {
  if (!value) {
    return {};
  }
  try {
    const parsed = JSON.parse(value);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed;
    }
    return { value: parsed };
  } catch {
    return {};
  }
}

function finishReasonToStopReason(reason) {
  if (reason === 'length') {
    return 'max_tokens';
  }
  if (reason === 'tool_calls' || reason === 'function_call') {
    return 'tool_use';
  }
  if (reason === 'stop') {
    return 'end_turn';
  }
  return reason || 'end_turn';
}

function convertToolChoice(choice) {
  if (!choice) {
    return undefined;
  }
  if (typeof choice === 'string') {
    return choice;
  }
  if (choice.type === 'auto') {
    return 'auto';
  }
  if (choice.type === 'any') {
    return 'required';
  }
  if (choice.type === 'tool' && choice.name) {
    return { type: 'function', function: { name: choice.name } };
  }
  return undefined;
}

function anthropicToOpenAI(body) {
  const messages = [];
  const systemText = textFromContent(body.system);
  if (systemText) {
    messages.push({ role: 'system', content: systemText });
  }

  for (const message of body.messages || []) {
    const role = message.role === 'assistant' ? 'assistant' : 'user';
    const content = message.content;

    if (role === 'assistant' && Array.isArray(content)) {
      const textParts = [];
      const toolCalls = [];
      for (const block of content) {
        if (!block) {
          continue;
        }
        if (block.type === 'tool_use') {
          toolCalls.push({
            id: block.id || `call_${toolCalls.length}`,
            type: 'function',
            function: {
              name: block.name || 'tool',
              arguments: JSON.stringify(block.input || {})
            }
          });
        } else {
          const text = textFromContent([block]);
          if (text) {
            textParts.push(text);
          }
        }
      }
      const openAIMessage = { role: 'assistant', content: textParts.join('\n') || null };
      if (toolCalls.length > 0) {
        openAIMessage.tool_calls = toolCalls;
      }
      messages.push(openAIMessage);
      continue;
    }

    if (role === 'user' && Array.isArray(content)) {
      const textParts = [];
      const toolResults = [];
      for (const block of content) {
        if (block && block.type === 'tool_result') {
          toolResults.push({
            role: 'tool',
            tool_call_id: block.tool_use_id,
            content: textFromContent(block.content)
          });
        } else {
          const text = textFromContent([block]);
          if (text) {
            textParts.push(text);
          }
        }
      }
      if (textParts.length > 0) {
        messages.push({ role: 'user', content: textParts.join('\n') });
      }
      for (const toolResult of toolResults) {
        messages.push(toolResult);
      }
      if (textParts.length === 0 && toolResults.length === 0) {
        messages.push({ role: 'user', content: '' });
      }
      continue;
    }

    messages.push({ role, content: textFromContent(content) });
  }

  const openAIRequest = {
    model: body.model,
    messages,
    stream: !!body.stream
  };

  if (typeof body.max_tokens === 'number') {
    openAIRequest.max_tokens = maxTokensLimit > 0 ? Math.min(body.max_tokens, maxTokensLimit) : body.max_tokens;
  }
  if (typeof body.temperature === 'number') {
    openAIRequest.temperature = body.temperature;
  }
  if (typeof body.top_p === 'number') {
    openAIRequest.top_p = body.top_p;
  }
  if (Array.isArray(body.stop_sequences) && body.stop_sequences.length > 0) {
    openAIRequest.stop = body.stop_sequences;
  }
  if (Array.isArray(body.tools) && body.tools.length > 0) {
    openAIRequest.tools = body.tools.map(tool => ({
      type: 'function',
      function: {
        name: tool.name,
        description: tool.description || '',
        parameters: tool.input_schema || { type: 'object', properties: {} }
      }
    }));
    const toolChoice = convertToolChoice(body.tool_choice);
    if (toolChoice) {
      openAIRequest.tool_choice = toolChoice;
    }
  }

  return openAIRequest;
}

function openAIToAnthropic(payload, requestedModel) {
  const choice = (payload.choices || [])[0] || {};
  const message = choice.message || {};
  const content = [];

  if (message.content) {
    content.push({ type: 'text', text: Array.isArray(message.content) ? textFromContent(message.content) : String(message.content) });
  }

  for (const call of message.tool_calls || []) {
    content.push({
      type: 'tool_use',
      id: call.id || `call_${content.length}`,
      name: (call.function && call.function.name) || 'tool',
      input: parseJsonObject(call.function && call.function.arguments)
    });
  }

  if (content.length === 0) {
    content.push({ type: 'text', text: '' });
  }

  return {
    id: payload.id || `msg_${Date.now()}`,
    type: 'message',
    role: 'assistant',
    model: payload.model || requestedModel,
    content,
    stop_reason: finishReasonToStopReason(choice.finish_reason),
    stop_sequence: null,
    usage: {
      input_tokens: (payload.usage && payload.usage.prompt_tokens) || 0,
      output_tokens: (payload.usage && payload.usage.completion_tokens) || 0
    }
  };
}

function sendSse(res, event, data) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

function pipeOpenAIStreamToAnthropic(proxyRes, res, requestedModel) {
  if ((proxyRes.statusCode || 500) >= 400) {
    res.writeHead(proxyRes.statusCode || 502, { ...proxyRes.headers, 'x-proxied-by': 'agent-router-proxy-server' });
    proxyRes.pipe(res);
    return;
  }

  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache',
    connection: 'keep-alive',
    'x-proxied-by': 'agent-router-proxy-server'
  });

  const messageId = `msg_${Date.now()}`;
  let nextBlockIndex = 0;
  let currentTextIndex = null;
  let stopReason = 'end_turn';
  let usage = { output_tokens: 0 };
  let finished = false;
  const toolStates = new Map();

  sendSse(res, 'message_start', {
    type: 'message_start',
    message: {
      id: messageId,
      type: 'message',
      role: 'assistant',
      model: requestedModel,
      content: [],
      stop_reason: null,
      stop_sequence: null,
      usage: { input_tokens: 0, output_tokens: 0 }
    }
  });

  function closeTextBlock() {
    if (currentTextIndex != null) {
      sendSse(res, 'content_block_stop', { type: 'content_block_stop', index: currentTextIndex });
      currentTextIndex = null;
    }
  }

  function writeTextDelta(text) {
    if (currentTextIndex == null) {
      currentTextIndex = nextBlockIndex++;
      sendSse(res, 'content_block_start', {
        type: 'content_block_start',
        index: currentTextIndex,
        content_block: { type: 'text', text: '' }
      });
    }
    sendSse(res, 'content_block_delta', {
      type: 'content_block_delta',
      index: currentTextIndex,
      delta: { type: 'text_delta', text }
    });
  }

  function startToolBlock(state) {
    if (state.started) {
      return;
    }
    closeTextBlock();
    state.blockIndex = nextBlockIndex++;
    state.started = true;
    sendSse(res, 'content_block_start', {
      type: 'content_block_start',
      index: state.blockIndex,
      content_block: {
        type: 'tool_use',
        id: state.id || `call_${state.key}`,
        name: state.name || 'tool',
        input: {}
      }
    });
    if (state.buffer) {
      sendSse(res, 'content_block_delta', {
        type: 'content_block_delta',
        index: state.blockIndex,
        delta: { type: 'input_json_delta', partial_json: state.buffer }
      });
      state.buffer = '';
    }
  }

  function finishStream() {
    if (finished) {
      return;
    }
    finished = true;

    if (nextBlockIndex === 0) {
      writeTextDelta('');
    }
    closeTextBlock();
    for (const state of toolStates.values()) {
      startToolBlock(state);
      sendSse(res, 'content_block_stop', { type: 'content_block_stop', index: state.blockIndex });
    }
    sendSse(res, 'message_delta', {
      type: 'message_delta',
      delta: { stop_reason: stopReason, stop_sequence: null },
      usage
    });
    sendSse(res, 'message_stop', { type: 'message_stop' });
    res.end();
  }

  function processChunk(payload) {
    const choice = (payload.choices || [])[0] || {};
    const delta = choice.delta || {};
    if (payload.usage) {
      usage = { output_tokens: payload.usage.completion_tokens || 0 };
    }
    if (choice.finish_reason) {
      stopReason = finishReasonToStopReason(choice.finish_reason);
    }
    if (delta.content) {
      writeTextDelta(delta.content);
    }
    for (const toolCall of delta.tool_calls || []) {
      const key = toolCall.index == null ? toolStates.size : toolCall.index;
      const state = toolStates.get(key) || { key, id: '', name: '', buffer: '', started: false, blockIndex: null };
      if (toolCall.id) {
        state.id = toolCall.id;
      }
      if (toolCall.function && toolCall.function.name) {
        state.name = toolCall.function.name;
      }
      const argDelta = toolCall.function && toolCall.function.arguments ? toolCall.function.arguments : '';
      if (argDelta) {
        if (state.started) {
          sendSse(res, 'content_block_delta', {
            type: 'content_block_delta',
            index: state.blockIndex,
            delta: { type: 'input_json_delta', partial_json: argDelta }
          });
        } else {
          state.buffer += argDelta;
        }
      }
      if (state.name && !state.started) {
        startToolBlock(state);
      }
      toolStates.set(key, state);
    }
  }

  let buffer = '';
  proxyRes.on('data', chunk => {
    buffer += chunk.toString('utf8');
    const events = buffer.split(/\r?\n\r?\n/);
    buffer = events.pop() || '';
    for (const eventText of events) {
      const data = eventText
        .split(/\r?\n/)
        .filter(line => line.startsWith('data:'))
        .map(line => line.slice(5).trimStart())
        .join('\n');
      if (!data) {
        continue;
      }
      if (data.trim() === '[DONE]') {
        finishStream();
        return;
      }
      try {
        processChunk(JSON.parse(data));
      } catch (err) {
        sendSse(res, 'error', { type: 'error', error: { type: 'proxy_parse_error', message: err.message } });
      }
    }
  });
  proxyRes.on('end', finishStream);
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    sendJson(res, 200, { status: 'ok', provider, api_format: normalizedApiFormat });
    return;
  }

  const requestPath = req.url.split('?')[0];
  if (req.method !== 'POST' || requestPath !== '/v1/messages') {
    sendJson(res, 404, { error: 'not found' });
    return;
  }

  const chunks = [];
  req.on('data', chunk => chunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    let outgoingBody = body;
    let targetPath = upstreamPath('/v1/messages');
    let requestedModel = provider;
    let openAIRequest = null;

    if (normalizedApiFormat === 'openai-chat') {
      try {
        const anthropicRequest = JSON.parse(body.toString('utf8'));
        requestedModel = anthropicRequest.model || requestedModel;
        openAIRequest = anthropicToOpenAI(anthropicRequest);
        outgoingBody = Buffer.from(JSON.stringify(openAIRequest));
        targetPath = upstreamPath('/chat/completions');
      } catch (err) {
        sendJson(res, 400, { error: `invalid Anthropic request for OpenAI adapter: ${err.message}` });
        return;
      }
    }

    const options = {
      hostname: upstream.hostname,
      port: upstream.port || (upstream.protocol === 'https:' ? 443 : 80),
      path: targetPath,
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...authHeaders(),
        'anthropic-version': req.headers['anthropic-version'] || '2023-06-01',
        'anthropic-beta': req.headers['anthropic-beta'] || '',
        'content-length': outgoingBody.length
      }
    };

    if (normalizedApiFormat === 'openai-chat') {
      delete options.headers['anthropic-version'];
      delete options.headers['anthropic-beta'];
    }

    if (!options.headers['anthropic-beta']) {
      delete options.headers['anthropic-beta'];
    }

    const proxyReq = client.request(options, proxyRes => {
      if (normalizedApiFormat === 'openai-chat') {
        if (openAIRequest && openAIRequest.stream) {
          pipeOpenAIStreamToAnthropic(proxyRes, res, requestedModel);
          return;
        }

        const responseChunks = [];
        proxyRes.on('data', chunk => responseChunks.push(chunk));
        proxyRes.on('end', () => {
          const rawResponse = Buffer.concat(responseChunks);
          if ((proxyRes.statusCode || 500) >= 400) {
            res.writeHead(proxyRes.statusCode || 502, { ...proxyRes.headers, 'x-proxied-by': 'agent-router-proxy-server' });
            res.end(rawResponse);
            return;
          }

          try {
            const payload = JSON.parse(rawResponse.toString('utf8'));
            sendJson(res, proxyRes.statusCode || 200, openAIToAnthropic(payload, requestedModel));
          } catch (err) {
            sendJson(res, 502, { error: `failed to parse OpenAI-compatible response: ${err.message}` });
          }
        });
        return;
      }

      const headers = { ...proxyRes.headers, 'x-proxied-by': 'agent-router-proxy-server' };
      res.writeHead(proxyRes.statusCode || 502, headers);
      proxyRes.pipe(res);
    });

    proxyReq.on('error', err => {
      sendJson(res, 502, { error: `upstream error: ${err.message}` });
    });

    proxyReq.write(outgoingBody);
    proxyReq.end();
  });
});

server.listen(port, '127.0.0.1', () => {
  console.log(`agent-router-proxy listening on http://127.0.0.1:${port}`);
  console.log(`forwarding ${provider} (${normalizedApiFormat}) to ${baseUrl}`);
});
EOF_PROXY
  chmod 700 "$PROXY_BIN"

  umask 077
  cat > "$PROXY_ENV" <<EOF_ENV
AGENT_ROUTER_PROVIDER=${provider}
UPSTREAM_BASE_URL=${base_url}
UPSTREAM_API_KEY=${api_key}
UPSTREAM_AUTH_HEADER=${auth_header}
UPSTREAM_API_FORMAT=${api_format}
PORT=${port}
EOF_ENV
  chmod 600 "$PROXY_ENV"

cat > "$PROXY_LAUNCHER" <<EOF_LAUNCHER
#!/usr/bin/env bash
set -euo pipefail
export PATH="${USER_BIN_DIR}:\${PATH}"
set -a
. "${PROXY_ENV}"
set +a
exec node "${PROXY_BIN}" "\$@"
EOF_LAUNCHER
  chmod 700 "$PROXY_LAUNCHER"
}

restart_proxy_service_if_running() {
  if ! need_cmd systemctl; then
    say "Proxy can be started manually with: $PROXY_LAUNCHER"
    return
  fi

  if systemctl --user is-active --quiet agent-router-proxy.service; then
    systemctl --user restart agent-router-proxy.service
    say "Restarted user service: agent-router-proxy.service"
    return
  fi

  if [ -f "$SERVICE_FILE" ]; then
    say "Proxy service exists but is not running. Start it with:"
    say "  systemctl --user start agent-router-proxy.service"
  else
    say "Proxy can be started manually with: $PROXY_LAUNCHER"
  fi
}

main() {
  say "agent-router provider switcher"
  say

  local current_base_url
  local current_model
  local existing_provider
  current_base_url="$(settings_env_value ANTHROPIC_BASE_URL || true)"
  current_model="$(settings_env_value ANTHROPIC_MODEL || true)"
  existing_provider="$(current_provider || true)"

  say "Current provider: ${existing_provider:-not configured}"
  say "Current base URL: ${current_base_url:-not configured}"
  say "Current model: ${current_model:-not configured}"
  say

  say "Choose upstream provider:"
  say "  1) MiniMax"
  say "  2) DeepSeek V4"
  say "  3) Kimi"
  say "  4) vLLM (OpenAI-compatible)"
  local provider_choice
  provider_choice="$(prompt_default 'Provider choice' '1')"

  local provider
  local provider_label
  local base_url
  local auth_header
  local default_model
  local default_small_model
  local effort_level=""
  local disable_nonstreaming_fallback=""
  local enable_tool_search=""
  local api_format="anthropic"

  case "$provider_choice" in
    2)
      provider="deepseek"
      provider_label="DeepSeek"
      base_url="https://api.deepseek.com/anthropic"
      auth_header="x-api-key"
      default_model="deepseek-v4-pro[1m]"
      default_small_model="deepseek-v4-flash"
      effort_level="max"
      disable_nonstreaming_fallback="1"
      say "DeepSeek Anthropic endpoint: ${base_url}"
      ;;
    3)
      provider="kimi"
      provider_label="Kimi"
      base_url="https://api.moonshot.ai/anthropic"
      auth_header="authorization"
      default_model="kimi-k2.5"
      default_small_model="$default_model"
      enable_tool_search="false"
      say "Kimi Anthropic endpoint: ${base_url}"
      ;;
    4)
      provider="vllm"
      provider_label="vLLM"
      auth_header="authorization"
      default_model=""
      default_small_model="$default_model"
      api_format="openai-chat"
      local default_base_url="http://127.0.0.1:8000/v1"
      if [ "$existing_provider" = "$provider" ]; then
        local existing_upstream_base_url
        existing_upstream_base_url="$(env_file_value "$PROXY_ENV" UPSTREAM_BASE_URL || true)"
        [ -n "$existing_upstream_base_url" ] && default_base_url="$existing_upstream_base_url"
      fi
      base_url="$(normalize_openai_base_url "$(prompt_default 'OpenAI-compatible base URL' "$default_base_url")")"
      say "vLLM OpenAI-compatible endpoint: ${base_url}"
      ;;
    *)
      provider="minimax"
      provider_label="MiniMax"
      auth_header="authorization"
      default_model="MiniMax-M2.7"
      say "Choose MiniMax endpoint:"
      say "  1) China mainland: https://api.minimaxi.com/anthropic"
      say "  2) International:  https://api.minimax.io/anthropic"
      local endpoint_choice
      endpoint_choice="$(prompt_default 'Endpoint choice' '1')"
      case "$endpoint_choice" in
        2) base_url="https://api.minimax.io/anthropic" ;;
        *) base_url="https://api.minimaxi.com/anthropic" ;;
      esac
      default_small_model="$default_model"
      ;;
  esac

  if [ "$provider" = "$existing_provider" ]; then
    local existing_model
    local existing_small_model
    existing_model="$(settings_env_value ANTHROPIC_MODEL || true)"
    existing_small_model="$(settings_env_value ANTHROPIC_SMALL_FAST_MODEL || true)"
    [ -n "$existing_model" ] && default_model="$existing_model"
    [ -n "$existing_small_model" ] && default_small_model="$existing_small_model"
  fi

  local model
  if [ "$provider" = "vllm" ]; then
    model="$(select_openai_model_from_base_url "$base_url" "$default_model")"
  else
    model="$(select_model_menu "$provider" "primary" "$default_model" "Primary model")"
  fi

  local small_model
  if [ "$provider" = "vllm" ]; then
    small_model="$model"
  elif [ "$provider" = "deepseek" ]; then
    small_model="$(select_model_menu "$provider" "small" "$default_small_model" "Small/haiku model")"
  else
    small_model="$model"
  fi

  local large_model="$model"
  local subagent_model="$small_model"

  local api_key
  local existing_api_key=""
  if [ "$provider" = "$existing_provider" ]; then
    existing_api_key="$(current_api_key || true)"
  fi

  if [ "$provider" = "vllm" ]; then
    if [ -n "$existing_api_key" ]; then
      say "${provider_label} API Key input is hidden. Leave empty to keep the current stored key."
      api_key="$(prompt_secret "${provider_label} API Key")"
      api_key="${api_key:-$existing_api_key}"
    else
      say "${provider_label} API Key input is hidden. Leave empty to use EMPTY for a local vLLM server."
      api_key="$(prompt_secret "${provider_label} API Key")"
      api_key="${api_key:-EMPTY}"
    fi
  elif [ -n "$existing_api_key" ]; then
    say "${provider_label} API Key input is hidden. Leave empty to keep the current stored key."
    api_key="$(prompt_secret "${provider_label} API Key")"
    api_key="${api_key:-$existing_api_key}"
  else
    say "${provider_label} API Key input is hidden. Paste the key, then press Enter."
    api_key="$(prompt_required_secret "${provider_label} API Key")"
  fi

  if [ "$api_format" = "openai-chat" ]; then
    say
    say "${provider_label} uses an OpenAI-compatible API. Claude Code will use the local Anthropic adapter proxy."
    local port
    port="$(prompt_default 'Local proxy port' "$(current_proxy_port)")"
    write_proxy_files "$provider" "$base_url" "$api_key" "$port" "$auth_header" "$api_format"
    write_direct_settings "http://127.0.0.1:${port}" "not-used-by-local-proxy" "$model" "$small_model" "$effort_level" "$large_model" "$subagent_model" "$disable_nonstreaming_fallback" "$enable_tool_search"
    restart_proxy_service_if_running
  else
    say
    say "Choose Claude Code connection mode:"
    say "  1) Direct mode: Claude Code calls ${provider_label} directly."
    say "  2) Local proxy mode: Claude Code calls a 127.0.0.1 proxy."
    local mode
    mode="$(prompt_default 'Mode' "$(current_mode)")"

    if [ "$mode" = "2" ]; then
      local port
      port="$(prompt_default 'Local proxy port' "$(current_proxy_port)")"
      write_proxy_files "$provider" "$base_url" "$api_key" "$port" "$auth_header" "$api_format"
      write_direct_settings "http://127.0.0.1:${port}" "not-used-by-local-proxy" "$model" "$small_model" "$effort_level" "$large_model" "$subagent_model" "$disable_nonstreaming_fallback" "$enable_tool_search"
      restart_proxy_service_if_running
    else
      write_direct_settings "$base_url" "$api_key" "$model" "$small_model" "$effort_level" "$large_model" "$subagent_model" "$disable_nonstreaming_fallback" "$enable_tool_search"
    fi
  fi

  say
  say "Done. Open Claude Code again for the new provider/model to take effect."
}

main "$@"
EOF_SWITCHER

  chmod 700 "$SWITCHER_BIN"
  ln -sf "$SWITCHER_BIN" "$SWITCHER_ALIAS"
  say "Installed provider switcher: $SWITCHER_BIN"
  say "Also available as: $SWITCHER_ALIAS"
}

main() {
  say "agent-router: Claude Code provider headless installer"
  say

  install_claude_code

  say
  say "Choose upstream provider:"
  say "  1) MiniMax"
  say "  2) DeepSeek V4"
  say "  3) Kimi"
  say "  4) vLLM (OpenAI-compatible)"
  local provider_choice
  provider_choice="$(prompt_default 'Provider choice' '1')"

  local provider
  local provider_label
  local base_url
  local auth_header
  local default_model
  local default_small_model
  local effort_level=""
  local disable_nonstreaming_fallback=""
  local enable_tool_search=""
  local api_format="anthropic"

  case "$provider_choice" in
    2)
      provider="deepseek"
      provider_label="DeepSeek"
      base_url="https://api.deepseek.com/anthropic"
      auth_header="x-api-key"
      default_model="deepseek-v4-pro[1m]"
      default_small_model="deepseek-v4-flash"
      effort_level="max"
      disable_nonstreaming_fallback="1"
      say "DeepSeek Anthropic endpoint: ${base_url}"
      ;;
    3)
      provider="kimi"
      provider_label="Kimi"
      base_url="https://api.moonshot.ai/anthropic"
      auth_header="authorization"
      default_model="kimi-k2.5"
      default_small_model="$default_model"
      enable_tool_search="false"
      say "Kimi Anthropic endpoint: ${base_url}"
      ;;
    4)
      provider="vllm"
      provider_label="vLLM"
      auth_header="authorization"
      default_model=""
      default_small_model="$default_model"
      api_format="openai-chat"
      base_url="$(normalize_openai_base_url "$(prompt_default 'OpenAI-compatible base URL' 'http://127.0.0.1:8000/v1')")"
      say "vLLM OpenAI-compatible endpoint: ${base_url}"
      ;;
    *)
      provider="minimax"
      provider_label="MiniMax"
      auth_header="authorization"
      default_model="MiniMax-M2.7"
      say "Choose MiniMax endpoint:"
      say "  1) China mainland: https://api.minimaxi.com/anthropic"
      say "  2) International:  https://api.minimax.io/anthropic"
      local endpoint_choice
      endpoint_choice="$(prompt_default 'Endpoint choice' '1')"
      case "$endpoint_choice" in
        2) base_url="https://api.minimax.io/anthropic" ;;
        *) base_url="https://api.minimaxi.com/anthropic" ;;
      esac
      default_small_model="$default_model"
      ;;
  esac

  local model
  if [ "$provider" = "vllm" ]; then
    model="$(select_openai_model_from_base_url "$base_url" "$default_model")"
  else
    model="$(select_model_menu "$provider" "primary" "$default_model" "Primary model")"
  fi

  local small_model
  if [ "$provider" = "vllm" ]; then
    small_model="$model"
  elif [ "$provider" = "deepseek" ]; then
    small_model="$(select_model_menu "$provider" "small" "$default_small_model" "Small/haiku model")"
  else
    small_model="$model"
  fi

  local large_model="$model"
  local subagent_model="$small_model"

  local api_key
  if [ "$provider" = "vllm" ]; then
    say "${provider_label} API Key input is hidden. Leave empty to use EMPTY for a local vLLM server."
    api_key="$(prompt_secret "${provider_label} API Key")"
    api_key="${api_key:-EMPTY}"
  else
    say "${provider_label} API Key input is hidden. Paste the key, then press Enter."
    api_key="$(prompt_required_secret "${provider_label} API Key")"
  fi

  if [ "$api_format" = "openai-chat" ]; then
    say
    say "${provider_label} uses an OpenAI-compatible API. Claude Code will use the local Anthropic adapter proxy."
    local port
    port="$(prompt_default 'Local proxy port' '8080')"
    write_proxy_files "$provider" "$base_url" "$api_key" "$port" "$auth_header" "$api_format"
    write_direct_settings "http://127.0.0.1:${port}" "not-used-by-local-proxy" "$model" "$small_model" "$effort_level" "$large_model" "$subagent_model" "$disable_nonstreaming_fallback" "$enable_tool_search"

    if confirm 'Start proxy as a systemd user service now?' 'Y'; then
      write_proxy_service
    else
      say "Proxy can be started manually with: $PROXY_LAUNCHER"
    fi
  else
    say
    say "Choose Claude Code connection mode:"
    say "  1) Direct mode: Claude Code calls ${provider_label} directly. Recommended."
    say "  2) Local proxy mode: install a local 127.0.0.1 proxy, then Claude Code calls the proxy."
    local mode
    mode="$(prompt_default 'Mode' '1')"

    if [ "$mode" = "2" ]; then
      local port
      port="$(prompt_default 'Local proxy port' '8080')"
      write_proxy_files "$provider" "$base_url" "$api_key" "$port" "$auth_header" "$api_format"
      write_direct_settings "http://127.0.0.1:${port}" "not-used-by-local-proxy" "$model" "$small_model" "$effort_level" "$large_model" "$subagent_model" "$disable_nonstreaming_fallback" "$enable_tool_search"

      if confirm 'Start proxy as a systemd user service now?' 'Y'; then
        write_proxy_service
      else
        say "Proxy can be started manually with: $PROXY_LAUNCHER"
      fi
    else
      write_direct_settings "$base_url" "$api_key" "$model" "$small_model" "$effort_level" "$large_model" "$subagent_model" "$disable_nonstreaming_fallback" "$enable_tool_search"
    fi
  fi

  write_switcher_command

  say
  say "Done."
  local claude_cmd="claude"
  if [ -x "${USER_BIN_DIR}/claude" ]; then
    claude_cmd="${USER_BIN_DIR}/claude"
  fi
  say "Test with:"
  say "  ${claude_cmd} -p '只回复 OK'"
  say
  say "Interactive Claude Code:"
  say "  ${claude_cmd}"
  say
  say "Switch provider/model later with:"
  say "  ${SWITCHER_BIN}"
}

main "$@"
