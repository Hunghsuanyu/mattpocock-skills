#!/usr/bin/env bash
# PostToolUse(Bash)：開完票或開完 PR，替人把檢查跑掉、結果放到眼前。
# 一律不擋、退出碼恆 0；只讀 GitHub。命中判法在 lib/hook-common.sh（與 hook-pre-bash.sh 共用）。
#
# 開完票 → 跑 ticket-check.sh <owner/repo> <票號…>，只查剛開的票。票只取自 gh issue create 印出的那一行
#   （成功時一定印一行、整行就是 https://github.com/<owner>/<repo>/issues/<號>，不帶 -R 也一樣）；
#   輸出裡別處提到的票網址（內文、前一個指令的輸出）不算。
#   整行就是票網址的行比指令裡的開票次數多、而且指令裡沒有迴圈 ⇒ 同一次 Bash 裡別的指令也印了票網址
#   （例：gh issue view --json url -q .url），分不出哪張是剛開的 ⇒ 不跑，明講。
#   不退回 -R／--repo 參數，也不從 cwd 推：建票失敗時拿參數去自檢，會對著沒開成的票報 NG 或全過；
#   clone 有兩個 remote 時從 cwd 推，會對著別的 repo 報全過。沒有那一行＝沒開成或沒讀到 → 不跑，明講沒跑。
#   自檢沒印 `--` 總結＝沒跑完：明講，不當成 NG（退出碼此時不是檢查結果）。
# 開完 PR → 從輸出取 PR 網址，回查 GitHub 登記的關票清單（closingIssuesReferences）
#   與內文的關閉關鍵字是否同一組票；內文那組用 ticket-check.sh 的 pr_closing_refs（同一個判法，只比本 repo 的票）。
#   不同就提示（目標不是預設分支，GitHub 不登記；從 gh issue develop 開的分支，內文沒寫也會關票）。
# 指令整體失敗（PostToolUseFailure，例：gh issue create … && 下一步失敗）：輸出裡有剛開的票網址 ⇒ 照樣自檢，
#   訊息開頭註明「指令整體失敗，但票已開」；沒有 ⇒ 照「未執行」提示。
# 測試：tests/test-hooks.sh。
HPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 0
# shellcheck source=lib/hook-common.sh
. "${HPO_DIR}/lib/hook-common.sh" || exit 0
hc_read || exit 0
TAG='[yu-github-workflow]'
NL='
'

hpo_issue() {
  local urls nurl ncreate repos repo nums out rc label_ng cell_ng other_ng nunk shown msg=''
  urls="$(printf '%s\n' "${HC_OUT}" | tr -d '\r' \
    | { grep -Ex '[[:space:]]*https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+[[:space:]]*' || true; } \
    | tr -d ' \t')"
  if [ -z "${urls}" ]; then
    printf '%s' "${TAG} 開票自檢未執行：沒有讀到 gh issue create 印出的票網址（可能沒開成）。開成了就自己跑 ticket-check.sh <owner/repo> <票號>。"
    return
  fi
  nurl="$(printf '%s\n' "${urls}" | awk 'NF' | wc -l | tr -d ' ')"
  ncreate="$(hc_issue_create_count "${HC_CMD}")"
  if [ "${nurl}" -gt "${ncreate}" ] && ! hc_has_loop "${HC_CMD}"; then
    printf '%s' "${TAG} 開票自檢未執行：輸出裡有 ${nurl} 行票網址，指令裡只開了 ${ncreate} 次票——同一次 Bash 裡別的指令也印了票網址，分不出哪張是剛開的。自己跑 ticket-check.sh <owner/repo> <票號>（網址：$(printf '%s\n' "${urls}" | paste -sd ' ' -)）。"
    return
  fi
  repos="$(printf '%s\n' "${urls}" | sed -E 's#^https://github\.com/([^/]+/[^/]+)/issues/.*#\1#' | awk '!s[$0]++')"
  while IFS= read -r repo; do
    nums="$(printf '%s\n' "${urls}" | awk -v p="https://github.com/${repo}/issues/" 'index($0, p) == 1 { print substr($0, length(p) + 1) }' | awk '!s[$0]++' | paste -sd ' ' -)"
    # shellcheck disable=SC2086 # 票號一個一個傳
    out="$(bash "${HPO_DIR}/ticket-check.sh" "${repo}" ${nums} 2>&1)"; rc=$?
    if ! printf '%s\n' "${out}" | grep -qx -- '--'; then
      msg+="${TAG} 開完票了——開票自檢沒跑完（${repo} ${nums}）：沒印出總結（退出碼 ${rc}），下面不是檢查結果。自己重跑 ticket-check.sh ${repo} ${nums}。${NL}$(printf '%s\n' "${out}" | tail -n 5)${NL}"
      continue
    fi
    # NG 分三類給提示：標籤格 1、2（類型／優先／驗證）、標籤格 3～8（機器、狀態、署名、衍生、誤關票）、其他（錨點、格 9）。
    label_ng="$(printf '%s\n' "${out}" | grep -E '^NG .* 標籤 格[12] ' || true)"
    cell_ng="$(printf '%s\n' "${out}" | grep -E '^NG .* 標籤 格[3-8] ' || true)"
    other_ng="$(printf '%s\n' "${out}" | grep -E '^NG ' | grep -vE '^NG .* 標籤 格[0-9]' || true)"
    nunk="$(printf '%s\n' "${out}" | awk '/^--$/ { exit } /^\?\? / { n++ } END { print n + 0 }')"
    # 只放 NG／??／!! 與結尾摘要；OK 的票一張一行，放進來只會把要看的淹掉。
    shown="$(printf '%s\n' "${out}" | awk '/^--$/ { tail = 1; next } tail || /^(NG|\?\?|!!) /')"
    if [ "${rc}" -eq 0 ] && [ "${nunk}" -gt 0 ]; then
      msg+="${TAG} 開完票了——開票自檢（${repo} ${nums}）沒有 NG，但有 ${nunk} 處讀不到（?? 行，那幾格沒查）。${NL}${shown}${NL}"
    elif [ "${rc}" -eq 0 ]; then
      msg+="${TAG} 開完票了——開票自檢（${repo} ${nums}）全過。${NL}${shown}${NL}"
    else
      msg+="${TAG} 開完票了——開票自檢（${repo} ${nums}）退出碼 ${rc}：${NL}${shown}${NL}"
      [ -z "${other_ng}" ] || msg+="錨點／做完能展示什麼 NG：施工者開工要自己去找缺的錨點，現在補（錨點段放 SHA 固定連結，SHA 用 git rev-parse 取；真的沒有程式碼錨點就寫一行「- 無：<理由>」）。${NL}"
      [ -z "${label_ng}" ] || msg+="標籤 NG：照 references/labels.md 補掛（類型／優先／驗證各一個）。${NL}"
      [ -z "${cell_ng}" ] || msg+="格 3～8 NG：照 NG 行的說明改（每格判準見 references/ticket-check.md）。${NL}"
      [ "${rc}" -eq 1 ] || msg+="退出碼不是 0／1：自檢本身沒跑成，上面的輸出不是檢查結果。${NL}"
    fi
  done <<< "${repos}"
  printf '%s' "${msg%"${NL}"}"
}

