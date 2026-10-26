#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# 共有 PostgreSQL を構築する
#
# Usage: ./scripts/postgres/setup.sh
#
# アプリ用のロールとデータベースは scripts/postgres/provision.sh で払い出す。
# ============================================================================

# --- 設定 -------------------------------------------------------------------
K3S_NODE="${K3S_NODE:-192.168.1.23}"
K3S_USER="${K3S_USER:-micheam}"
PG_NAMESPACE="${PG_NAMESPACE:-postgres}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
POSTGRES_DIR="${REPO_ROOT}/apps/postgres"

# --- ヘルパー ---------------------------------------------------------------
info()  { echo "==> $*"; }

ssh_node() { ssh -t "${K3S_USER}@${K3S_NODE}" "$@"; }

# ローカルの kubeconfig は読み取り専用のため、書込みを伴う kubectl はノード上で実行する。
# k3s 同梱の kubectl は KUBECONFIG 未設定だと /etc/rancher/k3s/k3s.yaml を優先するので明示する。
kubectl_node() { ssh "${K3S_USER}@${K3S_NODE}" "KUBECONFIG=\$HOME/.kube/config kubectl $(printf '%q ' "$@")"; }

# --- メイン ------------------------------------------------------------------
info "共有 PostgreSQL セットアップ"

if [ ! -f "${POSTGRES_DIR}/pv-local.yaml" ]; then
    info "pv-local.yaml を作成 (pv.yaml.example からコピー)"
    cp "${POSTGRES_DIR}/pv.yaml.example" "${POSTGRES_DIR}/pv-local.yaml"
    info "必要に応じて編集してください: ${POSTGRES_DIR}/pv-local.yaml"
fi

info "k3s ノード上にデータディレクトリを作成"
ssh_node "sudo mkdir -p /home/micheam/postgres-data && sudo chown -R 999:999 /home/micheam/postgres-data"

info "PostgreSQL マニフェストを適用"
kubectl kustomize "${POSTGRES_DIR}" | kubectl_node apply -f -

info "PostgreSQL の起動を待機中..."
kubectl wait --for=condition=ready pod -l app=postgres -n "${PG_NAMESPACE}" --timeout=120s

info "PostgreSQL セットアップ完了!"
