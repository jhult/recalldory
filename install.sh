#!/usr/bin/env bash
# recalldory install script
# Usage: curl -fsSL https://raw.githubusercontent.com/jhult/recalldory/trunk/install.sh | bash
set -euo pipefail

REPO="jhult/recalldory"
SKILL_SRC=".claude/skills/recalldory/SKILL.md"

# ANSI codes (disabled when not a terminal)
RED='' GREEN='' YELLOW='' BOLD='' RESET=''
if [ -t 1 ]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BOLD='\033[1m' RESET='\033[0m'
fi

info()  { printf "${GREEN}info${RESET}: %s\n" "$1"; }
warn()  { printf "${YELLOW}warn${RESET}: %s\n" "$1"; }
error() { printf "${RED}error${RESET}: %s\n" "$1" >&2; }
die()   { error "$1"; exit 1; }

needs_tool() {
    command -v "$1" >/dev/null 2>&1 || die "Required tool not found: $1"
}

show_help() {
    cat <<'EOF'
Usage: install.sh [options]

Install recalldory — persistent memory for AI coding assistants.

Options:
  --prefix DIR       Installation prefix (default: ~/.local)
  --target TARGET    Override platform target (e.g. amd64-linux-gnu)
  --skip-hook        Skip post-compact hook installation
  --skip-skill       Skip Claude Code skill installation
  -h, --help         Show this help message

Platforms detected automatically:
  macOS  arm64      -> arm64-mac-native
  macOS  x86_64     -> amd64-mac-native
  Linux  x86_64     -> amd64-linux-gnu (or amd64-linux-musl on musl systems)
  Linux  aarch64    -> arm64-linux-gnu (or arm64-linux-musl on musl systems)

Examples:
  curl -fsSL https://raw.githubusercontent.com/jhult/recalldory/trunk/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/jhult/recalldory/trunk/install.sh | bash -s -- --prefix /usr/local
  ./install.sh --target amd64-linux-musl

After installation, initialize each project:
  cd /path/to/your/project
  recalldory init
EOF
}

# --- Parse arguments ---

PREFIX="${HOME}/.local"
TARGET=""
SKIP_HOOK=false
SKIP_SKILL=false

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)     shift; [ $# -gt 0 ] || die "--prefix requires a value"; PREFIX="$1" ;;
        --target)     shift; [ $# -gt 0 ] || die "--target requires a value"; TARGET="$1" ;;
        --skip-hook)  SKIP_HOOK=true ;;
        --skip-skill) SKIP_SKILL=true ;;
        -h|--help)    show_help; exit 0 ;;
        *) die "Unknown option: $1. Run with --help for usage." ;;
    esac
    shift
done

PREFIX="${PREFIX/#\~/$HOME}"

# --- Preflight ---

needs_tool curl
needs_tool uname

# --- Platform detection ---

detect_target() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$os" in
        darwin)
            case "$arch" in
                arm64)  echo "arm64-mac-native" ;;
                x86_64) echo "amd64-mac-native" ;;
                *) die "Unsupported macOS architecture: ${arch}" ;;
            esac
            ;;
        linux)
            local libc="gnu"
            if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
                libc="musl"
            fi
            case "$arch" in
                x86_64)  echo "amd64-linux-${libc}" ;;
                aarch64) echo "arm64-linux-${libc}" ;;
                *) die "Unsupported Linux architecture: ${arch}" ;;
            esac
            ;;
        *) die "Unsupported OS: ${os}" ;;
    esac
}

if [ -z "$TARGET" ]; then
    TARGET="$(detect_target)"
    info "Detected platform: ${TARGET}"
fi

# --- Find latest release ---

info "Finding latest release..."
if ! RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null)"; then
    die "Failed to fetch release info from GitHub. Check your connection and that releases exist at https://github.com/${REPO}/releases"
fi

TAG="$(printf '%s' "$RELEASE_JSON" | grep -m1 '"tag_name"\s*:' | sed -E 's/.*"tag_name"\s*:\s*"([^"]+)".*/\1/' || true)"
if [ -z "$TAG" ]; then
    die "Could not determine latest release version"
fi
info "Latest version: ${TAG}"

# --- Download and install binary ---

BINDIR="${PREFIX}/bin"
BINARY="${BINDIR}/recalldory"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/recalldory-${TARGET}"

info "Downloading recalldory-${TARGET}..."
mkdir -p "$BINDIR"
if ! curl -fSL -o "$BINARY" "$DOWNLOAD_URL"; then
    die "Failed to download from ${DOWNLOAD_URL}. The '${TARGET}' target may not have a pre-built binary."
fi
chmod +x "$BINARY"
info "Installed binary to ${BINARY}"

# --- Install Claude Code skill ---

if [ "$SKIP_SKILL" = false ]; then
    SKILL_DIR="${HOME}/.claude/skills/recalldory"
    SKILL_FILE="${SKILL_DIR}/SKILL.md"
    SKILL_URL="https://raw.githubusercontent.com/${REPO}/${TAG}/${SKILL_SRC}"

    info "Installing Claude Code skill..."
    mkdir -p "$SKILL_DIR"
    if curl -fsSL -o "$SKILL_FILE" "$SKILL_URL"; then
        info "Installed skill to ${SKILL_FILE}"
    else
        warn "Failed to download skill. You can manually copy .claude/skills/recalldory/SKILL.md to ${SKILL_DIR}"
    fi
fi

# --- Add to PATH ---

portable_path() {
    local path="$1"
    if [[ "$path" == "${HOME}/"* ]]; then
        # shellcheck disable=SC2016
        printf '$HOME/%s' "${path#"${HOME}"/}"
    else
        printf '%s' "$path"
    fi
}

add_to_path() {
    local bindir="$1"
    local portable
    portable="$(portable_path "$bindir")"
    local shell_name
    shell_name="$(basename "${SHELL:-sh}")"

    case "$shell_name" in
        fish)
            local conf_dir="${HOME}/.config/fish/conf.d"
            local conf_file="${conf_dir}/recalldory.fish"
            mkdir -p "$conf_dir"
            printf 'fish_add_path %s\n' "$portable" > "$conf_file"
            info "Updated fish PATH via ${conf_file}"
            info "Restart your shell or run: source ${conf_file}"
            ;;
        zsh|bash)
            local rc="${HOME}/.${shell_name}rc"
            if [ -f "$rc" ] && grep -qF '# recalldory' "$rc" 2>/dev/null; then
                info "PATH already configured in ${rc}"
            else
                # shellcheck disable=SC2016
                printf '\n# recalldory\nexport PATH="%s:$PATH"\n' "$portable" >> "$rc"
                info "Added to PATH in ${rc}"
                info "Restart your shell or run: source ${rc}"
            fi
            ;;
        *)
            warn "Unsupported shell '${shell_name}'. Add ${bindir} to your PATH manually."
            ;;
    esac
}

case ":${PATH}:" in
    *":${BINDIR}:"*)
        info "${BINDIR} is already in PATH"
        ;;
    *)
        add_to_path "$BINDIR"
        ;;
esac

# --- Install post-compact hook ---

if [ "$SKIP_HOOK" = false ]; then
    info "Installing post-compact hook..."
    if "$BINARY" hook install; then
        info "Post-compact hook installed"
    else
        warn "Hook installation failed. Run 'recalldory hook install' manually."
    fi
fi

printf "\n${BOLD}recalldory %s installed!${RESET}\n" "$TAG"
printf "\nNext: initialize your project with ${GREEN}recalldory init${RESET}\n"