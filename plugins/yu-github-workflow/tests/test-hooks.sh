#!/usr/bin/env bash
# scripts/hook-pre-bash.sh、scripts/hook-post-bash.sh 的測試。
# hook 本體只吃合成的 hook JSON（標準輸入），不經過 Claude、不開票、不開 PR：
#   gh 換成記錄呼叫的假程式（放在 PATH 最前面）；ticket-check.sh 換成記錄呼叫的假程式
#   （把兩支 hook 與 lib 複製到暫存目錄，假 ticket-check.sh 放在它們旁邊，hook 找的是自己目錄下那支）。
# 每個案例印一行「ok <案例名>」或「not ok <案例名>」。票號（井號＋數字）在執行時組出，不直接寫進本檔。
#
# 用法：tests/test-hooks.sh　退出碼：0＝全過；1＝有案例失敗。
set -uo pipefail
TH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 9
SRC="$(cd "${TH_DIR}/../scripts" && pwd -P)" || exit 9
for f in hook-pre-bash.sh hook-post-bash.sh lib/hook-common.sh; do
  [ -f "${SRC}/${f}" ] || { echo "not ok 檔案不存在：${SRC}/${f}"; exit 1; }
done
command -v jq > /dev/null || { echo "not ok 這台沒有 jq（hook 需要）"; exit 1; }

T="$(mktemp -d)" || exit 9
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin" "${T}/plug/scripts/lib" "${T}/data"
cp "${SRC}/hook-pre-bash.sh" "${SRC}/hook-post-bash.sh" "${T}/plug/scripts/"
cp "${SRC}/lib/hook-common.sh" "${T}/plug/scripts/lib/"
PRE="${T}/plug/scripts/hook-pre-bash.sh" POST="${T}/plug/scripts/hook-post-bash.sh"

# 假 ticket-check.sh：記下參數，印 TC_OUT 檔的內容，回 TC_RC。
#   被 source 時（hook 借它的 pr_closing_refs 判法）改讀真的那支，不記帳、不印。
cat > "${T}/plug/scripts/ticket-check.sh" <<'FAKE'
#!/usr/bin/env bash
if [ "${BASH_SOURCE[0]}" != "$0" ]; then . "${REAL_TC}"; return; fi
printf '%s\n' "$*" >> "${TC_LOG}"
cat "${TC_OUT}"
exit "${TC_RC}"
FAKE
# 假 gh：
#   issue create → FAKE_CREATE＝ok 印 FAKE_URL；fail 印錯誤到 stderr、回 1（模擬建票失敗）
#   pr view      → FAKE_PRVIEW＝ok 印 FAKE_PRJSON 檔；fail 回 1
cat > "${T}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_LOG}"
case "$1 $2" in
  "issue create")
    case "${FAKE_CREATE}" in fail) echo "GraphQL: Could not resolve to a Repository" >&2; exit 1 ;; *) echo "${FAKE_URL}" ;; esac ;;
  "pr view")
    case "${FAKE_PRVIEW}" in fail) echo "HTTP 502" >&2; exit 1 ;; html) echo '<html>502 Bad Gateway</html>' ;; *) cat "${FAKE_PRJSON}" ;; esac ;;
  *) echo "假 gh 不認得：$*" >&2; exit 3 ;;
esac
FAKE
chmod +x "${T}/plug/scripts/ticket-check.sh" "${T}/bin/gh"
export PATH="${T}/bin:${PATH}" FAKE_LOG="${T}/gh.log" TC_LOG="${T}/tc.log" TC_OUT="${T}/tc.out" TC_RC=0 \
  FAKE_CREATE=ok FAKE_URL='' FAKE_PRVIEW=ok FAKE_PRJSON="${T}/pr.json" CLAUDE_PLUGIN_DATA="${T}/data" \
  REAL_TC="${SRC}/ticket-check.sh"
