#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# 共有 PostgreSQL に、アプリ用のロールとデータベースを払い出す
#
# Usage: ./scripts/postgres/provision.sh <app-dir>
#   例: ./scripts/postgres/provision.sh limnosrv
#
# apps/<app-dir>/secrets.env の DATABASE_URL から、ロール名・パスワード・データベース名を取る。
# ロールが無ければ作り、あればパスワードを DATABASE_URL に合わせる。
# データベースが無ければ、そのロールを所有者として作る。スキーマはアプリが作る。
# ============================================================================

# --- 設定 -------------------------------------------------------------------
K3S_NODE="${K3S_NODE:-192.168.1.23}"
K3S_USER="${K3S_USER:-micheam}"
PG_NAMESPACE="${PG_NAMESPACE:-postgres}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- ヘルパー ---------------------------------------------------------------
info()  { echo "==> $*"; }
die()   { echo "ERROR: $*" >&2; exit 1; }

# ローカルの kubeconfig は読み取り専用のため、書込みを伴う kubectl はノード上で実行する。
# k3s 同梱の kubectl は KUBECONFIG 未設定だと /etc/rancher/k3s/k3s.yaml を優先するので明示する。
kubectl_node() { ssh "${K3S_USER}@${K3S_NODE}" "KUBECONFIG=\$HOME/.kube/config kubectl $(printf '%q ' "$@")"; }

# URL の %xx を元の文字に戻す。値に含まれる \ は printf に解釈させない
urldecode() {
    local s="${1//\\/\\\\}"
    printf '%b' "${s//%/\\x}"
}

# --- メイン ------------------------------------------------------------------
app_dir="${1:-}"
[ -n "${app_dir}" ] || die "Usage: $0 <app-dir>  (例: $0 limnosrv)"

secrets="${REPO_ROOT}/apps/${app_dir}/secrets.env"
[ -f "${secrets}" ] || die "${secrets} がありません。先に scripts/setup/init-local.sh で復号してください"

db_url=$(grep '^DATABASE_URL=' "${secrets}" | cut -d= -f2- || true)
re='^postgres(ql)?://([^:@/]+):([^@]*)@[^/]+/([^?]+)'
[[ "${db_url}" =~ ${re} ]] \
    || die "${secrets} の DATABASE_URL を読めません (postgres://<role>:<password>@<host>/<database> の形にする)"
role=$(urldecode "${BASH_REMATCH[2]}")
pass=$(urldecode "${BASH_REMATCH[3]}")
db=$(urldecode "${BASH_REMATCH[4]}")
[ -n "${pass}" ] || die "${secrets} の DATABASE_URL にパスワードがありません"

pg_pod=$(kubectl get pod -n "${PG_NAMESPACE}" -l app=postgres --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
[ -n "${pg_pod}" ] || die "PostgreSQL が起動していません。先に scripts/postgres/setup.sh を実行してください"

info "ロール ${role} とデータベース ${db} を払い出す"
# 値は SQL に埋め込まず psql 変数で渡し、format() の %I / %L で引用する
kubectl_node exec -i -n "${PG_NAMESPACE}" "${pg_pod}" -- \
    psql -U postgres -v ON_ERROR_STOP=1 -v role="${role}" -v pass="${pass}" -v db="${db}" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN', :'role')
  WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'role') \gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'role', :'pass') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'role')
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db') \gexec
SQL

info "払い出し完了: ${role}@${db}"
