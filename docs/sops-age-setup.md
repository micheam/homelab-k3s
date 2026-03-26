# SOPS + age によるシークレット管理

このリポジトリでは [SOPS](https://github.com/getsf/sops) と [age](https://github.com/FiloSottile/age) を使って秘密情報を暗号化し、Git で安全に管理しています。

## 前提ツール

```bash
brew install age sops
```

## age 秘密鍵の管理

秘密鍵は `~/.config/sops/age/keys.txt` に配置します（SOPS のデフォルト参照パス）。

### 新規生成

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

### iCloud キーチェーンへのバックアップ

age 秘密鍵は複数行のテキストであり、`security` CLI の generic password では1行分しか保存できないため、**キーチェーンアクセス.app から GUI で保存**します。

#### 保存手順

1. `~/.config/sops/age/keys.txt` の内容をクリップボードにコピー:
   ```bash
   cat ~/.config/sops/age/keys.txt | pbcopy
   ```
2. 「キーチェーンアクセス.app」を開く
3. サイドバーで「iCloud」キーチェーンを選択
4. メニューから「ファイル > 新規パスワード項目...」を選択
5. 以下を入力:
   - キーチェーン項目名: `homelab-k3s-sops-age-key`
   - アカウント名: 自分のユーザー名
   - パスワード: クリップボードの内容をペースト
6. 保存

iCloud キーチェーンに保存することで、同一 Apple アカウントの他のデバイスからも復元可能になります。

#### 復元手順

1. 「キーチェーンアクセス.app」で `homelab-k3s-sops-age-key` を検索
2. パスワードを表示してコピー
3. ファイルに書き出し:
   ```bash
   mkdir -p ~/.config/sops/age
   pbpaste > ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   ```

## シークレットの操作

### 復号（セットアップ時）

```bash
./scripts/setup/init-local.sh
```

または個別に:

```bash
sops decrypt apps/<app-name>/secrets.enc.env > apps/<app-name>/secrets.env
```

### 編集

```bash
sops edit apps/<app-name>/secrets.enc.env
```

### 新規作成

`secrets.env` に平文で値を書き、暗号化:

```bash
sops encrypt apps/<app-name>/secrets.env > apps/<app-name>/secrets.enc.env
```

## ファイル構成

| ファイル | 内容 | Git 管理 |
|---------|------|----------|
| `config.env` | 非秘密の設定値 | コミット対象 |
| `secrets.env` | 秘密情報（平文） | `.gitignore` で除外 |
| `secrets.enc.env` | 秘密情報（暗号化済み） | コミット対象 |
| `.sops.yaml` | SOPS の暗号化ルール | コミット対象 |
