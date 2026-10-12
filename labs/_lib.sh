# Shared helpers for labs/*.sh (sourced, not executed).
# shellcheck shell=bash
# shellcheck disable=SC2034  # colours are used by the scripts that source this file
if [[ -t 1 ]]; then C_G=$'\e[32m'; C_R=$'\e[31m'; C_Y=$'\e[33m'; C_B=$'\e[1m'; C_0=$'\e[0m'
else C_G=""; C_R=""; C_Y=""; C_B=""; C_0=""; fi
ok()   { printf '%s✔%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s!%s %s\n' "$C_Y" "$C_0" "$*"; }
die()  { printf '%s%s%s\n' "$C_R" "$*" "$C_0" >&2; exit 1; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Run this inside the repository."
TOOLS_DIR="${LABS_TOOLS_DIR:-$REPO_ROOT/.labs-tools}"

require_clean_tree() {
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "You have uncommitted changes. Commit or stash them first (git stash)."
}

# Same tool versions as CI: read them from the prescan action, so the two can never drift apart.
tool_version() { grep -E "^\s+$1:" "$REPO_ROOT/.github/prescan/action.yml" | head -1 | sed -E 's/.*"([^"]+)".*/\1/'; }

# Download the official release binaries, verify them against the publisher's checksums (exactly
# like the CI action), and put them on PATH. Linux and macOS, amd64 and arm64.
ensure_tools() {
  local gl tv th os arch sha
  gl="$(tool_version GITLEAKS_VERSION)"; tv="$(tool_version TRIVY_VERSION)"; th="$(tool_version TRUFFLEHOG_VERSION)"
  [[ -n "$gl" && -n "$tv" && -n "$th" ]] || die "could not read tool versions from .github/prescan/action.yml"
  command -v jq >/dev/null || die "jq is required (apt install jq / brew install jq)"
  local stamp="$TOOLS_DIR/versions-$gl-$tv-$th"
  export PATH="$TOOLS_DIR/bin:$PATH"
  [[ -f "$stamp" ]] && return 0

  case "$(uname -s)" in Linux) os=linux;; Darwin) os=darwin;; *) die "Linux or macOS only (on Windows, use WSL).";; esac
  case "$(uname -m)" in x86_64|amd64) arch=amd64;; arm64|aarch64) arch=arm64;; *) die "unsupported CPU: $(uname -m)";; esac
  if command -v sha256sum >/dev/null; then sha="sha256sum -c -"; else sha="shasum -a 256 -c -"; fi
  local gl_arch="$arch"; [[ "$arch" == amd64 ]] && gl_arch=x64
  local tv_os="Linux"; [[ "$os" == darwin ]] && tv_os="macOS"
  local tv_arch="64bit"; [[ "$arch" == arm64 ]] && tv_arch="ARM64"

  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$TOOLS_DIR/bin"
  fetch() { # base archive checksums binary
    if ! curl -sSfL --retry 3 -o "$tmp/$2" "$1/$2" || ! curl -sSfL --retry 3 -o "$tmp/$3" "$1/$3"; then
      die "download failed: $1/$2"
    fi
    (cd "$tmp" && grep " $2\$" "$3" | $sha >/dev/null) || die "CHECKSUM MISMATCH for $2. Not installing it."
    tar -xzf "$tmp/$2" -C "$TOOLS_DIR/bin" "$4"
    echo "  $4: $2 (checksum OK)"
  }
  echo "Installing the CI's scanner versions into ${TOOLS_DIR#"$REPO_ROOT"/} (one time):"
  fetch "https://github.com/gitleaks/gitleaks/releases/download/v$gl" "gitleaks_${gl}_${os}_${gl_arch}.tar.gz" "gitleaks_${gl}_checksums.txt" gitleaks
  fetch "https://github.com/aquasecurity/trivy/releases/download/v$tv" "trivy_${tv}_${tv_os}-${tv_arch}.tar.gz" "trivy_${tv}_checksums.txt" trivy
  fetch "https://github.com/trufflesecurity/trufflehog/releases/download/v$th" "trufflehog_${th}_${os}_${arch}.tar.gz" "trufflehog_${th}_checksums.txt" trufflehog
  touch "$stamp"
}

# rand CHARSET LENGTH -- random string for FAKE secrets, generated at plant time so the repository
# itself never contains anything a scanner (or GitHub push protection) would flag.
rand() {
  local s
  s="$(LC_ALL=C tr -dc "$1" < <(head -c 8192 /dev/urandom))"
  printf '%s' "${s:0:$2}"
}
