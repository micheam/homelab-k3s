#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# limnosrv デプロイ管理スクリプト
#
# Usage: ./scripts/limnosrv/deploy.sh <command> [args]
#
# 動かすイメージのタグは apps/limnosrv/kustomization.yaml の images で宣言する。
# 初回は先に次を実行して、共有 PostgreSQL と limnosrv 用のロール・データベースを用意する。
#   ./scripts/postgres/setup.sh
#   ./scripts/postgres/provision.sh limnosrv
# ============================================================================

# --- 設定 -------------------------------------------------------------------
K3S_NODE="${K3S_NODE:-192.168.1.23}"
K3S_USER="${K3S_USER:-micheam}"
NAMESPACE="${NAMESPACE:-limno}"
PG_NAMESPACE="${PG_NAMESPACE:-postgres}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APP_DIR="${REPO_ROOT}/apps/limnosrv"

# --- ヘルパー ---------------------------------------------------------------
info()  { echo "==> $*"; }
die()   { echo "ERROR: $*" >&2; exit 1; }

# ローカルの kubeconfig は読み取り専用のため、書込みを伴う kubectl はノード上で実行する。
# k3s 同梱の kubectl は KUBECONFIG 未設定だと /etc/rancher/k3s/k3s.yaml を優先するので明示する。
kubectl_node() { ssh "${K3S_USER}@${K3S_NODE}" "KUBECONFIG=\$HOME/.kube/config kubectl $(printf '%q ' "$@")"; }

# --- サブコマンド ------------------------------------------------------------

cmd_deploy() {
    info "limnosrv マニフェストを適用"
    kubectl kustomize "${APP_DIR}" | kubectl_node apply -f -

    # limnosrv は起動時に DB を最大 60 秒待ち、マイグレーションを当ててから listen する
    info "ロールアウト完了を待機中..."
    kubectl rollout status deployment/limnosrv -n "${NAMESPACE}" --timeout=180s

    info "デプロイ完了!"
    cmd_status
}

cmd_status() {
    echo "--- postgres namespace ---"
    kubectl get pods,svc -n "${PG_NAMESPACE}" 2>/dev/null || echo "(not found)"
    echo ""
    echo "--- limno namespace ---"
    kubectl get pods,svc -n "${NAMESPACE}" 2>/dev/null || echo "(not found)"
}

cmd_logs() {
    local target="${1:-limnosrv}"
    local flags="${2:---tail=50}"

    case "${target}" in
        limnosrv|srv)
            kubectl logs -n "${NAMESPACE}" -l app=limnosrv "${flags}" ;;
        postgres|pg)
            kubectl logs -n "${PG_NAMESPACE}" -l app=postgres "${flags}" ;;
        *)
            die "不明なターゲット: ${target} (limnosrv|postgres)" ;;
    esac
}

cmd_help() {
    cat <<'HELP'
Usage: deploy.sh <command> [args]

Commands:
  deploy     マニフェストを適用し、ロールアウトの完了を待つ
             (動かすタグは apps/limnosrv/kustomization.yaml の newTag を書き換えて指定する)
  status     Pod / Service の状態確認
  logs       ログ表示 (deploy.sh logs [limnosrv|postgres] [--tail=N])
  help       このヘルプを表示

Environment Variables:
  K3S_NODE       k3s ノードの IP アドレス (default: 192.168.1.23)
  K3S_USER       SSH ユーザー名 (default: micheam)
  NAMESPACE      limnosrv の namespace (default: limno)
  PG_NAMESPACE   PostgreSQL の namespace (default: postgres)
HELP
}

# --- メイン ------------------------------------------------------------------
command="${1:-help}"
shift || true

case "${command}" in
    deploy)   cmd_deploy "$@" ;;
    status)   cmd_status "$@" ;;
    logs)     cmd_logs "$@" ;;
    help)     cmd_help ;;
    *)        die "不明なコマンド: ${command} ($0 help を参照)" ;;
esac
