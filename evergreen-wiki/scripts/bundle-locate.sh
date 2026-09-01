#!/usr/bin/env bash
# evergreen-wiki/scripts/bundle-locate.sh — OKF bundle の発見
# 出力: <scope>\t<bundle絶対パス>(1行1 bundle)。見つからなくても exit 0
set -euo pipefail
SCOPE=all; ROOT="$PWD"
while [ $# -gt 0 ]; do case "$1" in
  --scope) SCOPE=$2; shift 2 ;;
  --root)  ROOT=$2;  shift 2 ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac; done
USER_BUNDLE="${EVERGREEN_USER_BUNDLE:-$HOME/knowledge}"

# okf_version frontmatter を持つ index.md があるディレクトリだけが bundle
is_bundle() {
  [ -f "$1/index.md" ] || return 1
  # 単一 awk で判定する。awk | grep -q だと grep の早期 exit 後の書き込みが SIGPIPE になり、
  # pipefail 下で bundle が「発見されないまま exit 0」で終わる偽陰性を生むため
  awk '/^---$/{n++; next} n>=2{exit} n==1 && /^okf_version:/{found=1; exit} END{exit !found}' "$1/index.md"
}
abspath() { (cd "$1" 2>/dev/null && pwd); }

emit_user() {
  if is_bundle "$USER_BUNDLE"; then printf 'user\t%s\n' "$(abspath "$USER_BUNDLE")"; fi
}
emit_project() {
  local top
  top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || abspath "$ROOT" || true)
  [ -n "$top" ] || return 0
  local user_abs; user_abs=$(abspath "$USER_BUNDLE" || true)
  # find は permission-denied なサブツリーがあると非0終了する。パイプで受けると pipefail が
  # それを拾い、bundle を出力済みでもスクリプト全体が exit 1 で死ぬ(発見リストの無音の切り詰め)。
  # process substitution + || true で find の終了コードを無視する
  while read -r f; do
    d=$(dirname "$f")
    [ "$(abspath "$d")" = "${user_abs:-}" ] && continue
    if is_bundle "$d"; then printf 'project\t%s\n' "$(abspath "$d")"; fi
  done < <(find "$top" -maxdepth 4 \
    \( -name node_modules -o -name .git -o -name vendor -o -name dist -o -name build \) -prune \
    -o -name index.md -print 2>/dev/null || true)
}
case "$SCOPE" in
  user) emit_user ;;
  project) emit_project ;;
  all) emit_user; emit_project ;;
  *) echo "invalid --scope: $SCOPE" >&2; exit 2 ;;
esac
exit 0
