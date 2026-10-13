#!/usr/bin/env bash
# 用法：pr-risk.sh <owner/repo> <票號…>
#
# 讀一批票的驗證標籤、內文與留言（只讀，不寫任何東西），印出 PR 內文的「合併風險」段與連票清單。
# 合併風險由驗證等級帶出，不靠寫 PR 的人判斷；判準是 references/labels.md 的驗證段。
#   - 門：有一張票掛 `重驗證-自檢` 或 `重驗證-外審`、而且內文標了④（不可逆）→ 單向門；
#         有票沒掛驗證標籤 → 未定；其餘 → 雙向門。
#   - 外審：掛 `重驗證-外審` 的票，列出驗證者結論留言的連結（留言最後一行是「— 🔍 …」署名、含「結果」）；
#           找不到就照實印出來，不省略。
#   - 連票：合併後還有步驟的票寫 Refs，其餘寫 Closes。「合併後還有步驟」的判法在
#           scripts/lib/after-merge-step.sh，開票自檢用同一份。
#   - 影響範圍只印佔位，由開 PR 的人填一個詞。
#
# 退出碼：0 成功；2 有一張票讀不到或讀到的形狀不對——stdout 什麼都不印，不輸出半份；64 參數錯。
set -uo pipefail
PRR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 9
# shellcheck source=lib/after-merge-step.sh
. "${PRR_DIR}/lib/after-merge-step.sh" || exit 9

prr_usage() { echo "用法：pr-risk.sh <owner/repo> <票號…>" >&2; exit 64; }
[ $# -ge 2 ] || prr_usage
REPO="$1"; shift
case "${REPO}" in */*) ;; *) prr_usage ;; esac
for n in "$@"; do case "${n}" in '' | *[!0-9]*) prr_usage ;; esac; done

T="$(mktemp -d)" || exit 9
trap 'rm -rf "${T}"' EXIT

# 把 gh 回的 JSON 拆成三個檔：<前綴>.labels（一行一個標籤）、<前綴>.body、<前綴>.review（結論留言網址，沒有就空）
PRR_PY=''
IFS= read -r -d '' PRR_PY <<'PY' || true
import json, sys
src, out, want = sys.argv[1], sys.argv[2], int(sys.argv[3])
d = json.load(open(src, encoding="utf-8"))
if not isinstance(d, dict) or d.get("number") != want or not isinstance(d.get("labels"), list) \
        or not isinstance(d.get("body"), str) or not isinstance(d.get("comments"), list):
    keys = sorted(d) if isinstance(d, dict) else type(d).__name__
    sys.exit("形狀不對（鍵：%s）" % (keys,))
review = ""
for c in d["comments"]:
    lines = [x for x in (c.get("body") or "").splitlines() if x.strip()]
    if lines and lines[-1].lstrip().startswith("— 🔍") and "結果" in lines[-1]:
        review = c.get("url") or ""
with open(out + ".labels", "w", encoding="utf-8") as f:
    f.write("".join(l["name"] + "\n" for l in d["labels"]))
with open(out + ".body", "w", encoding="utf-8") as f:
    f.write(d["body"])
with open(out + ".review", "w", encoding="utf-8") as f:
    f.write(review)
PY

# ── 1. 先全部讀完；任何一張讀不到就停，不印半份 ──
for n in "$@"; do
  if ! gh issue view "${n}" -R "${REPO}" --json number,url,labels,body,comments > "${T}/${n}.json" 2> "${T}/${n}.err"; then
    echo "pr-risk: 讀不到 ${REPO} 的票 ${n}，什麼都沒印（不可以當成沒有風險）：" >&2
    cat "${T}/${n}.err" >&2
    exit 2
  fi
  if ! python3 -I -c "${PRR_PY}" "${T}/${n}.json" "${T}/${n}" "${n}" 2> "${T}/${n}.err"; then
    echo "pr-risk: ${REPO} 的票 ${n} 讀回來的形狀不對，什麼都沒印：" >&2
    cat "${T}/${n}.err" >&2
    exit 2
  fi
done

# ── 2. 逐張判定 ──
rows=() reviews=() links=()
any_one_way=0 any_unknown=0 any_review=0
for n in "$@"; do
  ref="${REPO}#${n}"
  labels="$(cat "${T}/${n}.labels")"
  body="$(cat "${T}/${n}.body")"
  level=''
  for L in 重驗證-外審 重驗證-自檢 中驗證 輕驗證; do # 同時掛了多個取最重的
    if grep -qxF -- "${L}" <<< "${labels}"; then level="${L}"; break; fi
  done

  irrev=0
  case "${level}" in
    重驗證-自檢 | 重驗證-外審) [[ "${body}" == *④* ]] && irrev=1; ;;
  esac

  if [ -z "${level}" ]; then
    any_unknown=1; rows+=("| ${ref} | （沒掛驗證標籤） | 未定 |")
  elif [ "${irrev}" = 1 ]; then
    any_one_way=1; rows+=("| ${ref} | ${level} | 單向門（內文標了④不可逆） |")
  else
    rows+=("| ${ref} | ${level} | 雙向門 |")
  fi

  if [ "${level}" = 重驗證-外審 ]; then
    any_review=1
    url="$(cat "${T}/${n}.review")"
    if [ -n "${url}" ]; then reviews+=("- ${ref}：${url}")
    else
      reviews+=("- ${ref}：找不到驗證者的結論留言（最後一行「— 🔍 …」署名、含「結果」）——外審沒做完不開 PR")
      echo "pr-risk: ${ref} 掛了 重驗證-外審，找不到結論留言" >&2
    fi
  fi

  if has_after_merge_step "${body}"; then links+=("Refs ${ref}"); else links+=("Closes ${ref}"); fi
done

if [ "${any_one_way}" = 1 ]; then door=單向門
elif [ "${any_unknown}" = 1 ]; then door='未定（有票沒掛驗證標籤）'
else door=雙向門; fi

# ── 3. 輸出 ──
echo "## 合併風險"
echo
echo "**門：** ${door}"
echo "**影響範圍：** <一個詞，開 PR 的人填>"
echo
echo "| 票 | 驗證 | 這張的門 |"
echo "|---|---|---|"
printf '%s\n' "${rows[@]}"
if [ "${any_review}" = 1 ]; then
  echo
  echo "**外審結論：**"
  printf '%s\n' "${reviews[@]}"
fi
echo
echo "## 連票"
echo
printf '%s\n' "${links[@]}"
