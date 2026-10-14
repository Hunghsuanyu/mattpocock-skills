#!/usr/bin/env bash
# 用法：pr-open.sh <owner/repo> <base> <head> <標題檔> <內文檔>
#
# 開 PR 一律經這支：公開 repo 開之前掃一次標題＋內文，開完讀回再掃一次；沒過就不開。
#   ① 可見度：`gh repo view` 回 PRIVATE → 不掃，直接開。讀不到或回其他值 → 一律當公開。
#   ② 掃描器（不另設變數）：
#      - 內建檢查一律跑：擋票號的各種寫法（owner/repo、短名、裸的「井號＋數字」、全形井號＋數字、
#        `GH-<數字>`、`github.com/<owner>/<repo>/(issues|pull)/<數字>` 網址；公開 repo 的 PR 不寫票號，不需要私有清單）。
#      - 有私有擴充（GITHUB_WORKFLOW_PRIVATE_DIR 非空）→ 內建檢查過了之後，再跑該目錄裡的 pr-scan.sh：
#        標準輸入餵「標題＋換行＋內文」，退出碼非 0＝沒過。私有掃描只加不取代內建檢查。
#        有私有擴充卻沒有 pr-scan.sh → 不開。
#   ③ 開前沒過 → 不呼叫 gh pr create。開完讀回失敗、或讀回的內容沒過 → 印 PR 網址交擁有者處理。
#
# 退出碼：0 開好了（印 PR 網址）；1 沒開，或開了但讀回沒過；64 參數錯。
set -uo pipefail

pro_usage() { echo "用法：pr-open.sh <owner/repo> <base> <head> <標題檔> <內文檔>" >&2; exit 64; }
[ $# -eq 5 ] || pro_usage
REPO="$1" BASE="$2" HEAD="$3" TITLE_F="$4" BODY_F="$5"
case "${REPO}" in */*) ;; *) pro_usage ;; esac
for f in "${TITLE_F}" "${BODY_F}"; do [ -r "${f}" ] || { echo "pr-open: 讀不到 ${f}" >&2; exit 64; }; done
TITLE="$(cat "${TITLE_F}")"
[ -n "${TITLE}" ] || { echo "pr-open: 標題是空的" >&2; exit 64; }

T="$(mktemp -d)" || exit 9
trap 'rm -rf "${T}"' EXIT

# 內建檢查：票號寫法都擋（fail-closed：公開上游的 owner/repo＋井號＋數字也會被擋，接受）。
#   owner/repo＋井號＋數字；短名＋井號＋數字（前面不是英數、底線、斜線）；
#   裸的井號（連續幾個都算，例如兩個井號＋數字）＋數字（前面不是英數、底線、斜線、井號、&——`&`＋井號＋數字是 HTML 字元參照）；
#   全形井號（＃）＋數字；GH-數字；github.com/<owner>/<repo>/(issues|pull)/數字（host 可帶 www.）。
#   以上的後面都不是英數、底線；整組不分大小寫（`GitHub.com`、`gh-5` 都擋）。
# 乾淨 → 0；命中 → 1；grep 自己失敗 → 也是 1（量不到不算乾淨）。
pro_builtin_scan() {
  LC_ALL=C grep -inE \
    -e '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+([^A-Za-z0-9_]|$)' \
    -e '(^|[^A-Za-z0-9_/])[A-Za-z][A-Za-z0-9_-]*#[0-9]+([^A-Za-z0-9_]|$)' \
    -e '(^|[^A-Za-z0-9_/#&])#+[0-9]+([^A-Za-z0-9_]|$)' \
    -e '＃[0-9]+([^A-Za-z0-9_]|$)' \
    -e '(^|[^A-Za-z0-9_])[Gg][Hh]-[0-9]+([^A-Za-z0-9_]|$)' \
    -e 'github\.com/[^/[:space:]]+/[^/[:space:]]+/(issues|pull)/[0-9]+([^A-Za-z0-9_]|$)' "$1" >&2
  [ $? -eq 1 ]
}

# 參數：要掃的檔。沒過 → 非 0（原因印在 stderr）。內建檢查一律先跑；有私有擴充再加跑 pr-scan.sh。
pro_scan() {
  local dir="${GITHUB_WORKFLOW_PRIVATE_DIR:-}"
  pro_builtin_scan "$1" || { echo "pr-open: 內建檢查擋下票號（公開 repo 的 PR 不寫票號）" >&2; return 1; }
  [ -n "${dir}" ] || return 0
  if [ ! -f "${dir}/pr-scan.sh" ]; then
    echo "pr-open: 有私有擴充（${dir}）卻讀不到 pr-scan.sh，不掃就不開" >&2
    return 1
  fi
  bash "${dir}/pr-scan.sh" < "$1" >&2 || { echo "pr-open: 私有擴充的 pr-scan.sh 沒過" >&2; return 1; }
}

# ── ① 可見度 ──
vis="$(gh repo view "${REPO}" --json visibility --jq .visibility 2> "${T}/vis.err")"; vis_rc=$?
if [ "${vis_rc}" -eq 0 ] && [ "${vis}" = PRIVATE ]; then
  public=0
else
  public=1
  [ "${vis_rc}" -eq 0 ] || { echo "pr-open: 讀不到 ${REPO} 的可見度，照公開處理：" >&2; cat "${T}/vis.err" >&2; }
fi

# ── ② 開之前掃 ──
if [ "${public}" = 1 ]; then
  { printf '%s\n' "${TITLE}"; cat "${BODY_F}"; } > "${T}/pre.txt"
  pro_scan "${T}/pre.txt" || { echo "pr-open: 開 PR 前掃描沒過，沒有開" >&2; exit 1; }
fi

# ── ③ 開 ──
url="$(gh pr create -R "${REPO}" --base "${BASE}" --head "${HEAD}" --title "${TITLE}" --body-file "${BODY_F}")" \
  || { echo "pr-open: gh pr create 失敗" >&2; exit 1; }
[ "${public}" = 1 ] || { printf '%s\n' "${url}"; exit 0; }

# ── ④ 公開 repo：讀回再掃 ──
if ! gh pr view "${url}" -R "${REPO}" --json title,body --jq '.title + "\n" + .body' > "${T}/post.txt" 2> "${T}/post.err"; then
  echo "pr-open: PR 已開但讀不回來，讀回失敗也算沒過，交擁有者處理：${url}" >&2
  cat "${T}/post.err" >&2
  printf '%s\n' "${url}"
  exit 1
fi
if ! pro_scan "${T}/post.txt"; then
  echo "pr-open: PR 已開但讀回的內容沒過掃描，交擁有者處理：${url}" >&2
  printf '%s\n' "${url}"
  exit 1
fi
printf '%s\n' "${url}"
