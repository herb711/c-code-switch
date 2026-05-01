#!/usr/bin/env bash
set -euo pipefail

APP_NAME="codalane"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
PROXY_DIR="${HOME}/.local/share/ccswitch-proxy"
PROXY_BIN="${PROXY_DIR}/proxy.js"
PROXY_ENV="${PROXY_DIR}/proxy.env"
USER_BIN_DIR="${HOME}/.local/bin"
NODE_ROOT="${HOME}/.local/share/codalane-node"
NODE_VERSION="${CODALANE_NODE_VERSION:-20.18.1}"
PROXY_LAUNCHER="${USER_BIN_DIR}/ccswitch-proxy"
SWITCHER_BIN="${USER_BIN_DIR}/ccr"
SWITCHER_ALIAS="${USER_BIN_DIR}/cc-router"
SWITCHER_LEGACY_BIN="${USER_BIN_DIR}/codalane"
SWITCHER_LEGACY_ALIAS="${USER_BIN_DIR}/codalane-switch"
SERVICE_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SERVICE_DIR}/ccswitch-proxy.service"

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
    "${CODALANE_NODE_MIRROR:-https://nodejs.org/dist}"
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
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/codalane-node.XXXXXX")"
    local archive="${tmp_dir}/node.tar.xz"

    download_node_archive "$NODE_VERSION" "$arch" "$archive" \
      || die "Failed to download Node.js. Check network access to nodejs.org or set CODALANE_NODE_MIRROR."

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
  local extra_env_lines=""

  if [ -n "$disable_nonstreaming_fallback" ]; then
    extra_env_lines="$(printf '%s,\n    "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK": "%s"' "$extra_env_lines" "$disable_nonstreaming_fallback")"
  fi
  if [ -n "$effort_level" ]; then
    extra_env_lines="$(printf '%s,\n    "CLAUDE_CODE_EFFORT_LEVEL": "%s"' "$extra_env_lines" "$effort_level")"
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

  mkdir -p "$PROXY_DIR" "$USER_BIN_DIR"
  chmod 700 "$PROXY_DIR"

  cat > "$PROXY_BIN" <<'EOF_PROXY'
#!/usr/bin/env node
const http = require('http');
const https = require('https');
const { URL } = require('url');

const port = Number(process.env.PORT || '8080');
const provider = process.env.CCSWITCH_PROVIDER || 'minimax';
const apiKey = process.env.UPSTREAM_API_KEY || process.env.MINIMAX_API_KEY;
const baseUrl = process.env.UPSTREAM_BASE_URL || process.env.MINIMAX_BASE_URL || 'https://api.minimaxi.com/anthropic';
const authHeader = (process.env.UPSTREAM_AUTH_HEADER || (provider === 'deepseek' ? 'x-api-key' : 'authorization')).toLowerCase();

if (!apiKey) {
  console.error('UPSTREAM_API_KEY is required');
  process.exit(1);
}

if (!['authorization', 'bearer', 'x-api-key'].includes(authHeader)) {
  console.error(`Unsupported UPSTREAM_AUTH_HEADER: ${authHeader}`);
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

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    sendJson(res, 200, { status: 'ok' });
    return;
  }

  if (req.method !== 'POST' || req.url !== '/v1/messages') {
    sendJson(res, 404, { error: 'not found' });
    return;
  }

  const chunks = [];
  req.on('data', chunk => chunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const options = {
      hostname: upstream.hostname,
      port: upstream.port || (upstream.protocol === 'https:' ? 443 : 80),
      path: `${upstream.pathname.replace(/\/+$/, '')}/v1/messages`,
      method: 'POST',
      headers: {
        'content-type': req.headers['content-type'] || 'application/json',
        ...authHeaders(),
        'anthropic-version': req.headers['anthropic-version'] || '2023-06-01',
        'anthropic-beta': req.headers['anthropic-beta'] || '',
        'content-length': body.length
      }
    };

    if (!options.headers['anthropic-beta']) {
      delete options.headers['anthropic-beta'];
    }

    const proxyReq = client.request(options, proxyRes => {
      const headers = { ...proxyRes.headers, 'x-proxied-by': 'ccswitch-proxy-server' };
      res.writeHead(proxyRes.statusCode || 502, headers);
      proxyRes.pipe(res);
    });

    proxyReq.on('error', err => {
      sendJson(res, 502, { error: `upstream error: ${err.message}` });
    });

    proxyReq.write(body);
    proxyReq.end();
  });
});

server.listen(port, '127.0.0.1', () => {
  console.log(`ccswitch-proxy listening on http://127.0.0.1:${port}`);
  console.log(`forwarding ${provider} to ${baseUrl}`);
});
EOF_PROXY
  chmod 700 "$PROXY_BIN"

  umask 077
  cat > "$PROXY_ENV" <<EOF_ENV
