#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# limnosrv デプロイ管理スクリプト
#
# Usage: ./scripts/limnosrv/deploy.sh <command> [args]
# ============================================================================

# --- 設定 -------------------------------------------------------------------
K3S_NODE="${K3S_NODE:-192.168.1.23}"
K3S_USER="${K3S_USER:-micheam}"
NAMESPACE="${NAMESPACE:-limno}"
PG_NAMESPACE="${PG_NAMESPACE:-postgres}"
IMAGE_NAME="limnosrv"
IMAGE_TAG="${IMAGE_TAG:-latest}"
NODE_PORT="${NODE_PORT:-30080}"

# リポジトリパス
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
POSTGRES_DIR="${REPO_ROOT}/apps/postgres"
APP_DIR="${REPO_ROOT}/apps/limnosrv"
LIMNO_REPO="${LIMNO_REPO:-$HOME/src/github.com/micheam/limno}"

# --- ヘルパー ---------------------------------------------------------------
info()  { echo "==> $*"; }
warn()  { echo "WARN: $*" >&2; }
die()   { echo "ERROR: $*" >&2; exit 1; }

ssh_node() { ssh -t "${K3S_USER}@${K3S_NODE}" "$@"; }

ensure_postgres() {
    if ! kubectl get pod -n "${PG_NAMESPACE}" -l app=postgres -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
        die "PostgreSQL が起動していません。先に '$0 setup-pg' を実行してください"
    fi
}

ensure_config() {
    local dir="$1" name="$2"
    if [ ! -f "${dir}/config.env" ]; then
        info "${name}: config.env を作成 (config.env.example からコピー)"
        cp "${dir}/config.env.example" "${dir}/config.env"
        warn "config.env を編集してください: ${dir}/config.env"
        warn "編集後に再度コマンドを実行してください"
        return 1
    fi
}

# --- サブコマンド ------------------------------------------------------------

cmd_setup_pg() {
    info "共有 PostgreSQL セットアップ"

    ensure_config "${POSTGRES_DIR}" "postgres"

    if [ ! -f "${POSTGRES_DIR}/pv-local.yaml" ]; then
        info "pv-local.yaml を作成 (pv.yaml.example からコピー)"
        cp "${POSTGRES_DIR}/pv.yaml.example" "${POSTGRES_DIR}/pv-local.yaml"
        info "必要に応じて編集してください: ${POSTGRES_DIR}/pv-local.yaml"
    fi

    info "k3s ノード上にデータディレクトリを作成"
    ssh_node "sudo mkdir -p /home/micheam/postgres-data && sudo chown -R 999:999 /home/micheam/postgres-data"

    info "PostgreSQL マニフェストを適用"
    kubectl apply -k "${POSTGRES_DIR}"

    info "PostgreSQL の起動を待機中..."
    kubectl wait --for=condition=ready pod -l app=postgres -n "${PG_NAMESPACE}" --timeout=120s

    info "PostgreSQL セットアップ完了!"
}

cmd_setup_db() {
    info "limno データベースユーザーとスキーマを作成"
    ensure_postgres
    ensure_config "${APP_DIR}" "limnosrv"

    # limnosrv の config.env から DATABASE_URL を読み取り、パスワードを抽出
    local db_url db_pass
    db_url=$(grep '^DATABASE_URL=' "${APP_DIR}/config.env" | cut -d= -f2-)
    db_pass=$(echo "${db_url}" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
    [ -n "${db_pass}" ] || die "DATABASE_URL からパスワードを抽出できません。limnosrv の config.env を確認してください"

    local pg_pod
    pg_pod=$(kubectl get pod -n "${PG_NAMESPACE}" -l app=postgres -o jsonpath='{.items[0].metadata.name}')

    info "limno ユーザーを作成 (既に存在する場合はパスワードを更新)"
    kubectl exec -n "${PG_NAMESPACE}" "${pg_pod}" -- \
        psql -U postgres -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'limno') THEN CREATE USER limno WITH PASSWORD '${db_pass}'; ELSE ALTER USER limno WITH PASSWORD '${db_pass}'; END IF; END \$\$;"

    info "limno データベースを作成 (既に存在する場合はスキップ)"
    kubectl exec -n "${PG_NAMESPACE}" "${pg_pod}" -- \
        psql -U postgres -c "SELECT 'CREATE DATABASE limno OWNER limno' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'limno')" --tuples-only | \
        kubectl exec -i -n "${PG_NAMESPACE}" "${pg_pod}" -- psql -U postgres

    info "limno スキーマを作成"
    kubectl exec -n "${PG_NAMESPACE}" "${pg_pod}" -- \
        psql -U postgres -d limno -c "CREATE SCHEMA IF NOT EXISTS limno AUTHORIZATION limno;"

    info "DB セットアップ完了!"
}

