# registry

limno などのアプリのコンテナイメージを置く、クラスタ内のコンテナレジストリ（Docker Hub の `registry`）を管理する。
イメージは `registry.home.lan:30500/<name>:<tag>` という名前で push し、マニフェストからもこの名前で参照する。
k3s はノード上の `registries.yaml` で、この名前をノード自身の NodePort に対応付けて pull する。

## 前提

- 認証はかけていない。NodePort なので、LAN 内の機械からは push も削除もできる。Cloudflare Tunnel などで外部に公開しない
- バックアップは取らない。イメージは各アプリのリポジトリから作り直せる
- レジストリが止まっても、動いている Pod と、ノードに取得済みのイメージでの再起動には影響しない。影響を受けるのは新しいタグの pull だけである
- レジストリ自身のイメージは Docker Hub から取得する

## 含まれるリソース

- `deployment.yaml`：レジストリ本体。イメージの保存先 `/var/lib/registry` に PVC をマウントする
- `service.yaml`：NodePort `30500`
- `pv.yaml.example`、`pvc.yaml`：ノードの `/home/micheam/registry-data` を使うローカル PV。`pv-local.yaml` は `scripts/setup/init-local.sh` が作る
- `config.env`：`REGISTRY_STORAGE_DELETE_ENABLED=true`。マニフェストを削除できるようにして、古いイメージを掃除できるようにする

## 構築

ローカル PV はディレクトリが先にないと Pod が起動しないので、ノードに保存先を作ってから適用する。

```bash
ssh -t <k3s-node> sudo mkdir -p /home/micheam/registry-data
./scripts/setup/init-local.sh   # apps/registry/pv-local.yaml を作る
kubectl kustomize apps/registry/ | ssh <k3s-node> 'KUBECONFIG=$HOME/.kube/config kubectl apply -f -'
```

### k3s ノードの設定

k3s がこのレジストリから pull できるよう、ノードに `/etc/rancher/k3s/registries.yaml` を置いて k3s を再起動する。
`registry.home.lan:30500` をノード自身の NodePort に対応付けるので、ノードではこの名前を引けなくてよい。
k3s を再起動しても、動いている Pod は止まらない。

ノードに SSH して実行する。

```bash
sudo tee /etc/rancher/k3s/registries.yaml >/dev/null <<'EOF'
mirrors:
  "registry.home.lan:30500":
    endpoint:
      - "http://127.0.0.1:30500"
EOF
sudo systemctl restart k3s
```

### push する機械の設定

- `/etc/hosts` に `192.168.1.23 registry.home.lan` を足す
- HTTP で push するので、Docker Desktop の Settings → Docker Engine で `insecure-registries` に `"registry.home.lan:30500"` を足して Apply & restart する

## 確認

```bash
curl http://registry.home.lan:30500/v2/_catalog
curl http://registry.home.lan:30500/v2/<name>/tags/list
ssh -t <k3s-node> sudo k3s crictl pull registry.home.lan:30500/<name>:<tag>   # ノードから pull できるか
```

ノードから pull できないときは、k3s が `registries.yaml` を読み込んだかを確かめる。
読み込んでいれば、次のファイルに `http://127.0.0.1:30500` が書かれている。

```bash
ssh -t <k3s-node> sudo cat '/var/lib/rancher/k3s/agent/etc/containerd/certs.d/registry.home.lan:30500/hosts.toml'
```

## 古いイメージの掃除

レジストリは古いイメージを自動では消さない。タグのマニフェストを削除してから、ガベージコレクションで参照されなくなったレイヤを消す。

- マニフェストで指定しているタグは消さない。ノードのキャッシュから消えたあとで Pod を作り直すと、pull できなくなる
- マニフェストは digest で削除するので、同じ digest を指す別のタグも一緒に消える
- ガベージコレクションの最中に push されたレイヤは消される恐れがあるので、push していないときに行う

digest を取るときは `Accept` に OCI と Docker の形式を並べる。付けないと、レジストリが形式を合わせようとして、タグが指すものとは別のマニフェストの digest を返すことがある。

```bash
R=http://registry.home.lan:30500
name=limnosrv tag=<消すタグ>
ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'
digest=$(curl -sI -H "Accept: $ACCEPT" "$R/v2/$name/manifests/$tag" | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}' | tr -d '\r')
curl -X DELETE "$R/v2/$name/manifests/$digest"   # 202 が返れば削除できた

ssh <k3s-node> 'KUBECONFIG=$HOME/.kube/config kubectl exec -n registry deploy/registry -- registry garbage-collect --delete-untagged /etc/distribution/config.yml'
```

## 更新

レジストリのバージョンは `kustomization.yaml` の `images` で固定している。
