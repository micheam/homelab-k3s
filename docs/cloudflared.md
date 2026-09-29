# Cloudflare Tunnel

k3s 上のアプリを、ルーターのポートを開けずにインターネットへ公開するための Cloudflare Tunnel の構成と手順をまとめる。

## 構成

- トンネルは `homelab-k3s` の 1 本だけを使う。公開するアプリは、すべてこのトンネルのルートとして足す
- トンネルはダッシュボードで管理する（remotely-managed）。ルートの設定は Cloudflare 側に保存され、このリポジトリには入らない
- cloudflared は `apps/cloudflared/` の Deployment として、namespace `cloudflared` で 2 レプリカ動かす
- cloudflared はトンネルのトークン（環境変数 `TUNNEL_TOKEN`）で Cloudflare に接続する。トークンは SOPS で暗号化した `apps/cloudflared/secrets.enc.env` で管理する
- cloudflared は Cloudflare へ外向きに接続するだけなので、Service は作らない

k3s のノードは 1 台なので、2 レプリカはノードの障害には効かない。
ロールアウトや Pod の再起動の間も、どちらかの Pod がトンネルにつながっているようにするためのものである。

## ルート一覧

ダッシュボードのルートと、この表を一致させておく。

| ホスト名 | Service URL |
| --- | --- |
| limno.micheam.com | http://limnosrv.limno.svc.cluster.local:8080 |

補足:

- ホスト名は、ゾーンの apex か 1 階層目のサブドメインにする。Universal SSL の証明書はそこまでしか対象にしないので、`a.b.micheam.com` のような名前では TLS の接続に失敗する
- ゾーンは、トンネルと同じ Cloudflare アカウントにあれば `micheam.com` 以外でもよい
- Service URL には、クラスタ内の Service の DNS 名（`<service>.<namespace>.svc.cluster.local`）を書く
- limnosrv の NodePort（30080）は、LAN のクライアントが直接つなぐためのものである。トンネルは NodePort を使わない

## 初期構築

### 1. トンネルを作る

Cloudflare のダッシュボードで **Networking > Tunnels** を開き、**Create a tunnel** からトンネル `homelab-k3s` を作る。
続いて表示されるインストールコマンドの、`eyJ` で始まる長い文字列がトークンである。
OS はどれを選んでもよい（トークンは同じ）。
あとで確認するときは、トンネルの **Overview** で **Add a replica** を選ぶと同じコマンドが表示される。

ルートは手順 4 で足す。
作成の流れでルートの入力を求められたら、手順 4 の値をここで入れてもよい。
cloudflared がつながるまでは、そのホスト名への要求に 530 が返るだけである。

### 2. トークンを暗号化する

インストールコマンドをコピーしてから、次を実行する。
コマンド全体をコピーしても、トークンだけをコピーしてもよい。
トークンは画面にもシェルの履歴にも残らない。

```bash
pbpaste | grep -oE 'eyJ[A-Za-z0-9+/=_-]+' | sed 's/^/TUNNEL_TOKEN=/' > apps/cloudflared/secrets.env
grep -c '^TUNNEL_TOKEN=eyJ' apps/cloudflared/secrets.env  # 1 と表示されればよい
sops encrypt apps/cloudflared/secrets.env > apps/cloudflared/secrets.enc.env
```

暗号化した `secrets.enc.env` はコミットする。
平文の `secrets.env` は `.gitignore` で除外されている。

### 3. cloudflared を動かす

```bash
kubectl kustomize apps/cloudflared/ | ssh <k3s-node> 'KUBECONFIG=$HOME/.kube/config kubectl apply -f -'
kubectl -n cloudflared rollout status deployment/cloudflared
kubectl -n cloudflared logs -l app=cloudflared --prefix --tail=20
```

ログに `Registered tunnel connection` が並べば、Cloudflare に接続できている。
ダッシュボードのトンネルの Overview にも、Pod ごとにコネクタが表示される。

起動時に `ping_group_range` や ICMP proxy に触れる警告（`WRN`）が出るが、無視してよい。
ICMP を中継する機能のためのもので、ルートでアプリを公開するだけなら使わない。

### 4. ルートを足す

トンネルの **Routes** で **Add route** > **Published application** を選び、ルート一覧の表のとおりに入力する。

- Subdomain：`limno`
- Domain：`micheam.com`
- Service URL：`http://limnosrv.limno.svc.cluster.local:8080`

DNS の CNAME レコードは自動で作られる。
cloudflared は新しい設定を自動で受け取るので、Pod を再起動する必要はない。
ログに `Updated to new configuration` が出れば反映されている。