cmd_import() {
    local tarball="/tmp/${IMAGE_NAME}.tar"

    info "イメージを tarball にエクスポート"
    docker save "${IMAGE_NAME}:${IMAGE_TAG}" -o "${tarball}"

    info "k3s ノードへ転送 (${K3S_USER}@${K3S_NODE})"
    scp "${tarball}" "${K3S_USER}@${K3S_NODE}:/tmp/${IMAGE_NAME}.tar"

    info "k3s にイメージをインポート"
    ssh_node "sudo k3s ctr images import /tmp/${IMAGE_NAME}.tar && rm /tmp/${IMAGE_NAME}.tar"

    rm -f "${tarball}"
    info "イメージインポート完了: ${IMAGE_NAME}:${IMAGE_TAG}"
}

cmd_setup() {
    info "limnosrv 初期セットアップ"

    # 1. PostgreSQL
    if ! kubectl get pod -n "${PG_NAMESPACE}" -l app=postgres -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
        cmd_setup_pg
    else
        info "PostgreSQL は起動済み — スキップ"
    fi

    # 2. DB ユーザー・スキーマ
    cmd_setup_db

    # 3. Docker イメージをビルド (limno リポジトリ側)
    info "limnosrv イメージをビルド (${LIMNO_REPO})"
    make -C "${LIMNO_REPO}" docker IMAGE_TAG="${IMAGE_TAG}"

    # 4. k3s にイメージ転送
    cmd_import

    # 5. limnosrv マニフェスト適用
    info "limnosrv マニフェストを適用"
    kubectl apply -k "${APP_DIR}"

    # 6. Pod の起動待ち
    info "limnosrv の起動を待機中..."
    kubectl wait --for=condition=ready pod -l app=limnosrv -n "${NAMESPACE}" --timeout=120s

    echo ""
    info "セットアップ完了!"
    info "クライアント側で以下を設定:"
    echo "  LIMNO_SYNC_URL=http://${K3S_NODE}:${NODE_PORT}"
    echo "  # ~/.config/limno/env に追加"
}

cmd_deploy() {
    info "limnosrv を更新デプロイ"
    ensure_postgres

    # 1. ビルド (limno リポジトリ側)
    info "limnosrv イメージをビルド (${LIMNO_REPO})"
    make -C "${LIMNO_REPO}" docker IMAGE_TAG="${IMAGE_TAG}"

    # 2. k3s に転送
    cmd_import

    # 3. マニフェスト適用 (ConfigMap 変更があれば反映)
    kubectl apply -k "${APP_DIR}"

    # 4. rollout restart
    info "Deployment をロールアウト再起動"
    kubectl rollout restart deployment/limnosrv -n "${NAMESPACE}"

    info "ロールアウト完了を待機中..."
    kubectl rollout status deployment/limnosrv -n "${NAMESPACE}" --timeout=120s

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

cmd_migrate() {
    info "goose マイグレーションを手動実行"
    ensure_postgres

    local pod
    pod=$(kubectl get pod -n "${NAMESPACE}" -l app=limnosrv -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) \
        || die "limnosrv Pod が見つかりません"

    kubectl exec -n "${NAMESPACE}" "${pod}" -- sh -c \
        'psql "$DATABASE_URL" -c "CREATE SCHEMA IF NOT EXISTS limno;" && goose -dir /migrations -table limno.goose_db_version postgres "$DATABASE_URL" up'
}

cmd_help() {
    cat <<'HELP'
Usage: deploy.sh <command> [args]

Commands:
  setup      初期構築 (PostgreSQL + DB + limnosrv を一括デプロイ)
  setup-pg   共有 PostgreSQL のみセットアップ
  setup-db   limno ユーザー・DB・スキーマを PostgreSQL に作成
  deploy     limnosrv の更新デプロイ (build → import → rollout restart)
  import     ビルド済みイメージを k3s ノードへ転送・インポート
  status     Pod / Service の状態確認
  logs       ログ表示 (deploy.sh logs [limnosrv|postgres] [--tail=N])
  migrate    goose マイグレーションを手動実行
  help       このヘルプを表示

Environment Variables:
  K3S_NODE       k3s ノードの IP アドレス (default: 192.168.1.23)
  K3S_USER       SSH ユーザー名 (default: micheam)
  NAMESPACE      limnosrv の namespace (default: limno)
  PG_NAMESPACE   PostgreSQL の namespace (default: postgres)
  IMAGE_TAG      Docker イメージタグ (default: latest)
  LIMNO_REPO     limno リポジトリのパス (default: ~/src/github.com/micheam/limno)
HELP
}

# --- メイン ------------------------------------------------------------------
command="${1:-help}"
shift || true

case "${command}" in
    setup)    cmd_setup "$@" ;;
    setup-pg) cmd_setup_pg "$@" ;;
    setup-db) cmd_setup_db "$@" ;;
    deploy)   cmd_deploy "$@" ;;
    import)   cmd_import "$@" ;;
    status)   cmd_status "$@" ;;
    logs)     cmd_logs "$@" ;;
    migrate)  cmd_migrate "$@" ;;
    help)     cmd_help ;;
    *)        die "不明なコマンド: ${command} ($0 help を参照)" ;;
esac