LEDGER="${T}/data/hook-ledger.log"
H='#'

PASS=0 FAILN=0
if [ "$(command -v gh)" = "${T}/bin/gh" ]; then echo "ok 拿到的是假 gh"; PASS=$((PASS + 1))
else echo "not ok 拿到的是假 gh（$(command -v gh)）"; echo "停：不是假 gh 就不跑"; exit 1; fi

# hook <pre|post> <指令> [工具輸出]：結果放在 rc、out（hook 印出來的 JSON 解開後的訊息）
hook() {
  : > "${FAKE_LOG}"; : > "${TC_LOG}"; : > "${LEDGER}"
  local s="${PRE}"; [ "$1" = post ] && s="${POST}"
  jq -n --arg c "$2" --arg o "${3:-}" \
    '{hook_event_name: "x", tool_name: "Bash", tool_input: {command: $c}, tool_response: {stdout: $o, stderr: "", interrupted: false}}' \
    | bash "${s}" > "${T}/raw" 2> "${T}/err"; rc=$?
  out=''
  if [ -s "${T}/raw" ]; then out="$(jq -r '.hookSpecificOutput.additionalContext' "${T}/raw" 2>&1)"; fi
}
# 建票：用假 gh 真的跑一次 gh issue create，拿它的 stdout＋stderr 當工具輸出（模擬 Bash 工具收到的東西）
create_out() { gh issue create "$@" 2>&1; }
calls() { awk 'NF' "$1" | wc -l | tr -d ' '; }
verdict() { # verdict <案例名> <條件…>：條件成立且退出碼 0 → ok
  local name="$1"; shift
  if [ "${rc}" -eq 0 ] && "$@"; then echo "ok ${name}"; PASS=$((PASS + 1))
  else
    echo "not ok ${name}"; FAILN=$((FAILN + 1))
    echo "  # rc=${rc} 輸出=$(printf '%s' "${out}" | tr '\n' '|') 自檢呼叫=$(tr '\n' ';' < "${TC_LOG}") gh=$(tr '\n' ';' < "${FAKE_LOG}") stderr=$(tr '\n' '|' < "${T}/err")"
  fi
}
has() { case "${out}" in *"$1"*) return 0 ;; esac; return 1; }
silent() { [ -z "${out}" ] && [ ! -s "${T}/raw" ]; }

# ══ PreToolUse：開票 ══
NL='
'
for c in 'gh issue create --title t --body-file b.md' "echo 'gh issue create dry-text'" 'cd x && gh  issue  create -R o/r' \
  'gh issue new --title t' 'gh -R o/r issue create --title t' 'gh --repo o/r issue create --title t' 'gh --repo=o/r issue create' \
  "gh issue \\${NL}  create --title t" 'gh issue -R o/r create --title t' 'gh issue --repo=o/r new --title t' \
  'gh issue create --title "改 -h 參數" --body-file b' 'gh issue create --title t --body "看 --help 說明"'; do
  hook pre "${c}"
  verdict "pre 開票命中：${c}" has '開票提醒'
done
hook pre 'gh issue create --title t'
c_pre_text() { has '在 SPEC 留言，由指揮台寫進' && ! has '記到 SPEC'; }
verdict 'pre 開票：計畫外的新事在 SPEC 留言、由指揮台寫進' c_pre_text
c_ledger_issue() { grep -qE $'\tpre-issue-create\tgh$' "${LEDGER}"; }
verdict 'pre 開票：帳本記一行、第一個字詞是 gh' c_ledger_issue
hook pre 'GH_TOKEN=sekret-value gh issue create --title t'
c_ledger_noval() { grep -qE $'\tpre-issue-create\tGH_TOKEN=$' "${LEDGER}" && ! grep -q sekret "${LEDGER}"; }
verdict 'pre 開票：第一個字詞是環境變數設定時只記名稱、不記值' c_ledger_noval

