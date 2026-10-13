# hook-pre-bash.sh／hook-post-bash.sh 共用：讀 hook 輸入、判斷命中哪一種指令、寫帳本、輸出。
# 只給 source 用。函式一律 hc_ 開頭，變數一律 HC_ 開頭（兩支 hook 互不 source，但測試會）。
#
# 「哪些指令算開票／開 PR」只在這裡判一次，前後兩支共用同一個判法。
#   開票：gh issue create（後面接空白、引號、結尾都算；gh issue created 不算）。
#   開 PR：gh pr create，或經 pr-open.sh 開（開 PR 一律走這支，指令字串裡沒有 gh pr create）。

HC_RE_ISSUE='(^|[^[:alnum:]_.-])gh[[:space:]]+issue[[:space:]]+create([^[:alnum:]_-]|$)'
HC_RE_PR='(^|[^[:alnum:]_.-])gh[[:space:]]+pr[[:space:]]+create([^[:alnum:]_-]|$)'
HC_RE_PR_OPEN='(^|[^[:alnum:]_.-])pr-open\.sh([^[:alnum:]_.-]|$)'

hc_is_issue_create() { [[ "$1" =~ ${HC_RE_ISSUE} ]]; }
hc_is_pr_create() { [[ "$1" =~ ${HC_RE_PR} ]] || [[ "$1" =~ ${HC_RE_PR_OPEN} ]]; }

# 讀標準輸入的 hook JSON，設 HC_CMD（指令字串）與 HC_OUT（工具輸出：stdout＋stderr）。
# 沒有 jq：只在原文看起來像開票／開 PR 時印一行「沒跑」，其他指令照常不出聲。回 1＝不要往下做。
hc_read() {
  local payload
  payload="$(cat)"
  if ! command -v jq > /dev/null; then
    case "${payload}" in
      *'issue create'* | *'pr create'* | *'pr-open.sh'*)
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
