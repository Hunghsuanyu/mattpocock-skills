# hook-pre-bash.sh／hook-post-bash.sh 共用：讀 hook 輸入、判斷命中哪一種指令、寫帳本、輸出。
# 只給 source 用。函式一律 hc_ 開頭，變數一律 HC_ 開頭（兩支 hook 互不 source，但測試會）。
#
# 「哪些指令算開票／開 PR」只在這裡判一次，前後兩支共用同一個判法。先把反斜線換行接回一行再判。
#   開票：gh issue create／gh issue new（gh 與 issue 之間可夾 -R／--repo；後面接空白、引號、結尾都算；
#         gh issue created 不算；同一段指令帶 --help／-h 不算）。
#   開 PR：gh pr create／gh pr new（同上），或執行 pr-open.sh（開 PR 一律走這支，指令字串裡沒有 gh pr create）。
#         「執行」＝前面是 bash／sh／zsh，或 pr-open.sh 本身在指令開頭；cat、git diff --、編輯器開它不算。

HC_NL='
'
HC_GH='(^|[^[:alnum:]_.-])gh([[:space:]]+(-R|--repo)([[:space:]]+|=)[^[:space:]]+)*[[:space:]]+'
HC_RE_ISSUE="${HC_GH}issue[[:space:]]+(create|new)([^[:alnum:]_-]|\$)"
HC_RE_PR="${HC_GH}pr[[:space:]]+(create|new)([^[:alnum:]_-]|\$)"
HC_RE_HELP='[[:space:]](--help|-h)([[:space:]]|=)'
HC_PO_PATH="[^[:space:];&|<>()'\"]*pr-open\\.sh([^[:alnum:]_.-]|\$)"
HC_RE_PR_OPEN_RUN="(^|[^[:alnum:]_.-])(bash|sh|zsh)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*${HC_PO_PATH}"
HC_RE_PR_OPEN_CMD="(^|[;&|(${HC_NL}])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*${HC_PO_PATH}"

hc_norm() { local bs=$'\\\n'; printf '%s' "${1//"${bs}"/ }"; }
# hc_gh_hit <正規式> <指令>：有一處命中、而且那一段（到 ; & | 或換行為止）沒有 --help／-h → 0。
hc_gh_hit() {
  local rest="$2" seg
  while [[ "${rest}" =~ $1 ]]; do
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    seg="${rest%%[;&|]*}"; seg="${seg%%"${HC_NL}"*}"
    [[ " ${seg} " =~ ${HC_RE_HELP} ]] || return 0
  done
  return 1
}
hc_is_issue_create() { hc_gh_hit "${HC_RE_ISSUE}" "$(hc_norm "$1")"; }
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