# ══ PreToolUse：開 PR（gh pr create 或 pr-open.sh） ══
for c in 'gh pr create --base main --body-file b.md' 'bash plugins/x/scripts/pr-open.sh o/r main feat/x t.txt b.txt' "echo 'bash ./pr-open.sh o/r main h t b'" \
  'gh pr new --base main' 'gh -R o/r pr create --base main' './scripts/pr-open.sh o/r main feat/x t b' 'cd x && FOO=1 scripts/pr-open.sh o/r main h t b' \
  '"${CLAUDE_PLUGIN_ROOT}/scripts/pr-open.sh" o/r main feat/x t b' "'/u/x/scripts/pr-open.sh' o/r main h t b" \
  'bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-open.sh" o/r main h t b' 'cd x && "/u/x/scripts/pr-open.sh" o/r main h t b' \
  'gh pr --repo o/r create --base main' 'gh pr create --title "改 -h 參數" --body-file b'; do
  hook pre "${c}"
  verdict "pre 開 PR 命中：${c}" has '開 PR 提醒'
done
hook pre 'bash scripts/pr-open.sh o/r main feat/x t b'
c_ledger_pr() { grep -qE $'\tpre-pr-create\tbash$' "${LEDGER}"; }
verdict 'pre 開 PR：帳本記一行、第一個字詞是 bash' c_ledger_pr

# ══ PreToolUse：不該命中 ══
for c in 'gh issue list' 'gh pr view 3' "echo 'gh issue created'" 'gh issue createx' 'mygh issue create' 'gh pr created' 'cat pr-open.sh.bak' 'ls' \
  'cat scripts/pr-open.sh' 'git diff -- scripts/pr-open.sh' 'vim scripts/pr-open.sh' 'gh pr create --help' 'gh issue create -h' 'gh pr new --help' \
  'bash tests/test-pr-open.sh' 'bash -n scripts/pr-open.sh' 'cat "scripts/pr-open.sh"' 'gh issue -R o/r create --help' "vim 'scripts/pr-open.sh'"; do
  hook pre "${c}"
  c_none() { silent && [ ! -s "${LEDGER}" ]; }
  verdict "pre 不命中：${c}" c_none
done
printf 'not json' | bash "${PRE}" > "${T}/raw" 2>&1; rc=$?; out="$(cat "${T}/raw")"
verdict 'pre 輸入不是 JSON：不出聲、退出碼 0' silent

# ══ PostToolUse：開票自檢 ══
printf '%s\n' "   repo-a        ${H}12  標籤 OK（一般票）" '--' '施工票 1 張' > "${TC_OUT}"
FAKE_CREATE=ok FAKE_URL='https://github.com/own-c/repo-d/issues/12'
c_called() { [ "$(calls "${TC_LOG}")" -eq 1 ] && [ "$(cat "${TC_LOG}")" = "$1" ]; }
c_not_run() { [ "$(calls "${TC_LOG}")" -eq 0 ] && has '開票自檢未執行'; }

hook post 'gh issue create --title t --body-file b.md' "$(create_out --title t --body-file b.md)"
c1() { c_called 'own-c/repo-d 12' && has '全過'; }
verdict '開票自檢：不帶 -R、有票網址：只對那張票自檢' c1

hook post 'gh issue create -R own-a/repo-b --title t' "$(create_out -R own-a/repo-b --title t)"
c2() { c_called 'own-c/repo-d 12'; }
verdict '開票自檢：-R 與網址不同：以網址為準' c2

# 輸出裡別處也有別的 repo 的票網址（內文、前一個指令的輸出）⇒ 只認 gh issue create 印的那一行（整行就是網址）
hook post 'gh issue view 3 -R own-x/repo-y && gh issue create --title t' \
  "$(printf '參考 https://github.com/own-x/repo-y/issues/3 的作法\nhttps://github.com/own-c/repo-e/issues/4%sissuecomment-1\n' "${H}")${NL}$(create_out --title t)"
