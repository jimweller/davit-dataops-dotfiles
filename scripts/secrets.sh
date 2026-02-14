#!/bin/bash
set -e
BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-}" in
    open)
        if [ -z "${DOTFILES_KEY:-}" ]; then
            echo "ERROR: DOTFILES_KEY not set"
            exit 1
        fi
        echo "$DOTFILES_KEY" | gpg --batch --decrypt --passphrase-fd 0 "${BASEDIR}/manifests/secrets.gpg" | tar xzf - -C "$HOME"
        ;;
    *)
        echo "Usage: secrets.sh {open}"
        exit 1
        ;;
esac
