#!/usr/bin/env bash
set -euo pipefail

APP_NAME="codalane"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
PROXY_DIR="${HOME}/.local/share/ccswitch-proxy"
PROXY_BIN="${PROXY_DIR}/proxy.js"
PROXY_ENV="${PROXY_DIR}/proxy.env"
USER_BIN_DIR="${HOME}/.local/bin"
PROXY_LAUNCHER="${USER_BIN_DIR}/ccswitch-proxy"
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
    say "Input was empty. Paste your key, then press Enter. The key will not be shown while typing."
  done
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
  if need_cmd npm; then
    return
  fi

  if ! need_cmd curl; then
    die "curl is not installed. Install curl first, then rerun this script."
  fi

  say "npm not found. Installing Node.js via fnm (no sudo required)..."

  local fnm_dir="${HOME}/.fnm"
  local fnm_bin="${fnm_dir}/fnm"
  local fnm_url
  fnm_url="$(curl -fsSL https://api.github.com/repos/Schniz/fnm/releases/latest | grep 'browser_download_url.*linux-x64"' | cut -d'"' -f4)"

  if [ -z "$fnm_url" ]; then
    die "Failed to find fnm release URL. Install Node.js manually, then rerun."
  fi

  mkdir -p "${fnm_dir}"
  curl -fsSL "$fnm_url" -o "$fnm_bin"
  chmod +x "$fnm_bin"

  export PATH="${fnm_dir}:${PATH}"
  eval "$(fnm env --use-on-cd)"
  fnm install 20
  fnm default 20

  if ! need_cmd npm; then
    die "fnm installed but npm still not found. Check PATH after: eval \"\$(fnm env --use-on-cd)\""
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
  npm install -g @anthropic-ai/claude-code
}

write_direct_settings() {
  local base_url="$1"
  local api_key="$2"
  local model="$3"

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
    "ANTHROPIC_SMALL_FAST_MODEL": "${model}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${model}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${model}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${model}"
  }
}
EOF_SETTINGS
  chmod 600 "$SETTINGS_FILE"
  say "Wrote Claude Code settings: $SETTINGS_FILE"
}

write_proxy_files() {
  local base_url="$1"
  local api_key="$2"
  local port="$3"

  mkdir -p "$PROXY_DIR" "$USER_BIN_DIR"
  chmod 700 "$PROXY_DIR"

  cat > "$PROXY_BIN" <<'EOF_PROXY'
#!/usr/bin/env node
const http = require('http');
const https = require('https');
const { URL } = require('url');

const port = Number(process.env.PORT || '8080');
const apiKey = process.env.MINIMAX_API_KEY;
const baseUrl = process.env.MINIMAX_BASE_URL || 'https://api.minimaxi.com/anthropic';

if (!apiKey) {
  console.error('MINIMAX_API_KEY is required');
  process.exit(1);
}

const upstream = new URL(baseUrl.replace(/\/+$/, ''));
const client = upstream.protocol === 'https:' ? https : http;

function sendJson(res, status, payload) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(payload));
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
        'authorization': `Bearer ${apiKey}`,
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
  console.log(`forwarding to ${baseUrl}`);
});
EOF_PROXY
  chmod 700 "$PROXY_BIN"

  umask 077
  cat > "$PROXY_ENV" <<EOF_ENV
MINIMAX_BASE_URL=${base_url}
MINIMAX_API_KEY=${api_key}
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
Description=CCSwitch-compatible MiniMax proxy for Claude Code
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

main() {
  say "Codalane: Claude Code + MiniMax headless installer"
  say

  install_claude_code

  say
  say "Choose MiniMax endpoint:"
  say "  1) China mainland: https://api.minimaxi.com/anthropic"
  say "  2) International:  https://api.minimax.io/anthropic"
  local endpoint_choice
  endpoint_choice="$(prompt_default 'Endpoint choice' '1')"
  local base_url
  case "$endpoint_choice" in
    2) base_url="https://api.minimax.io/anthropic" ;;
    *) base_url="https://api.minimaxi.com/anthropic" ;;
  esac

  local model
  model="$(prompt_default 'Model name' 'MiniMax-M2.7')"

  local api_key
  say "MiniMax API Key input is hidden. Paste the key, then press Enter."
  api_key="$(prompt_required_secret 'MiniMax API Key')"

  say
  say "Choose Claude Code connection mode:"
  say "  1) Direct mode: Claude Code calls MiniMax directly. Recommended."
  say "  2) Local proxy mode: install a local 127.0.0.1 proxy, then Claude Code calls the proxy."
  local mode
  mode="$(prompt_default 'Mode' '1')"

  if [ "$mode" = "2" ]; then
    local port
    port="$(prompt_default 'Local proxy port' '8080')"
    write_proxy_files "$base_url" "$api_key" "$port"
    write_direct_settings "http://127.0.0.1:${port}" "not-used-by-local-proxy" "$model"

    if confirm 'Start proxy as a systemd user service now?' 'Y'; then
      write_proxy_service
    else
      say "Proxy can be started manually with: $PROXY_LAUNCHER"
    fi
  else
    write_direct_settings "$base_url" "$api_key" "$model"
  fi

  say
  say "Done."
  say "Test with:"
  say "  claude -p '只回复 OK'"
  say
  say "Interactive Claude Code:"
  say "  claude"
}

main "$@"