### 5. 外から確かめる

```bash
curl -i -X POST https://limno.micheam.com/limno.v1.SyncService/PullNotes \
  -H 'Content-Type: application/json' -d '{}'
```

API キーを付けていないので、limnosrv まで届けば `401` と JSON（`"code":"unauthenticated"`）が返る。
ホスト名は Cloudflare の IP アドレスに解決されるので、LAN の中から実行しても、要求はトンネルを通る。

| 応答 | 止まった場所 |
| --- | --- |
| 401 と JSON | limnosrv（正常） |
| HTML の 403 / 503 | Cloudflare |
| 502 | cloudflared から Service URL |
| 530（error 1033） | トンネル |

補足:

- HTML の 403 / 503 は、Bot Fight Mode や WAF のルールがブラウザ以外のクライアントを止めている。ダッシュボードのセキュリティのイベント一覧で、止めたルールを確かめる
- 502 は、cloudflared が Service URL に接続できていない。Service 名、namespace、ポートを確かめる
- 530 は、トンネルにつながっている cloudflared が 1 つもない。Pod の状態とログを確かめる

## 別のアプリを公開する

cloudflared のマニフェストは変えない。
ダッシュボードにルートを足すだけで公開できる。

1. アプリの Service を作る（ClusterIP でよい）
2. トンネルの Routes で Published application を足し、ホスト名と Service URL を入力する
3. この文書のルート一覧に行を足す

ルートを足したアプリは、インターネットの誰からでも要求を受ける。
認証はアプリの側で必ず行う（limnosrv は API キーで認証している）。

## cloudflared を更新する

イメージのタグは、`apps/cloudflared/kustomization.yaml` の `newTag` だけで指定している（`deployment.yaml` にはタグを書かない）。

1. [リリース](https://github.com/cloudflare/cloudflared/releases)を確かめ、`newTag` を書き換える
2. ノードは arm64 なので、そのタグに linux/arm64 のイメージがあることを確かめる
3. 初期構築の手順 3 と同じく適用する

```bash
docker manifest inspect cloudflare/cloudflared:<tag> | jq -r '.manifests[].platform | "\(.os)/\(.architecture)"'
```

ロールアウトでは新しい Pod が先に起動し、Cloudflare につながってから古い Pod が止まる。
そのため、更新の間もどちらかの Pod がつながっている。

## トークンを更新する

トークンがあれば、誰でもこのトンネルのコネクタを動かせる。
つまり、公開中のホスト名への要求を受け取れてしまう。

1. トンネルの Overview で **Refresh token** を選び、新しいインストールコマンドをコピーする
2. 初期構築の手順 2 と 3 のとおりに、暗号化して適用する

Refresh token のあとも、既存のコネクタはつながったまま動く。
古いトークンで新しく接続できなくなるだけなので、Pod が入れ替わるまでトンネルは切れない。
Secret の名前にはハッシュが付くので、適用すると Deployment のロールアウトが自動で始まる。

トークンが漏れた場合は、既存の接続を切る手順も要る（漏れたトークンで動いているコネクタも、つながったまま残るため）。
Cloudflare の文書の [Tunnel permissions](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/remote-tunnel-permissions/) に従う。

## マニフェストの補足

[Cloudflare の文書にある Deployment の例](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/kubernetes/)を元にしている。
例と違う点は次のとおり。

- readiness probe を足した。`/ready` は Cloudflare への接続が 1 本以上あるときだけ 200 を返すので、ロールアウトでは新しい Pod がつながるまで古い Pod が残る
- liveness probe は、例の `failureThreshold: 1` を 6 にした。瞬断のたびには再起動せず、1 分つながらないときだけ再起動する
- ICMP の中継に使う sysctl（`net.ipv4.ping_group_range`）は入れていない
- securityContext は Cloudflare の Helm チャートの既定値に合わせた。root 以外のユーザーで動かし、ルートファイルシステムを読み取り専用にする

## TODO: ルートを設定ファイルで管理する

limno を外部の gateway から使うようになる前（limno の Phase 2 の前）に、ルートの設定を Git で管理できるようにする。
ダッシュボードで管理している間は、ルートの変更がこのリポジトリに残らない。

方法は次の 2 つが候補で、着手するときに決める。

- 設定ファイルで動かすトンネル（locally-managed）に切り替える。ルートは ConfigMap の `config.yaml` に書き、変更はロールアウトで反映する
- ダッシュボードで管理したまま、Terraform などでトンネルの設定をコードにする
