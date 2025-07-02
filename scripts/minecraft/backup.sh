#!/bin/bash
# Minecraftワールドバックアップスクリプト

NAMESPACE="minecraft"
BACKUP_DIR="$HOME/minecraft-backups"
POD=$(kubectl get pod -n $NAMESPACE -l app=minecraft -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
    echo "Error: Minecraft pod not found"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "Creating backup..."
kubectl exec -n $NAMESPACE $POD -- rcon-cli save-all
sleep 5

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
kubectl exec -n $NAMESPACE $POD -- tar -czf - /data/worlds > "$BACKUP_DIR/minecraft-backup-$TIMESTAMP.tar.gz"

echo "Backup saved to: $BACKUP_DIR/minecraft-backup-$TIMESTAMP.tar.gz"

# 古いバックアップを削除（7日以上前）
find "$BACKUP_DIR" -name "minecraft-backup-*.tar.gz" -mtime +7 -delete
