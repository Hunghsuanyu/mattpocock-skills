#!/usr/bin/env bash
# 用法：pr-risk.sh <owner/repo> <票號…>
#
# 讀一批票的驗證標籤、內文與留言（只讀，不寫任何東西），印出逐票事實表與 `## 連票` 段。
# 不印 `## 合併風險` 標題：那段標題與 Door／Blast Radius 由開 PR 的人寫，事實表貼在下面。
# 只列事實、不判門：Door（one-way／two-way）與 Blast Radius 由開 PR 的模型看實際改動自己寫。
#   - 每張票一列：驗證標籤（同時掛好幾個取最重的；沒掛就照實寫）、外審結論、有沒有合併後步驟。
#   - 外審結論：只看掛 `重驗證-外審` 的票（其他票印「不需要」）。找驗證者的結論留言——留言最後一個非空行
#     以「— 🔍」開頭、而且含「結果」，現行署名格式是
#       — 🔍 驗證｜<機器>｜session <8 碼>｜分支 <整合分支>｜結果：通過
#     有好幾則取最後一則。「結果」後面（去掉冒號與空白）恰好是「通過」才算通過，「不通過」「有條件通過」都不算。
#     印「有：<留言網址>」「不通過：<留言網址>」或「無（找不到結論留言）」。
#     留言是 `gh issue view --json comments` 讀的：gh 會自己分頁讀完全部留言，沒有 100 則上限。
#   - 連票：合併後還有步驟的票寫 Refs，其餘寫 Closes。「合併後還有步驟」的判法在
#           scripts/lib/after-merge-step.sh，開票自檢用同一份。
#
# 退出碼：0 全部讀到、沒有未定；
#         3 未定——有掛 `重驗證-外審` 的票外審結論缺席或不通過，或有票沒掛驗證標籤。
#           stdout 照常印完整輸出，表格後面多一行「**未定：** <原因>」；先補齊、不開 PR；
#         2 有一張票讀不到或讀到的形狀不對——stdout 什麼都不印，不輸出半份；64 參數錯。
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

# 把 gh 回的 JSON 拆成四個檔：<前綴>.labels（一行一個標籤）、<前綴>.body、
#   <前綴>.review（最後一則結論留言的網址，沒有就空）、<前綴>.verdict（那則的結果：pass／fail，沒有就空）
PRR_PY=''
IFS= read -r -d '' PRR_PY <<'PY' || true
import json, sys
src, out, want = sys.argv[1], sys.argv[2], int(sys.argv[3])
d = json.load(open(src, encoding="utf-8"))
if not isinstance(d, dict) or d.get("number") != want or not isinstance(d.get("labels"), list) \
        or not isinstance(d.get("body"), str) or not isinstance(d.get("comments"), list):
    keys = sorted(d) if isinstance(d, dict) else type(d).__name__
    sys.exit("形狀不對（鍵：%s）" % (keys,))
review = verdict = ""
for c in d["comments"]:
    lines = [x for x in (c.get("body") or "").splitlines() if x.strip()]
    if lines and lines[-1].lstrip().startswith("— 🔍") and "結果" in lines[-1]:
        review = c.get("url") or ""
        # 「結果」後面（去掉全形／半形冒號與空白）恰好是「通過」才算通過；「不通過」「有條件通過」都不算
        res = lines[-1].rsplit("結果", 1)[1].strip().lstrip("：:").strip()
        verdict = "pass" if res == "通過" else "fail"
with open(out + ".labels", "w", encoding="utf-8") as f:
    f.write("".join(l["name"] + "\n" for l in d["labels"]))
with open(out + ".body", "w", encoding="utf-8") as f:
    f.write(d["body"])
with open(out + ".review", "w", encoding="utf-8") as f:
    f.write(review)
with open(out + ".verdict", "w", encoding="utf-8") as f:
    f.write(verdict)
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

# ── 2. 逐張列事實 ──
rows=() links=()
u_label=0 u_review=0 # 兩種「未定」
for n in "$@"; do
  ref="${REPO}#${n}"
  labels="$(cat "${T}/${n}.labels")"
  body="$(cat "${T}/${n}.body")"
  level=''
  for L in 重驗證-外審 重驗證-自檢 中驗證 輕驗證; do # 同時掛了多個取最重的
    if grep -qxF -- "${L}" <<< "${labels}"; then level="${L}"; break; fi
  done
  [ -n "${level}" ] || { u_label=1; level='（沒掛驗證標籤）'; }

  review='不需要'
  if [ "${level}" = 重驗證-外審 ]; then
    url="$(cat "${T}/${n}.review")"
    verdict="$(cat "${T}/${n}.verdict")"
    if [ -z "${url}" ]; then
      u_review=1; review='無（找不到結論留言）'
      echo "pr-risk: ${ref} 掛了 重驗證-外審，找不到結論留言" >&2
    elif [ "${verdict}" != pass ]; then
      u_review=1; review="不通過：${url}"
      echo "pr-risk: ${ref} 掛了 重驗證-外審，最後一則結論不是通過" >&2
    else
      review="有：${url}"
    fi
  fi

  if has_after_merge_step "${body}"; then after='有'; links+=("Refs ${ref}"); else after='無'; links+=("Closes ${ref}"); fi
  rows+=("| ${ref} | ${level} | ${review} | ${after} |")
done

reasons=''
[ "${u_review}" = 1 ] && reasons="${reasons}；有掛 重驗證-外審 的票外審結論缺席或不通過"
[ "${u_label}" = 1 ] && reasons="${reasons}；有票沒掛驗證標籤"

# ── 3. 輸出（不印「合併風險」標題：那段標題與 Door／Blast Radius 由開 PR 的人寫，表格貼在它們下面）──
echo "| 票 | 驗證標籤 | 外審結論 | 合併後步驟 |"
echo "|---|---|---|---|"
printf '%s\n' "${rows[@]}"
if [ -n "${reasons}" ]; then
  echo
  echo "**未定：** ${reasons#；}"
fi
echo
echo "## 連票"
echo
printf '%s\n' "${links[@]}"
[ -z "${reasons}" ] || exit 3
