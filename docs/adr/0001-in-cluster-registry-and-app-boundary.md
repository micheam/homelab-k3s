# 0001. クラスタ内にコンテナレジストリを置き、ビルドとマイグレーションをアプリのリポジトリに任せる

## Status

Accepted

## Context

limnosrv を配備するスクリプト `scripts/limnosrv/deploy.sh` は、bash で保守できる限界に近い規模になっていた。このスクリプトは k3s へのマニフェストの適用のほかに、次の仕事を抱えていた。

- 別のリポジトリ（limno）のイメージのビルドを `make -C $LIMNO_REPO docker` で呼ぶ
- できたイメージを `docker save`、`scp`、`k3s ctr images import` でノードに運ぶ
- limnosrv の Pod の中で goose を実行し、マイグレーションを当てる。そのために goose、マイグレーションのディレクトリ、版を記録する表といったアプリの内部を知っている
- 共有 PostgreSQL に limno のロール、DB、スキーマを作る。名前は `limno` に固定で、パスワードは SQL の文字列に直接埋め込んでいた。パスワードに `'` が含まれると SQL が壊れる

マニフェストはイメージを `latest` と `imagePullPolicy: Never` で参照し、更新は `rollout restart` で反映していた。どのビルドが動いているのかをマニフェストから読み取れず、ロールバックも難しかった。

当初は、このスクリプトを bash から別の言語に移植することを検討した。しかし検討を進めると、規模が大きくなった原因は言語ではなかった。外部のレジストリを使わない方針のもとで、イメージの転送を手作業で代行した結果、アプリのビルドやマイグレーションの責務までこのリポジトリに入り込んでいた。

前提として、ローカルの kubeconfig は読み取り専用で、書き込みを伴う操作はノードに SSH して行う。

## Decision

### 責任の境界

このリポジトリが受け持つのは、k3s と、その上で動く Pod と共有基盤（レジストリ、PostgreSQL）の運用である。イメージのビルド、レジストリへの登録、スキーマの作成とマイグレーションは、アプリのリポジトリが受け持つ。

アプリとの取り決めは、次の 2 つだけにする。

- イメージ（レジストリ、名前、タグ）
- Secret と ConfigMap で渡す環境変数（`DATABASE_URL` など）

スクリプトは bash のまま残し、別の言語には移植しない。

### レジストリをクラスタ内に置く

`apps/registry` に、Docker Hub の `registry` イメージ（バージョンは固定）で動くレジストリを置く。

- NodePort `30500` で公開し、イメージはノードのローカル PV に保存する
- 認証はかけない。LAN の中だけで使い、Cloudflare Tunnel などで外部には公開しない
- バックアップは取らない。イメージはアプリのリポジトリからいつでも作り直せる
- マニフェストの削除を有効にし、古いイメージはガベージコレクションで手作業で消す

### レジストリを名前で参照する

イメージは `registry.home.lan:30500/<name>:<tag>` という名前で push し、マニフェストもこの名前で参照する。

- この名前を引くのは、push する機械だけである。今は `/etc/hosts` で解決している
- ノードの k3s は `/etc/rancher/k3s/registries.yaml` の mirror で、この名前をノード自身の NodePort（`http://127.0.0.1:30500`）に対応付ける。ノードでは名前を引けなくてよい
- マニフェストに IP アドレスを書かずに済む

### 動かすタグをマニフェストで固定する

各アプリの `kustomization.yaml` の `images` で、`newName` にレジストリ上の名前、`newTag` にアプリの commit のハッシュを書く。デプロイは `newTag` を書き換えて apply するだけにする。`imagePullPolicy: Never` は外し、ノードに無いタグは取得させる。

### DB の払い出しをアプリに依存しない手順にする

`scripts/postgres/provision.sh <app-dir>` は、`apps/<app-dir>/secrets.env` の `DATABASE_URL` からロール名、パスワード、DB 名を読み取る。そのうえで、ロールと、そのロールが所有する DB を作る。

- スキーマは作らない。DB の所有者であれば、アプリが自分でスキーマを作れる
- 値は SQL に埋め込まず psql 変数で渡し、`format()` の `%I` と `%L` で引用する
- 何度実行してもよい。ロールが既にあれば、パスワードを `DATABASE_URL` に合わせる

共有 PostgreSQL の構築は `scripts/postgres/setup.sh` に分け、`deploy.sh` に残すのはマニフェストの適用、状態の確認、ログの表示だけにする。

### マイグレーションをマニフェストに書かない

マイグレーションを流す initContainer は置かない。limnosrv は起動時に DB を待ち、マイグレーションを当ててから listen するので、Deployment にはその間に liveness で再起動されないよう startupProbe を置く。

### 採用しなかった選択肢

- **スクリプトを Go、Deno（dax）、Ruby などに移植する**: 責任の境界を直せばスクリプトが小さくなり、移植する必要がなくなる
- **GitHub Container Registry と GitHub Actions を使う**: GitHub への依存をこれ以上増やしたくない。自宅のクラスタへ外から push させる入口も無い
- **`docker save`、`scp`、`k3s ctr images import` をアプリのリポジトリに移す**: 今度はアプリがこのクラスタの内部（ssh や containerd）を知ることになり、問題の向きが逆になるだけである
- **レジストリを Cloudflare Tunnel で公開する**: 大きなレイヤのアップロードが Cloudflare のリクエストの大きさの上限に当たるおそれがある。公開範囲も広がる

## Consequences

### メリット

- どのビルドが動いているかをマニフェストから読み取れる。ロールバックは `newTag` を戻して apply するだけで済む
- `deploy.sh` が小さくなり、アプリの内部を知らなくなった
- DB の払い出しは、パスワードに `'` が含まれても壊れず、ほかのアプリにも使える
- レジストリが止まっても、動いている Pod と、ノードに取得済みのイメージでの再起動には影響しない。影響を受けるのは、新しいタグの取得だけである

### デメリット・制約

- レジストリには認証が無いので、LAN の中の機械からは誰でも push も削除もできる
- 古いイメージは自動では消えない。タグのマニフェストを削除してから、ガベージコレクションを手で実行する（手順は `apps/registry/README.md`）
- リポジトリの外の設定が前提になる。ノードの `registries.yaml` と k3s の再起動、push する機械の `/etc/hosts`、Docker の `insecure-registries`、macOS のローカルネットワークの許可である。いずれも手順を `apps/registry/README.md` に残す
- レジストリ自身のイメージは Docker Hub から取得する

### 今後の検討事項

- 古いイメージの保持ポリシーを設定で決めたくなったら、レジストリを Zot に差し替えることを検討する
- ベースイメージなどの Docker Hub への依存を減らしたくなったら、このレジストリをプルスルーキャッシュとしても使うことを検討する
- アプリを Cloud Run に移すと、イメージは Artifact Registry に置くことになる。k3s が Artifact Registry から取得する場合は、認証の扱いを決める必要がある（アクセストークンはおよそ 1 時間で失効する）
- 共有 PostgreSQL を使うアプリが増えたら、CloudNativePG などの Operator による宣言的な払い出しを検討する
