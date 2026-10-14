#!/usr/bin/env bash
# PreToolUse(Bash)：指令要開票或開 PR 時，把該照的規則放到眼前。
# 一律不擋、退出碼恆 0：要不要開、怎麼開是判斷，這支只負責讓規則在動手那一刻被看到。
# 命中判法在 lib/hook-common.sh（與 hook-post-bash.sh 共用）。測試：tests/test-hooks.sh。
HPB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 0
# shellcheck source=lib/hook-common.sh
. "${HPB_DIR}/lib/hook-common.sh" || exit 0
hc_read || exit 0

msg=''
if hc_is_issue_create "${HC_CMD}"; then
  hc_ledger pre-issue-create "${HC_CMD}"
  msg='[yu-github-workflow] 開票提醒：施工中的對話不開票——計畫外的新事在 SPEC 留言，由指揮台寫進「尚未定義」（🔴 不能等的例外照入口 skill github-workflow）。指揮台開票照拆票 skill to-tickets：類型／優先／驗證標籤各一個、內文走 --body-file、施工票補設被外審票擋（--add-blocked-by）；真的不改檔的票，錨點寫 `- 無：<理由>`。'
fi
if hc_is_pr_create "${HC_CMD}"; then
  hc_ledger pre-pr-create "${HC_CMD}"
  msg="${msg:+${msg}
}"'[yu-github-workflow] 開 PR 提醒：照 PR skill pr 寫內文、經 scripts/pr-open.sh 開；整合分支收齊才開；外審（review skill）在開 PR 之前做完；公開 repo 的 PR 不寫私有 repo 名與票號。'
fi
[ -z "${msg}" ] || hc_emit PreToolUse "${msg}"
exit 0
