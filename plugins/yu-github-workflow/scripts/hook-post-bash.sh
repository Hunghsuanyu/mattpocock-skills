#!/usr/bin/env bash
# PostToolUse(Bash)：開完票或開完 PR，替人把檢查跑掉、結果放到眼前。
# 一律不擋、退出碼恆 0；只讀 GitHub。命中判法在 lib/hook-common.sh（與 hook-pre-bash.sh 共用）。
#
# 開完票 → 跑 ticket-check.sh。repo 只取自工具輸出裡剛開好的票網址
#   （gh issue create 成功時一定印 https://github.com/<owner>/<repo>/issues/<號>，不帶 -R 也一樣）。
#   不退回 -R／--repo 參數，也不從 cwd 推：建票失敗時拿參數去自檢，會對著沒開成的票報 NG 或全過；
#   clone 有兩個 remote 時從 cwd 推，會對著別的 repo 報全過。沒有網址＝沒開成或沒讀到 → 不跑，明講沒跑。
# 開完 PR → 從輸出取 PR 網址，回查 GitHub 登記的關票清單（closingIssuesReferences）
#   與內文寫的關閉關鍵字是否同一組票；不同就提示（包在反引號裡、目標不是預設分支，GitHub 都不登記）。
# 測試：tests/test-hooks.sh。
HPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 0
# shellcheck source=lib/hook-common.sh
. "${HPO_DIR}/lib/hook-common.sh" || exit 0
hc_read || exit 0
TAG='[yu-github-workflow]'
NL='
'

hpo_issue() {
  local repos repo out rc label_ng other_ng shown msg=''
  repos="$(printf '%s\n' "${HC_OUT}" \
    | { grep -Eo 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+' || true; } \
    | sed -E 's#^https://github\.com/([^/]+/[^/]+)/issues/.*#\1#' | awk '!s[$0]++')"
  if [ -z "${repos}" ]; then
    printf '%s' "${TAG} 開票自檢未執行：沒有讀到剛開好的票網址（可能沒開成）。開成了就自己跑 ticket-check.sh <owner/repo>。"
    return
  fi
  while IFS= read -r repo; do
    out="$(bash "${HPO_DIR}/ticket-check.sh" "${repo}" 2>&1)"; rc=$?
    label_ng="$(printf '%s\n' "${out}" | grep -E '^NG .* 標籤 格[0-9]' || true)"
    other_ng="$(printf '%s\n' "${out}" | grep -E '^NG ' | grep -vE '^NG .* 標籤 格[0-9]' || true)"
    # 只放 NG／??／!! 與結尾摘要；OK 的票一張一行，放進來只會把要看的淹掉。
    shown="$(printf '%s\n' "${out}" | awk '/^--$/ { tail = 1; next } tail || /^(NG|\?\?|!!) /')"
    if [ "${rc}" -eq 0 ]; then
      msg+="${TAG} 開完票了——開票自檢（${repo}）全過。${NL}${shown}${NL}"
    else
      msg+="${TAG} 開完票了——開票自檢（${repo}）退出碼 ${rc}：${NL}${shown}${NL}"
      [ -z "${other_ng}" ] || msg+="錨點／做完能展示什麼 NG：施工者開工要自己去找缺的錨點，現在補（錨點段放 SHA 固定連結，SHA 用 git rev-parse 取）。${NL}"
      [ -z "${label_ng}" ] || msg+="標籤 NG：照 references/labels.md 補掛（類型／優先／驗證各一個）。${NL}"
      [ "${rc}" -eq 1 ] || msg+="退出碼不是 0／1：自檢本身沒跑成，上面的輸出不是檢查結果。${NL}"
    fi
  done <<< "${repos}"
  printf '%s' "${msg%"${NL}"}"
}

hpo_pr() {
  local url repo json body_set ref_set only_body only_ref
  url="$(printf '%s\n' "${HC_OUT}" \
    | { grep -Eo 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' || true; } | tail -n 1)"
  if [ -z "${url}" ]; then
    printf '%s' "${TAG} Closes 回查未執行：沒有讀到剛開好的 PR 網址（可能沒開成）。"
    return
  fi
  repo="$(printf '%s' "${url}" | sed -E 's#^https://github\.com/([^/]+/[^/]+)/pull/.*#\1#')"
  if ! json="$(gh pr view "${url}" --json body,closingIssuesReferences 2>&1)"; then
    printf '%s' "${TAG} Closes 回查未執行：讀不到 ${url}（$(printf '%s' "${json}" | tr '\n' ' ')）。"
    return
  fi
  # 兩組都正規化成小寫 owner/repo#號。內文那組故意不排除反引號與程式碼區塊：要抓的正是「寫了但沒登記」。
  body_set="$(printf '%s' "${json}" | jq -r '.body // ""' \
    | { grep -Eoi '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]*:?[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+' || true; } \
    | sed -E 's/^[^#]*[[:space:]]//' | awk -v r="${repo}" '{ if (substr($0, 1, 1) == "#") $0 = r $0; print tolower($0) }' | sort -u)"
  ref_set="$(printf '%s' "${json}" | jq -r '.closingIssuesReferences[]?
      | if (.url // "") != "" then (.url | sub("^https://github\\.com/"; "") | sub("/issues/"; "#"))
        else "\(.repository.owner.login)/\(.repository.name)#\(.number)" end' \
    | tr '[:upper:]' '[:lower:]' | sort -u)"
  [ "${body_set}" != "${ref_set}" ] || return 0
  only_body="$(comm -23 <(printf '%s\n' "${body_set}") <(printf '%s\n' "${ref_set}") | awk 'NF' | paste -sd ' ' -)"
  only_ref="$(comm -13 <(printf '%s\n' "${body_set}") <(printf '%s\n' "${ref_set}") | awk 'NF' | paste -sd ' ' -)"
  printf '%s' "${TAG} Closes 回查不一致（${url}）：內文寫了、GitHub 沒登記：${only_body:-無}；GitHub 登記了、內文沒寫：${only_ref:-無}。常見原因：關鍵字包在反引號或程式碼區塊裡、PR 目標不是預設分支（都不登記）、分支是從票上用 gh issue develop 開的（內文沒寫也會關票）。"
}

msg=''
if hc_is_issue_create "${HC_CMD}"; then
  hc_ledger post-issue-create "${HC_CMD}"
  msg="$(hpo_issue)"
fi
if hc_is_pr_create "${HC_CMD}"; then
  hc_ledger post-pr-create "${HC_CMD}"
  m2="$(hpo_pr)"
  [ -z "${m2}" ] || msg="${msg:+${msg}${NL}}${m2}"
fi
[ -z "${msg}" ] || hc_emit PostToolUse "${msg}"
exit 0
