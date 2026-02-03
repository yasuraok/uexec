#!/bin/bash

# Universal Exec Script - コンテナやローカル環境で任意のコマンドを実行
# Usage: ./uexec.sh [--restart] [--install-node] [--install-copilot] <target> [command...]

set -e

WORKSPACE_DIR="${HOME}/workspace"
RESTART_CONTAINER=false
INSTALL_NODE=false
INSTALL_COPILOT=false

# Node.jsインストール関数
install_node_in_container() {
    local container_name="$1"
    echo ""
    echo "📦 Installing Node.js (via apt)..."
    docker exec "$container_name" bash -c '
        set -e
        if command -v node &> /dev/null; then
            echo "Node.js is already installed: $(node --version)"
            exit 0
        fi
        
        echo "Setting up NodeSource repository..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        
        echo "Installing Node.js..."
        sudo apt-get install -y nodejs
        
        echo "Verifying installation..."
        node --version
        npm --version
        
        echo "✅ Node.js installed successfully"
    ' || {
        echo "❌ Failed to install Node.js"
        return 1
    }
    echo ""
}

# Copilot CLIインストール関数
install_copilot_in_container() {
    local container_name="$1"
    echo "📦 Installing GitHub Copilot CLI..."
    docker exec "$container_name" bash -c '
        set -e
        if command -v copilot &> /dev/null; then
            echo "Copilot CLI is already installed: $(copilot --version)"
            exit 0
        fi
        
        # 古いパッケージがあれば削除
        sudo npm uninstall -g @githubnext/github-copilot-cli 2>/dev/null || true
        
        # 新しい公式パッケージをインストール
        sudo npm install -g @github/copilot
        
        echo "✅ Copilot CLI installed successfully"
        copilot --version
    ' || {
        echo "❌ Failed to install Copilot CLI"
        return 1
    }
    echo ""
}

# オプション解析
while [[ "$1" == --* ]]; do
    case "$1" in
        --restart)
            RESTART_CONTAINER=true
            shift
            ;;
        --install-node)
            INSTALL_NODE=true
            shift
            ;;
        --install-copilot)
            INSTALL_NODE=true
            INSTALL_COPILOT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ターゲット設定
declare -A TARGETS

# 設定ファイルを読み込み
CONFIG_FILE="${HOME}/uexec.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "⚠️  Warning: Config file not found: $CONFIG_FILE"
    echo "   Copy uexec.conf.example to uexec.conf and edit it."
    exit 1
fi

# ターゲット一覧表示
show_targets() {
    echo "🚀 Universal Exec - Available targets:"
    echo ""
    for target in "${!TARGETS[@]}"; do
        echo "  📦 $0 $target [command...]"
    done
    echo ""
    echo "Usage: $0 [--restart] [--install-copilot] <target> [command...]"
}

if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_targets
    exit 0
fi

TARGET_NAME="$1"
shift
CMD_ARGS=("$@")
[ ${#CMD_ARGS[@]} -eq 0 ] && CMD_ARGS=("bash")

if [ -z "${TARGETS[$TARGET_NAME]}" ]; then
    echo "❌ Error: Unknown target '${TARGET_NAME}'"
    show_targets
    exit 1
fi

IFS=':' read -r EXEC_TYPE REPO_NAME SERVICE_NAME CONTAINER_NAME USE_COMPOSE REMOTE_USER <<< "${TARGETS[$TARGET_NAME]}"
REPO_PATH="${WORKSPACE_DIR}/${REPO_NAME}"

# remote_userが指定されていない場合はホストユーザーを使用
if [ -z "$REMOTE_USER" ]; then
    REMOTE_USER="$(whoami)"
fi

if [ ! -d "$REPO_PATH" ]; then
    echo "❌ Error: Repository not found at ${REPO_PATH}"
    exit 1
fi

CMD_STRING=""
for arg in "${CMD_ARGS[@]}"; do
    [[ "$arg" =~ [[:space:]] ]] && CMD_STRING+="\"$arg\" " || CMD_STRING+="$arg "
done
CMD_STRING="${CMD_STRING% }"

echo "📂 Target: ${TARGET_NAME}"
echo "🔧 Type: ${EXEC_TYPE}"
echo "👤 Remote User: ${REMOTE_USER}"
[ "$RESTART_CONTAINER" = true ] && echo "♻️  Restart: enabled"
[ "$INSTALL_COPILOT" = true ] && echo "📦 Install: Node.js + Copilot CLI"
echo "💻 Command: ${CMD_STRING}"
echo ""

case "$EXEC_TYPE" in
    local)
        echo "🏠 Executing locally..."
        cd "$REPO_PATH"
        exec "${CMD_ARGS[@]}"
        ;;
    devcontainer)
        DEVCONTAINER_PATH="${REPO_PATH}/.devcontainer/${SERVICE_NAME}"
        [ ! -d "$DEVCONTAINER_PATH" ] && DEVCONTAINER_PATH="${REPO_PATH}/.devcontainer"
        
        if [ ! -f "$DEVCONTAINER_PATH/devcontainer.json" ]; then
            echo "❌ Error: Devcontainer config not found"
            exit 1
        fi
        
        if ! command -v devcontainer &> /dev/null; then
            echo "❌ Error: devcontainer CLI not found"
            echo "Install: npm install -g @devcontainers/cli"
            exit 1
        fi
        
        cd "$REPO_PATH"
        
        MOUNT_OPTS=""
        [ -d "${HOME}/.copilot" ] && MOUNT_OPTS="--mount type=bind,source=${HOME}/.copilot,target=/home/${REMOTE_USER}/.copilot"
        
        REMOVE_OPTS=""
        [ "$RESTART_CONTAINER" = true ] && REMOVE_OPTS="--remove-existing-container"
        
        echo "🚀 Starting devcontainer..."
        devcontainer up --workspace-folder "${REPO_PATH}" --config "${DEVCONTAINER_PATH}/devcontainer.json" $REMOVE_OPTS $MOUNT_OPTS
        
        CONTAINER_NAME="${REPO_NAME}-${SERVICE_NAME}-1"
        docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" || CONTAINER_NAME="${REPO_NAME//-/_}_${SERVICE_NAME}_1"
        
        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "❌ Error: Container not running"
            docker ps
            exit 1
        fi
        
        echo "🐳 Container: ${CONTAINER_NAME}"
        
        [ "$INSTALL_NODE" = true ] && install_node_in_container "$CONTAINER_NAME"
        [ "$INSTALL_COPILOT" = true ] && install_copilot_in_container "$CONTAINER_NAME"
        
        docker exec -it "$CONTAINER_NAME" bash -c "cd ${REPO_PATH} && exec bash --login -c '${CMD_STRING}'"
        ;;
    *)
        echo "❌ Error: Invalid exec-type"
        exit 1
        ;;
esac
