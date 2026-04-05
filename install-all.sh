#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

NODE_MODE="install"
PIP_USER=0
SKIP_NODE=0
SKIP_PYTHON=0

usage() {
    cat <<'EOF'
Install dependencies for all local services from the repository root.

Usage:
  ./install-all.sh [--ci] [--python-user] [--skip-node] [--skip-python]

Options:
  --ci           Use deterministic installs when possible (npm ci if lockfile exists).
  --python-user  Install Python dependencies with --user.
  --skip-node    Skip JavaScript dependency installation.
  --skip-python  Skip Python dependency installation.
  -h, --help     Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ci)
            NODE_MODE="ci"
            shift
            ;;
        --python-user)
            PIP_USER=1
            shift
            ;;
        --skip-node)
            SKIP_NODE=1
            shift
            ;;
        --skip-python)
            SKIP_PYTHON=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_python() {
    if [[ -n "${PYTHON:-}" ]] && command_exists "$PYTHON"; then
        echo "$PYTHON"
        return
    fi

    if command_exists python3; then
        echo "python3"
        return
    fi

    if command_exists python; then
        echo "python"
        return
    fi

    echo ""
}

install_node_deps() {
    local manager=""

    if [[ -f "$ROOT_DIR/status-dashboard/pnpm-lock.yaml" ]]; then
        manager="pnpm"
    elif [[ -f "$ROOT_DIR/status-dashboard/yarn.lock" ]]; then
        manager="yarn"
    else
        manager="npm"
    fi

    echo "[node] Installing status-dashboard dependencies with $manager"

    case "$manager" in
        npm)
            if [[ "$NODE_MODE" == "ci" && -f "$ROOT_DIR/status-dashboard/package-lock.json" ]]; then
                (cd "$ROOT_DIR/status-dashboard" && npm ci)
            else
                (cd "$ROOT_DIR/status-dashboard" && npm install)
            fi
            ;;
        yarn)
            if ! command_exists yarn; then
                echo "[node] yarn.lock found but yarn is not installed." >&2
                echo "[node] Install yarn or remove yarn.lock if you intend to use npm." >&2
                exit 1
            fi
            if [[ "$NODE_MODE" == "ci" ]]; then
                (cd "$ROOT_DIR/status-dashboard" && yarn install --frozen-lockfile)
            else
                (cd "$ROOT_DIR/status-dashboard" && yarn install)
            fi
            ;;
        pnpm)
            if ! command_exists pnpm; then
                echo "[node] pnpm-lock.yaml found but pnpm is not installed." >&2
                echo "[node] Install pnpm or remove pnpm-lock.yaml if you intend to use npm." >&2
                exit 1
            fi
            if [[ "$NODE_MODE" == "ci" ]]; then
                (cd "$ROOT_DIR/status-dashboard" && pnpm install --frozen-lockfile)
            else
                (cd "$ROOT_DIR/status-dashboard" && pnpm install)
            fi
            ;;
    esac
}

install_python_deps() {
    local python_bin
    local pip_args=("-m" "pip" "install")

    python_bin="$(detect_python)"
    if [[ -z "$python_bin" ]]; then
        echo "[python] Python not found. Install Python 3.12+ and retry." >&2
        exit 1
    fi

    if [[ "$PIP_USER" -eq 1 ]]; then
        pip_args+=("--user")
    fi

    echo "[python] Installing dependencies with $python_bin"
    "$python_bin" "${pip_args[@]}" -r "$ROOT_DIR/analytics/requirements.txt"
    "$python_bin" "${pip_args[@]}" -r "$ROOT_DIR/status-panel/requirements.txt"
}

if [[ "$SKIP_NODE" -eq 1 && "$SKIP_PYTHON" -eq 1 ]]; then
    echo "Nothing to do: both Node and Python installs are skipped."
    exit 0
fi

if [[ "$SKIP_NODE" -eq 0 ]]; then
    install_node_deps
else
    echo "[node] Skipped"
fi

if [[ "$SKIP_PYTHON" -eq 0 ]]; then
    install_python_deps
else
    echo "[python] Skipped"
fi

echo "All dependency installs completed."