CCSWITCH_PROVIDER=${provider}
UPSTREAM_BASE_URL=${base_url}
UPSTREAM_API_KEY=${api_key}
UPSTREAM_AUTH_HEADER=${auth_header}
PORT=${port}
EOF_ENV
  chmod 600 "$PROXY_ENV"

  cat > "$PROXY_LAUNCHER" <<EOF_LAUNCHER
#!/usr/bin/env bash
set -euo pipefail
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
Description=CCSwitch-compatible provider proxy for Claude Code
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${PROXY_LAUNCHER}
Restart=always
RestartSec=5
Environment=HOME=${HOME}

[Install]
WantedBy=default.target
EOF_SERVICE

  systemctl --user daemon-reload
  systemctl --user enable --now ccswitch-proxy.service
  say "Started user service: ccswitch-proxy.service"
}

write_switcher_command() {
  mkdir -p "$USER_BIN_DIR"

  cat > "$SWITCHER_BIN" <<'EOF_SWITCHER'
#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
PROXY_DIR="${HOME}/.local/share/ccswitch-proxy"
PROXY_BIN="${PROXY_DIR}/proxy.js"
PROXY_ENV="${PROXY_DIR}/proxy.env"
USER_BIN_DIR="${HOME}/.local/bin"
PROXY_LAUNCHER="${USER_BIN_DIR}/ccswitch-proxy"
SERVICE_FILE="${HOME}/.config/systemd/user/ccswitch-proxy.service"

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
      env_file_value "$PROXY_ENV" CCSWITCH_PROVIDER || true
      ;;
    *deepseek*) printf '%s' "deepseek" ;;
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
  local extra_env_lines=""

  if [ -n "$disable_nonstreaming_fallback" ]; then
    extra_env_lines="$(printf '%s,\n    "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK": "%s"' "$extra_env_lines" "$disable_nonstreaming_fallback")"
  fi
  if [ -n "$effort_level" ]; then
    extra_env_lines="$(printf '%s,\n    "CLAUDE_CODE_EFFORT_LEVEL": "%s"' "$extra_env_lines" "$effort_level")"
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

  mkdir -p "$PROXY_DIR" "$USER_BIN_DIR"
  chmod 700 "$PROXY_DIR"

  cat > "$PROXY_BIN" <<'EOF_PROXY'
#!/usr/bin/env node
const http = require('http');
const https = require('https');
const { URL } = require('url');

const port = Number(process.env.PORT || '8080');
const provider = process.env.CCSWITCH_PROVIDER || 'minimax';
const apiKey = process.env.UPSTREAM_API_KEY || process.env.MINIMAX_API_KEY;
const baseUrl = process.env.UPSTREAM_BASE_URL || process.env.MINIMAX_BASE_URL || 'https://api.minimaxi.com/anthropic';
const authHeader = (process.env.UPSTREAM_AUTH_HEADER || (provider === 'deepseek' ? 'x-api-key' : 'authorization')).toLowerCase();

if (!apiKey) {
  console.error('UPSTREAM_API_KEY is required');
  process.exit(1);
}

if (!['authorization', 'bearer', 'x-api-key'].includes(authHeader)) {
  console.error(`Unsupported UPSTREAM_AUTH_HEADER: ${authHeader}`);
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

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    sendJson(res, 200, { status: 'ok' });
    return;
  }

  if (req.method !== 'POST' || req.url !== '/v1/messages') {
    sendJson(res, 404, { error: 'not found' });
    return;
  }

  const chunks = [];
  req.on('data', chunk => chunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const options = {
      hostname: upstream.hostname,
      port: upstream.port || (upstream.protocol === 'https:' ? 443 : 80),
      path: `${upstream.pathname.replace(/\/+$/, '')}/v1/messages`,
      method: 'POST',
      headers: {
        'content-type': req.headers['content-type'] || 'application/json',
        ...authHeaders(),
        'anthropic-version': req.headers['anthropic-version'] || '2023-06-01',
        'anthropic-beta': req.headers['anthropic-beta'] || '',
        'content-length': body.length
      }
    };

    if (!options.headers['anthropic-beta']) {
      delete options.headers['anthropic-beta'];
    }

    const proxyReq = client.request(options, proxyRes => {
      const headers = { ...proxyRes.headers, 'x-proxied-by': 'ccswitch-proxy-server' };
      res.writeHead(proxyRes.statusCode || 502, headers);
      proxyRes.pipe(res);
    });

    proxyReq.on('error', err => {
      sendJson(res, 502, { error: `upstream error: ${err.message}` });
    });

    proxyReq.write(body);
    proxyReq.end();
  });
});

server.listen(port, '127.0.0.1', () => {
  console.log(`ccswitch-proxy listening on http://127.0.0.1:${port}`);
  console.log(`forwarding ${provider} to ${baseUrl}`);
});
EOF_PROXY
  chmod 700 "$PROXY_BIN"

  umask 077
  cat > "$PROXY_ENV" <<EOF_ENV
