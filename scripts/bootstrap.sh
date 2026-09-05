#!/usr/bin/env bash
set -euo pipefail
command -v node >/dev/null || { echo "Node.js をインストールしてください。" >&2; exit 1; }
command -v pnpm >/dev/null || { echo "pnpm をインストールしてください。" >&2; exit 1; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node "$repo_root/scripts/verify.mjs"
echo "構成を確認しました。アプリ依存と Xcode 設定は未導入です。"
