# Minecraft Fabric Server - バージョンアップ手順

## 概要

`apps/minecraft-fabric/` で管理している Minecraft Fabric サーバーのバージョンを更新する手順です。

## 手順

### 1. バックアップを取る

```bash
./scripts/minecraft/backup.sh
```

### 2. config.env のバージョンを変更

```bash
# 現在のバージョンを確認
grep VERSION apps/minecraft-fabric/config.env

# バージョンを変更（例: 1.21.11 に更新）
sed -i '' 's/VERSION=.*/VERSION=1.21.11/' apps/minecraft-fabric/config.env
```

または、エディタで `apps/minecraft-fabric/config.env` を直接編集:

```
VERSION=1.21.11
```

### 3. Kustomize で適用

```bash
sudo kubectl apply -k apps/minecraft-fabric/
```

### 4. デプロイメントを更新

既存の Pod がワールドデータをロックしているため、スケールダウン→スケールアップで更新します:

```bash
# スケールダウン（全 Pod 停止）
sudo kubectl scale deployment minecraft-fabric-server -n minecraft-fabric --replicas=0

# 数秒待ってからスケールアップ
sudo kubectl scale deployment minecraft-fabric-server -n minecraft-fabric --replicas=1
```

### 5. 起動を確認

```bash
# Pod の状態を確認
sudo kubectl get pods -n minecraft-fabric

# ログで起動完了を確認（Done! と表示されれば OK）
sudo kubectl logs -f <pod-name> -n minecraft-fabric
```

## トラブルシューティング

### session.lock エラーが発生する場合

```
Failed to start the minecraft server
net.minecraft.class_5125$class_5126: /data/./world/session.lock: already locked
```

古い Pod がまだ動いている可能性があります。手順 4 のスケールダウン→スケールアップを再度実行してください。

### CrashLoopBackOff になる場合

ログを確認してエラー内容を特定:

```bash
sudo kubectl logs <pod-name> -n minecraft-fabric --tail=100
```

## 補足

- `VERSION=LATEST` を指定すると、常に最新の安定版が適用されます
- `VERSION=SNAPSHOT` で最新のスナップショット版も利用可能
- Mod（`MODRINTH_PROJECTS` で指定）は自動的に互換バージョンがダウンロードされます
- メジャーバージョンアップ時は Mod の互換性に注意してください