c_multi() { c_called 'own-c/repo-d 12'; }
verdict '開票自檢：輸出裡有別的 repo 的票網址：只對剛開的那張自檢' c_multi

FAKE_CREATE=fail
hook post 'gh issue create -R own-a/repo-b --title t' "$(create_out -R own-a/repo-b --title t)"
verdict '開票自檢：帶 -R、沒有票網址：未執行、不呼叫自檢' c_not_run

hook post 'gh issue create --title t' "$(create_out --title t)"
verdict '開票自檢：不帶 -R、沒有票網址：未執行、不呼叫自檢' c_not_run

# NG 原樣放進來，標籤 NG 與錨點 NG 分開提示；OK 的票不放。
printf '%s\n' "NG repo-d        ${H}12  標籤 格1 缺 類型（一般票） — 某票" "NG repo-d        ${H}13  沒有「## 錨點」段 — 另一票" \
  "   repo-d        ${H}14  標籤 OK（一般票）" '--' '施工票 2 張，缺錨點 1 張' > "${TC_OUT}"
TC_RC=1 FAKE_CREATE=ok
hook post 'gh issue create --title t' "$(create_out --title t)"
c_ng() { has '標籤 格1 缺 類型' && has '沒有「## 錨點」段' && has '標籤 NG：' && has '錨點／做完能展示什麼 NG：' && has '施工票 2 張' && ! has "${H}14"; }
verdict '開票自檢：NG 原樣放進來、標籤 NG 與錨點 NG 分開提示' c_ng
printf '%s\n' "NG repo-d        ${H}12  標籤 格1 缺 類型（一般票） — 某票" '--' 'x' > "${TC_OUT}"
hook post 'gh issue create --title t' "$(create_out --title t)"
c_label_only() { has '標籤 NG：' && ! has '錨點／做完能展示什麼 NG：'; }
verdict '開票自檢：只有標籤 NG 時不講錨點' c_label_only
# 格 5～8 的 NG 不是「補掛類型／優先／驗證」
printf '%s\n' "NG repo-d        ${H}12  標籤 格5 驗證者 session a 與施工者 session a 是同一個對話（session a） — 某票" '--' 'x' > "${TC_OUT}"
hook post 'gh issue create --title t' "$(create_out --title t)"
c_cell_ng() { has '格5 驗證者' && has '格 3～8 NG：' && ! has '標籤 NG：' && ! has '錨點／做完能展示什麼 NG：'; }
verdict '開票自檢：格 5 的 NG 不歸成補掛類型／優先／驗證' c_cell_ng
# 自檢沒印 -- 總結＝沒跑完：明講，不當成 rc=1 的 NG
printf '%s\n' "NG repo-d        ${H}12  標籤 格1 缺 類型（一般票） — 某票" 'gh: HTTP 502' > "${TC_OUT}"
hook post 'gh issue create --title t' "$(create_out --title t)"
c_unfinished() { has '自檢沒跑完' && ! has '標籤 NG：' && ! has '錨點／做完能展示什麼 NG：'; }
verdict '開票自檢：沒印總結 ⇒ 明講沒跑完、不當 NG' c_unfinished
# 有總結、但退出碼不是 0／1 ⇒ 警告輸出不是檢查結果
printf '%s\n' '--' 'x' > "${TC_OUT}"; TC_RC=3
hook post 'gh issue create --title t' "$(create_out --title t)"
c_rc3() { has '退出碼 3' && has '退出碼不是 0／1'; }
verdict '開票自檢：有總結但退出碼 3 ⇒ 警告' c_rc3
TC_RC=0
# 退出碼 0 但有 ?? ⇒ 不寫「全過」，講有幾處讀不到
printf '%s\n' "?? repo-d        ${H}12  格5 問不到留言（HTTP 502）" "?? repo-d        問不到開著的票內文，錨點、格 7、格 9 不查（x）" '--' 'x' > "${TC_OUT}"
hook post 'gh issue create --title t' "$(create_out --title t)"
c_unk() { has '沒有 NG，但有 2 處讀不到' && ! has '全過'; }
verdict '開票自檢：rc=0 但有 ?? ⇒ 不寫全過、講幾處讀不到' c_unk
printf '%s\n' "   repo-d        ${H}12  標籤 OK（一般票）" '--' 'x' > "${TC_OUT}"
# 同一次 Bash 裡別的指令也印了整行的票網址 ⇒ 分不出哪張是剛開的、不跑
hook post 'gh issue view 3 -R own-x/repo-y --json url -q .url && gh issue create --title t' \
  "https://github.com/own-x/repo-y/issues/3${NL}$(create_out --title t)"