CCSWITCH_PROVIDER=${provider}
UPSTREAM_BASE_URL=${base_url}
UPSTREAM_API_KEY=${api_key}
UPSTREAM_AUTH_HEADER=${auth_header}
PORT=${port}
EOF_ENV
  chmod 600 "$PROXY_ENV"

  cat > "$PROXY_LAUNCHER" <<EOF_LAUNCHER
#!/usr/bin/env bash
set -euo pipefail
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

  if systemctl --user is-active --quiet ccswitch-proxy.service; then
    systemctl --user restart ccswitch-proxy.service
    say "Restarted user service: ccswitch-proxy.service"
    return
  fi

  if [ -f "$SERVICE_FILE" ]; then
    say "Proxy service exists but is not running. Start it with:"
    say "  systemctl --user start ccswitch-proxy.service"
  else
    say "Proxy can be started manually with: $PROXY_LAUNCHER"
  fi
}

main() {
  say "Claude Code Router provider switcher"
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
  model="$(select_model_menu "$provider" "primary" "$default_model" "Primary model")"

  local small_model
  if [ "$provider" = "deepseek" ]; then
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

  if [ -n "$existing_api_key" ]; then
    say "${provider_label} API Key input is hidden. Leave empty to keep the current stored key."
    api_key="$(prompt_secret "${provider_label} API Key")"
    api_key="${api_key:-$existing_api_key}"
  else
    say "${provider_label} API Key input is hidden. Paste the key, then press Enter."
    api_key="$(prompt_required_secret "${provider_label} API Key")"
  fi

  say
  say "Choose Claude Code connection mode:"
  say "  1) Direct mode: Claude Code calls ${provider_label} directly."
  say "  2) Local proxy mode: Claude Code calls a 127.0.0.1 proxy."
  local mode
  mode="$(prompt_default 'Mode' "$(current_mode)")"

  if [ "$mode" = "2" ]; then
    local port
    port="$(prompt_default 'Local proxy port' "$(current_proxy_port)")"
    write_proxy_files "$provider" "$base_url" "$api_key" "$port" "$auth_header"
    write_direct_settings "http://127.0.0.1:${port}" "not-used-by-local-proxy" "$model" "$small_model" "$effort_level" "$large_model" "$subagent_model" "$disable_nonstreaming_fallback"
    restart_proxy_service_if_running
  else
    write_direct_settings "$base_url" "$api_key" "$model" "$small_model" "$effort_level" "$large_model" "$subagent_model" "$disable_nonstreaming_fallback"
  fi

  say
  say "Done. Open Claude Code again for the new provider/model to take effect."
}

main "$@"
EOF_SWITCHER

  chmod 700 "$SWITCHER_BIN"
  ln -sf "$SWITCHER_BIN" "$SWITCHER_ALIAS"
  ln -sf "$SWITCHER_BIN" "$SWITCHER_LEGACY_BIN"
  ln -sf "$SWITCHER_BIN" "$SWITCHER_LEGACY_ALIAS"
  say "Installed provider switcher: $SWITCHER_BIN"
  say "Also available as: $SWITCHER_ALIAS, $SWITCHER_LEGACY_BIN, $SWITCHER_LEGACY_ALIAS"
}

main() {
  say "Codalane: Claude Code provider headless installer"
  say

  install_claude_code

  say
  say "Choose upstream provider:"
  say "  1) MiniMax"
  say "  2) DeepSeek V4"
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
  model="$(select_model_menu "$provider" "primary" "$default_model" "Primary model")"

  local small_model
  if [ "$provider" = "deepseek" ]; then
    small_model="$(select_model_menu "$provider" "small" "$default_small_model" "Small/haiku model")"
  else
    small_model="$model"
  fi

  local large_model="$model"
  local subagent_model="$small_model"

  local api_key
  say "${provider_label} API Key input is hidden. Paste the key, then press Enter."
  api_key="$(prompt_required_secret "${provider_label} API Key")"

  say
  say "Choose Claude Code connection mode:"
  say "  1) Direct mode: Claude Code calls ${provider_label} directly. Recommended."
  say "  2) Local proxy mode: install a local 127.0.0.1 proxy, then Claude Code calls the proxy."
  local mode
  mode="$(prompt_default 'Mode' '1')"

  if [ "$mode" = "2" ]; then
    local port
    port="$(prompt_default 'Local proxy port' '8080')"
    write_proxy_files "$provider" "$base_url" "$api_key" "$port" "$auth_header"
    write_direct_settings "http://127.0.0.1:${port}" "not-used-by-local-proxy" "$model" "$small_model" "$effort_level" "$large_model" "$subagent_model" "$disable_nonstreaming_fallback"

    if confirm 'Start proxy as a systemd user service now?' 'Y'; then
      write_proxy_service
    else
      say "Proxy can be started manually with: $PROXY_LAUNCHER"
    fi
  else
    write_direct_settings "$base_url" "$api_key" "$model" "$small_model" "$effort_level" "$large_model" "$subagent_model" "$disable_nonstreaming_fallback"
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
