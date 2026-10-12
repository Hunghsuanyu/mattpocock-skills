#!/bin/bash
# PreToolUse(Bash): print a one-line reminder when the command creates a GitHub issue.
# Never blocks; always exits 0.
input=$(cat)
case "$input" in
  *"gh issue create"*)
    msg='[yu-github-workflow] 提醒：開票前確認類型／優先／驗證標籤各一個，內文走 --body-file。'
    printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$msg" "$msg"
    ;;
esac
exit 0