c_other_url() { [ "$(calls "${TC_LOG}")" -eq 0 ] && has '開票自檢未執行' && has '分不出哪張是剛開的'; }
verdict '開票自檢：別的指令也印了整行票網址 ⇒ 不跑、明講' c_other_url
# ⬛ 對照：兩次開票、兩行網址 ⇒ 兩張都查；迴圈裡開票 ⇒ 網址比指令裡的開票次數多也照查
hook post 'gh issue create --title a && gh issue create -R own-c/repo-d --title b' \
  "$(create_out --title a)${NL}https://github.com/own-c/repo-d/issues/13"
c_two() { c_called 'own-c/repo-d 12 13'; }
verdict '開票自檢：⬛ 開兩次、兩行網址 ⇒ 兩張都查' c_two
hook post 'for t in a b; do gh issue create --title "$t"; done' \
  "$(create_out --title a)${NL}https://github.com/own-c/repo-d/issues/13"
verdict '開票自檢：⬛ 迴圈裡開票 ⇒ 兩張都查' c_two
hook post 'gh issue create --title t' "$(create_out --title t)"
c_ledger_post() { grep -qE $'\tpost-issue-create\tgh$' "${LEDGER}"; }
verdict '開票自檢：帳本記一行' c_ledger_post

for c in 'gh issue list' "echo 'gh issue created'"; do
  hook post "${c}" 'https://github.com/own-c/repo-d/issues/12'
  c_post_none() { silent && [ "$(calls "${TC_LOG}")" -eq 0 ]; }
  verdict "post 不命中：${c}" c_post_none
done

# ══ PostToolUse：PR 的 Closes 回查 ══
PRURL='https://github.com/own-c/repo-d/pull/7'
ref() { printf '{"number":%s,"url":"https://github.com/%s/issues/%s","repository":{"name":"x","owner":{"login":"y"}}}' "$2" "$1" "$2"; }
prjson() { jq -n --arg b "$1" --argjson r "$2" '{body: $b, closingIssuesReferences: $r}' > "${FAKE_PRJSON}"; }

prjson "$(printf '摘要\n\nCloses %s5\nfixes own-e/repo-f%s9\n' "${H}" "${H}")" "[$(ref own-c/repo-d 5),$(ref own-e/repo-f 9)]"
hook post 'bash scripts/pr-open.sh own-c/repo-d main feat/x t b' "${PRURL}"
c_pr_same() { silent && grep -qF "pr view ${PRURL} " "${FAKE_LOG}"; }
verdict 'PR 回查：pr-open.sh、內文與登記一致：不出聲（有回查）' c_pr_same

prjson "$(printf '摘要\n\n`Closes %s5`\n' "${H}")" '[]'
hook post 'bash scripts/pr-open.sh own-c/repo-d main feat/x t b' "$(printf 'pr-open: 開好了\n%s\n' "${PRURL}")"
c_pr_code() { silent && grep -qF "pr view ${PRURL} " "${FAKE_LOG}"; }
verdict 'PR 回查：反引號裡的關鍵字（GitHub 不認、開票自檢同一個判法也不認）：不出聲' c_pr_code

