# Universal Exec (uexec.sh)

汎用コンテナ実行スクリプト - devcontainer、既存コンテナ、ローカル環境で任意のコマンドを実行

## セットアップ

1. 設定ファイルを作成：
```bash
cp uexec.conf.example uexec.conf
```

2. `uexec.conf`を編集してターゲットを設定

## 使い方

```bash
# 基本的な実行
./uexec.sh <target> [command...]

# コンテナを再作成してから実行
./uexec.sh --restart <target> [command...]

# Node.jsとCopilot CLIをインストール
./uexec.sh --restart --install-copilot <target> [command...]
```

## オプション

- `--restart` - 既存コンテナを削除してから起動
- `--install-node` - Node.jsをインストール（apt経由）
- `--install-copilot` - Node.js + GitHub Copilot CLIをインストール

## 例

```bash
# Copilot CLIを起動
./uexec.sh myproject/web copilot

# 初回セットアップ（コンテナ再作成 + Copilotインストール）
./uexec.sh --restart --install-copilot myproject/web copilot

# bashシェルを起動
./uexec.sh myproject/web bash

# ローカル実行
./uexec.sh localproject ls -la
```

## ターゲット設定

`uexec.conf`で設定します。フォーマット：

```
"exec_type:repo_path:service_name[:container_name][:use_compose][:remote_user]"
```

### 例

```bash
# Devcontainer（debianユーザー）
TARGETS["myproject/web"]="devcontainer:myproject:web:::debian"

# Devcontainer（別ユーザー）
TARGETS["another/api"]="devcontainer:another:api:::appuser"

# ローカル実行
TARGETS["localproject"]="local:localproject"

# 既存コンテナに接続
TARGETS["running/service"]="container:running:service"

# Docker Compose経由
TARGETS["compose/app"]="container:compose:app::compose"
```

## 機能

- **Devcontainer起動**: `devcontainer up`で自動的に起動
- **Copilotセッション共有**: `~/.copilot`を自動マウント
- **Node.js/Copilotインストール**: `--install-copilot`で一発セットアップ
- **柔軟なターゲット設定**: 設定ファイルで簡単に管理