hpo_pr() {
  local url repo lrepo json chk body nums body_set ref_set only_body only_ref
  url="$(printf '%s\n' "${HC_OUT}" \
    | { grep -Eo 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' || true; } | tail -n 1)"
  if [ -z "${url}" ]; then
    printf '%s' "${TAG} Closes 回查未執行：沒有讀到剛開好的 PR 網址（可能沒開成）。"
    return
  fi
  repo="$(printf '%s' "${url}" | sed -E 's#^https://github\.com/([^/]+/[^/]+)/pull/.*#\1#')"
  lrepo="$(printf '%s' "${repo}" | tr '[:upper:]' '[:lower:]')"
  if ! json="$(gh pr view "${url}" --json body,closingIssuesReferences 2>&1)"; then
    printf '%s' "${TAG} Closes 回查未執行：讀不到 ${url}（$(printf '%s' "${json}" | tr '\n' ' ')）。"
    return
  fi
  if ! chk="$(printf '%s' "${json}" | jq -e 'type == "object"' 2>&1)"; then
    printf '%s' "${TAG} Closes 回查未執行：gh pr view ${url} 回的不是 JSON（$(printf '%s' "${json}" | head -c 200 | tr '\n' ' ')）。"
    return
  fi
  body="$(printf '%s' "${json}" | jq -r '.body // ""')"
  # 內文那組：開票自檢的 pr_closing_refs（反引號、程式碼區塊裡的不算；只印本 repo 的票號）。在子 shell 裡 source，不讓它的 set -e 漏出來。
  if ! nums="$(. "${HPO_DIR}/ticket-check.sh" && pr_closing_refs "${body}" "${repo}")"; then
    printf '%s' "${TAG} Closes 回查未執行：判法（ticket-check.sh 的 pr_closing_refs）沒跑成。"
    return
  fi
  body_set="$(printf '%s\n' "${nums}" | awk -v r="${lrepo}" 'NF { print r "#" $0 }' | sort -u)"
  # GitHub 登記的那組只比本 repo（判法只認本 repo；跨 repo 的關票不在這裡比）。
  ref_set="$(printf '%s' "${json}" | jq -r '.closingIssuesReferences[]?
      | if (.url // "") != "" then (.url | sub("^https://github\\.com/"; "") | sub("/issues/"; "#"))
        else "\(.repository.owner.login)/\(.repository.name)#\(.number)" end' \
    | tr '[:upper:]' '[:lower:]' | awk -v p="${lrepo}#" 'index($0, p) == 1' | sort -u)"
  [ "${body_set}" != "${ref_set}" ] || return 0
  only_body="$(comm -23 <(printf '%s\n' "${body_set}") <(printf '%s\n' "${ref_set}") | awk 'NF' | paste -sd ' ' -)"
  only_ref="$(comm -13 <(printf '%s\n' "${body_set}") <(printf '%s\n' "${ref_set}") | awk 'NF' | paste -sd ' ' -)"
  printf '%s' "${TAG} Closes 回查不一致（${url}）：內文寫了、GitHub 沒登記：${only_body:-無}；GitHub 登記了、內文沒寫：${only_ref:-無}。常見原因：PR 目標不是預設分支（不登記）、分支是從票上用 gh issue develop 開的（內文沒寫也會關票）。"
}

msg=''
if hc_is_issue_create "${HC_CMD}"; then
  hc_ledger post-issue-create "${HC_CMD}"
  msg="$(hpo_issue)"
  case "${msg}" in
    *開票自檢未執行*) ;;
    *) [ "${HC_FAILED}" != 1 ] || msg="${TAG} 指令整體失敗，但票已開——${NL}${msg}" ;;
  esac
fi
if hc_is_pr_create "${HC_CMD}"; then
  hc_ledger post-pr-create "${HC_CMD}"
  m2="$(hpo_pr)"
  [ -z "${m2}" ] || msg="${msg:+${msg}${NL}}${m2}"
fi
ev=PostToolUse; [ "${HC_FAILED}" != 1 ] || ev=PostToolUseFailure
[ -z "${msg}" ] || hc_emit "${ev}" "${msg}"
exit 0
