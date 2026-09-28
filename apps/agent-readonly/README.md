# agent-readonly

コーディングエージェント（Claude Code、Codex など）がクラスタを読み取るための ServiceAccount と RBAC を管理する。
Mac の `~/.kube/config` はこの ServiceAccount のトークンで接続するので、そこから実行した kubectl はクラスタに書込みできない。
書込みは k3s ノードに SSH して行う前提としている。

## 含まれるリソース

- `serviceaccount.yaml`：ServiceAccount `agent-readonly` と、その長期トークンを保持する Secret `agent-readonly-token`（どちらも `kube-system`）
- `clusterrole.yaml`：組み込みの `view` に含まれない読み取り権限を補う ClusterRole `agent-readonly-extra`
- `clusterrolebinding.yaml`：`view` と `agent-readonly-extra` を ServiceAccount に割り当てる ClusterRoleBinding

## 権限の範囲

読めるものは次のとおり。

- `view` の範囲（namespace 内のワークロード、ConfigMap、PVC、Event、Pod のログ、`kubectl top`）
- Node と PersistentVolume
- `clusterrole.yaml` に列挙した API グループのリソース（StorageClass、CRD、RBAC、Traefik、k3s の HelmChart など）

次の操作はできない。

- Secret の読み取り
- リソースの作成、変更、削除
- `kubectl exec`、`attach`、`port-forward`
- `kubectl diff` と `--dry-run=server`（サーバー側の dry-run にも書込み権限が必要なため）

Secret を読めないようにしているのは、Secret の値がエージェント経由で LLM のプロバイダに送られるのを避けるためである。
加えて、ServiceAccount のトークンを読めると、そのトークンの権限で書込みができてしまう。

## 権限を追加するときの注意

core グループ（`apiGroups: [""]`）には `resources: ["*"]` を指定せず、リソースを列挙する。
RBAC には許可を足す仕組みしかないので、`*` を指定すると Secret も読めるようになる。
Secret は core グループのリソースなので、それ以外の API グループは `*` でまとめて許可している。

## 適用

管理者権限が必要なので、ローカルでマニフェストを組み立てて k3s ノード上で適用する。

```bash
kubectl kustomize apps/agent-readonly/ | ssh <k3s-node> 'KUBECONFIG=$HOME/.kube/config kubectl apply -f -'
```

## エージェント用 kubeconfig の作成

トークンと CA 証明書をノードから取得し、`~/.kube/config` を作る。
トークンは Secret の適用から少し遅れて書き込まれるので、空の場合は時間をおいて取得し直す。

```bash
node_kubectl() { ssh <k3s-node> "KUBECONFIG=\$HOME/.kube/config kubectl $(printf '%q ' "$@")"; }
TOKEN=$(node_kubectl -n kube-system get secret agent-readonly-token -o jsonpath='{.data.token}' | base64 -d)
CA=$(node_kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

cat > ~/.kube/config <<EOF
apiVersion: v1
kind: Config
clusters:
- name: homelab
  cluster: {server: "https://192.168.1.23:6443", certificate-authority-data: "${CA}"}
users:
- name: agent-readonly
  user: {token: "${TOKEN}"}
contexts:
- name: homelab-ro
  context: {cluster: homelab, user: agent-readonly}
current-context: homelab-ro
EOF
chmod 600 ~/.kube/config
```

権限は次のように確認できる。

```bash
kubectl auth can-i --list
kubectl auth can-i get secrets -A                   # no になる
kubectl auth can-i create deployments -n minecraft  # no になる
```

## トークンの無効化

Secret `agent-readonly-token` を削除すると、そのトークンは使えなくなる。
マニフェストを適用し直すと新しいトークンが発行されるので、kubeconfig を作り直す。
