#!/bin/bash
# ワールド切り替えスクリプト

NAMESPACE="minecraft"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <world-name>"
    echo "Available worlds:"
    kubectl exec -n minecraft deployment/minecraft-server -- ls -1 /data/worlds/ 2>/dev/null || echo "No worlds found"
    exit 1
fi

WORLD_NAME=$1

echo "Switching to world: $WORLD_NAME"

# ConfigMapを更新（この実装は環境に応じて調整が必要）
echo "Please update ACTIVE_WORLD in config.env and re-apply the configuration"
echo "Then run: kubectl rollout restart -n $NAMESPACE deployment/minecraft-server"