prjson "$(printf '摘要\n\nCloses %s5\n' "${H}")" '[]'
hook post 'bash scripts/pr-open.sh own-c/repo-d main feat/x t b' "${PRURL}"
c_pr_unreg() { has 'Closes 回查不一致' && has "內文寫了、GitHub 沒登記：own-c/repo-d${H}5"; }
verdict 'PR 回查：內文寫了、GitHub 沒登記（例：目標不是預設分支）：提示' c_pr_unreg

prjson '摘要' "[$(ref own-c/repo-d 8)]"
hook post 'gh pr create --base main --body-file b.md' "${PRURL}"
c_pr_extra() { has 'Closes 回查不一致' && has "GitHub 登記了、內文沒寫：own-c/repo-d${H}8"; }
verdict 'PR 回查：gh pr create、登記了但內文沒寫：提示' c_pr_extra

hook post 'gh pr create --base main' 'pull request create failed: GraphQL: No commits between main and x'
c_pr_nourl() { has 'Closes 回查未執行' && [ "$(calls "${FAKE_LOG}")" -eq 0 ]; }
verdict 'PR 回查：沒有 PR 網址：未執行、不呼叫 gh' c_pr_nourl

FAKE_PRVIEW=fail
hook post 'gh pr create --base main' "${PRURL}"
c_pr_viewfail() { has 'Closes 回查未執行' && has 'HTTP 502'; }
verdict 'PR 回查：讀不到 PR：未執行' c_pr_viewfail
FAKE_PRVIEW=html
hook post 'gh pr create --base main' "${PRURL}"
c_pr_html() { has 'Closes 回查未執行' && has '不是 JSON'; }
verdict 'PR 回查：gh pr view 回的不是 JSON：明講沒查成' c_pr_html
FAKE_PRVIEW=ok

for c in 'gh pr view 7' 'gh pr list'; do
  hook post "${c}" "${PRURL}"
  c_post_pr_none() { silent && [ "$(calls "${FAKE_LOG}")" -eq 0 ]; }
  verdict "post 不命中：${c}" c_post_pr_none
done

# ══ 沒有 jq：開票／開 PR 的指令印一行「沒跑」，其他指令不出聲 ══
mkdir -p "${T}/nojq"
for b in cat dirname; do ln -s "$(command -v "${b}")" "${T}/nojq/${b}"; done
nojq() { # nojq <pre|post> <指令>
  local s="${PRE}"; [ "$1" = post ] && s="${POST}"
  jq -n --arg c "$2" '{tool_input: {command: $c}, tool_response: {stdout: "", stderr: ""}}' > "${T}/in.json"
  PATH="${T}/nojq" "${BASH}" "${s}" < "${T}/in.json" > "${T}/raw" 2> "${T}/err"; rc=$?
  out="$(cat "${T}/raw")"
}
# 用新的 bash 問：本 shell 的 command -v 會讀指令快取（jq 先前用過），換了 PATH 照樣找得到
if [ -z "$(PATH="${T}/nojq" "${BASH}" -c 'command -v jq' 2>&1)" ]; then echo "ok 沒有 jq 的 PATH 真的找不到 jq"; PASS=$((PASS + 1))
else echo "not ok 沒有 jq 的 PATH 找得到 jq"; FAILN=$((FAILN + 1)); fi
for c in 'gh issue new --title t' 'gh pr new --base main' 'gh issue create --title t'; do
  for w in pre post; do
    nojq "${w}" "${c}"
    verdict "沒有 jq（${w}）：${c} ⇒ 明講沒跑" has '沒有 jq'
  done
done
nojq pre 'ls'
verdict '沒有 jq：不相干的指令不出聲' silent

echo "--"
echo "通過 ${PASS}，失敗 ${FAILN}"
[ "${FAILN}" -eq 0 ]
