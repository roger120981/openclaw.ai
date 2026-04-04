#!/usr/bin/env bash
set -euo pipefail

LOCAL_INSTALL_PATH="/opt/openclaw-install.sh"
if [[ -n "${OPENCLAW_INSTALL_URL:-}" ]]; then
  INSTALL_URL="$OPENCLAW_INSTALL_URL"
elif [[ -n "${CLAWDBOT_INSTALL_URL:-}" ]]; then
  INSTALL_URL="$CLAWDBOT_INSTALL_URL"
elif [[ -f "$LOCAL_INSTALL_PATH" ]]; then
  INSTALL_URL="file://${LOCAL_INSTALL_PATH}"
else
  INSTALL_URL="https://openclaw.ai/install.sh"
fi

curl_install() {
  if [[ "$INSTALL_URL" == file://* ]]; then
    curl -fsSL "$INSTALL_URL"
  else
    curl -fsSL --proto '=https' --tlsv1.2 "$INSTALL_URL"
  fi
}

extract_version() {
  local raw="$1"
  if [[ "$raw" =~ ([0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "$raw"
  fi
}

echo "==> Installer: --help"
curl_install | bash -s -- --help >/tmp/install-help.txt
grep -q -- "--install-method" /tmp/install-help.txt

echo "==> Clone Openclaw repo"
REPO_DIR="/tmp/openclaw-src"
rm -rf "$REPO_DIR"
git clone --depth 1 https://github.com/openclaw/openclaw.git "$REPO_DIR"

echo "==> Verify autodetect defaults to npm (no TTY)"
(
  cd "$REPO_DIR"
  set +e
  curl_install | bash -s -- --dry-run --no-onboard --no-prompt >/tmp/git-detect.out 2>&1
  code=$?
  set -e
  if [[ "$code" -ne 0 ]]; then
    echo "ERROR: expected installer to succeed when repo is detected without method" >&2
    cat /tmp/git-detect.out >&2
    exit 1
  fi
  if ! sed -r 's/\x1b\[[0-9;]*m//g' /tmp/git-detect.out | grep -Eq "Install method: npm|Install method[[:space:]]+npm"; then
    echo "ERROR: expected autodetect to default to npm" >&2
    cat /tmp/git-detect.out >&2
    exit 1
  fi
)

echo "==> Install from Git (using detected checkout)"
(
  cd "$REPO_DIR"
  curl_install | bash -s -- --install-method git --no-onboard --no-prompt --no-git-update
)

echo "==> Verify wrapper exists"
test -x "$HOME/.local/bin/openclaw"

echo "==> Verify openclaw runs"
export PATH="$HOME/.local/bin:$PATH"
openclaw --help >/dev/null

echo "==> Verify version matches checkout"
EXPECTED_VERSION="$(node -e "console.log(JSON.parse(require('fs').readFileSync('${REPO_DIR}/package.json','utf8')).version)")"
INSTALLED_VERSION_RAW="$(openclaw --version 2>/dev/null | head -n 1 | tr -d '\r')"
INSTALLED_VERSION="$(extract_version "$INSTALLED_VERSION_RAW")"
echo "installed=$INSTALLED_VERSION raw=$INSTALLED_VERSION_RAW expected=$EXPECTED_VERSION"
if [[ "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "ERROR: expected openclaw@$EXPECTED_VERSION, got $INSTALLED_VERSION" >&2
  exit 1
fi

echo "OK"
