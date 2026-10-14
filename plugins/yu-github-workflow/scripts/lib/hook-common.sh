# hook-pre-bash.sh／hook-post-bash.sh 共用：讀 hook 輸入、判斷命中哪一種指令、寫帳本、輸出。
# 只給 source 用。函式一律 hc_ 開頭，變數一律 HC_ 開頭（兩支 hook 互不 source，但測試會）。
#
# 「哪些指令算開票／開 PR」只在這裡判一次，前後兩支共用同一個判法。先把反斜線換行接回一行再判。
#   開票：gh issue create／gh issue new（gh 與 issue、issue 與 create 之間都可夾 -R／--repo；後面接空白、引號、結尾都算；
#         gh issue created 不算；緊接在子指令後的 --help／-h 不算——標題、內文裡的 -h 不算看說明）。
#   開 PR：gh pr create／gh pr new（同上），或執行 pr-open.sh（開 PR 一律走這支，指令字串裡沒有 gh pr create）。
#         「執行」＝前面是 bash／sh／zsh（bash -n 只查語法、不算），或 pr-open.sh 本身在指令開頭；
#         路徑可加雙引號或單引號（pr skill 的正式寫法是 "${CLAUDE_PLUGIN_ROOT}/scripts/pr-open.sh"）；
#         檔名要剛好是 pr-open.sh（test-pr-open.sh 不算）；cat、git diff --、編輯器開它不算。

HC_NL='
'
HC_RF='([[:space:]]+(-R|--repo)([[:space:]]+|=)[^[:space:]]+)*'
HC_GH="(^|[^[:alnum:]_.-])gh${HC_RF}[[:space:]]+"
HC_RE_ISSUE="${HC_GH}issue${HC_RF}[[:space:]]+(create|new)([^[:alnum:]_-]|\$)"
HC_RE_PR="${HC_GH}pr${HC_RF}[[:space:]]+(create|new)([^[:alnum:]_-]|\$)"
# 緊接在子指令後（中間只有空白）的 --help／-h。
HC_RE_HELP='^[[:space:]]*(--help|-h)([[:space:]=;&|)]|$)'
# 路徑：不加引號、雙引號、單引號三種；最後一段要剛好是 pr-open.sh。
HC_PO_PATH="(([^[:space:];&|<>()'\"]*/)?pr-open\\.sh([^[:alnum:]_.-]|\$)|\"([^\"]*/)?pr-open\\.sh\"|'([^']*/)?pr-open\\.sh')"
# bash 的選項：長選項照收；短選項不能含 n（-n＝只查語法、不執行）。
HC_RE_PR_OPEN_RUN="(^|[^[:alnum:]_.-])(bash|sh|zsh)[[:space:]]+((--[^[:space:]]+|-[^-[:space:]n][^[:space:]n]*)[[:space:]]+)*${HC_PO_PATH}"
HC_RE_PR_OPEN_CMD="(^|[;&|(${HC_NL}])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*${HC_PO_PATH}"

hc_norm() { local bs=$'\\\n'; printf '%s' "${1//"${bs}"/ }"; }
# hc_gh_hit <正規式> <指令>：有一處命中、而且子指令後面緊接的不是 --help／-h → 0。
#   只看緊接的那一個字詞：標題、內文（--title "改 -h 參數"）裡的 -h 不算看說明。
#   命中字串的最後一個字元是子指令後的分界；分界不是空白（引號、; 等）就不可能緊接 --help。
# hc_gh_count <正規式> <指令>：印這種命中有幾處（判法同 hc_gh_hit）。
hc_gh_count() {
  local rest="$2" m n=0
  while [[ "${rest}" =~ $1 ]]; do
    m="${BASH_REMATCH[0]}"
    rest="${rest#*"${m}"}"
    case "${m}" in
      *[[:space:]]) [[ "${rest}" =~ ${HC_RE_HELP} ]] || n=$((n + 1)) ;;
      *) n=$((n + 1)) ;;
    esac
  done
  printf '%s' "${n}"
}
hc_gh_hit() { [ "$(hc_gh_count "$1" "$2")" -gt 0 ]; }
hc_is_issue_create() { hc_gh_hit "${HC_RE_ISSUE}" "$(hc_norm "$1")"; }
# 指令裡寫了幾次開票（迴圈裡的一次只算一次）。
hc_issue_create_count() { hc_gh_count "${HC_RE_ISSUE}" "$(hc_norm "$1")"; }
# 指令裡有沒有迴圈（for／while／until／xargs）：有的話一次開票可能印出好幾張票。
HC_RE_LOOP='(^|[[:space:];&|(])(for|while|until|xargs)[[:space:]]'
hc_has_loop() { [[ "$(hc_norm "$1")" =~ ${HC_RE_LOOP} ]]; }
hc_is_pr_create() {
  local c; c="$(hc_norm "$1")"
  hc_gh_hit "${HC_RE_PR}" "${c}" || [[ "${c}" =~ ${HC_RE_PR_OPEN_RUN} ]] || [[ "${c}" =~ ${HC_RE_PR_OPEN_CMD} ]]
}

# 讀標準輸入的 hook JSON，設 HC_CMD（指令字串）與 HC_OUT（工具輸出：stdout＋stderr）。
# 沒有 jq：只在原文看起來像開票／開 PR 時印一行「沒跑」，其他指令照常不出聲。回 1＝不要往下做。
hc_read() {
  local payload
  payload="$(cat)"
  if ! command -v jq > /dev/null; then
    case "${payload}" in
      *'issue create'* | *'issue new'* | *'pr create'* | *'pr new'* | *'pr-open.sh'*)
        printf '%s\n' '{"systemMessage":"[yu-github-workflow] hook 沒跑：這台沒有 jq，讀不了 hook 輸入。"}' ;;
    esac
    return 1
  fi
  HC_CMD="$(printf '%s' "${payload}" | jq -r '.tool_input.command // empty' 2>&1)" || return 1
  HC_OUT="$(printf '%s' "${payload}" | jq -r '.tool_response // empty
    | if type == "object" then ((.stdout // "") + "\n" + (.stderr // ""))
      elif type == "string" then . else tostring end' 2>&1)" || HC_OUT=''
  return 0
}

# 帳本：一行一筆「時間<TAB>哪一支<TAB>指令的第一個字詞」，不寫參數內容。
# 第一個字詞是 NAME=value 這種環境變數設定時只記 NAME=（值可能是密鑰）。
# 沒有 CLAUDE_PLUGIN_DATA（不是從 plugin 載入）就不寫。
hc_ledger() {
  [ -n "${CLAUDE_PLUGIN_DATA:-}" ] || return 0
  local first="${2#"${2%%[![:space:]]*}"}"
  first="${first%%[[:space:]]*}"
  case "${first}" in *=*) first="${first%%=*}=" ;; esac
  mkdir -p "${CLAUDE_PLUGIN_DATA}" &&
    printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "${first}" >> "${CLAUDE_PLUGIN_DATA}/hook-ledger.log"
}

# hc_emit <PreToolUse|PostToolUse> <訊息>：訊息同時給使用者（systemMessage）與模型（additionalContext）。
hc_emit() {
  jq -cn --arg ev "$1" --arg m "$2" '{systemMessage: $m, hookSpecificOutput: {hookEventName: $ev, additionalContext: $m}}'
}
