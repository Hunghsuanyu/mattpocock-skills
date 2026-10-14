#!/usr/bin/env bash
# 依 references/labels.md 在一個 repo 建標籤（冪等：已存在只更新顏色與說明）。
#
# 用法：labels-setup.sh <owner/repo> [--dry-run] [--status labels|project]
#                        [--machine-labels <A>,<B>] [--owner-wait-label <名>]
#   --dry-run           只讀：印出會建立／更新／改名／刪除的清單與張數，不呼叫任何寫入 API。
#   --status            施工狀態的記法（repo 設定「施工狀態記法」）。預設 labels。
#                       project ⇒ 不建「施工中」「待驗證」，沒有開著的票在用就刪除。
#   --machine-labels    機器標籤名（repo 設定「機器標籤名」），逗號分隔；不給就不建機器標籤。
#   --owner-wait-label  等待擁有者的標籤名（repo 設定「等待擁有者的標籤名」）。預設「等擁有者」。
#                       兩種狀態記法都建，而且永遠不刪。
#   等待擁有者與機器標籤不可以與本腳本會建、改名、刪除的標籤同名（不分大小寫），彼此也不可以同名
#   ⇒ 撞名是參數錯（rc=64），在讀、寫任何東西之前就停。
#
# 退出碼：0 成功（或 dry-run 印完）；1 寫入失敗，或寫完讀回的清單與計畫不符／讀不回來（不印「已」）；
#         2 查詢失敗（讀不到清單或張數，什麼都沒寫）；64 參數錯（含撞名）。
#
# 先讀完、算好整份計畫，才開始寫：查詢失敗時一個寫入都還沒發生，
# 而且查詢失敗絕不當成「標籤不存在」（那會另建一個空的新標籤、舊標籤連同掛著的票被留下）。
set -uo pipefail

usage(){ sed -n '4,11p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

R="" DRY=0 STATUS=labels MACHINES="" WAIT="等擁有者"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --status) [ $# -ge 2 ] || usage; STATUS="$2"; shift ;;
    --machine-labels) [ $# -ge 2 ] || usage; MACHINES="$2"; shift ;;
    --owner-wait-label) [ $# -ge 2 ] || usage; WAIT="$2"; shift ;;
    -h|--help) usage ;;
    -*) echo "未知參數：$1" >&2; usage ;;
    *) [ -z "${R}" ] || usage; R="$1" ;;
  esac
  shift
done
[ -n "${R}" ] || usage
case "${STATUS}" in labels|project) ;; *) echo "--status 只接受 labels 或 project" >&2; exit 64 ;; esac
[ -n "${WAIT}" ] || { echo "--owner-wait-label 不可為空" >&2; exit 64; }

# ── 要有的標籤：名稱、顏色、說明（與 references/labels.md 的表格相等，測試釘住）──
WANT=()      # "名稱<TAB>顏色<TAB>說明"
def(){ WANT+=("$1"$'\t'"$2"$'\t'"$3"); }
def "錯誤"   5319E7 "結果不對、壞掉"
def "新功能" 7057FF "新的功能或模組"
def "改善"   9A8CFF "改進既有功能、重構，不加新功能"
def "文件"   C5BEF7 "文件、註解、文案"
def "維護"   D4C5F9 "CI、套件升級、設定雜項"
def "資安"   3B0A9E "權限、secret、個資外洩"
def "P0-阻斷" B60205 "生產壞了或有資安事故，其他工作先停"
def "P1-高"   FB8C00 "這批一定要完成"
def "P2-一般" FBCA04 "照排程處理"
def "P3-低"   CCCCCC "有空再做"
def "輕驗證"      C2E0C6 "不改行為（文件、註解、標籤、看得到的小設定）：CI 綠即可"
def "中驗證"      0E8A16 "改到行為：CI＋突變（只突變改到的斷言）＋真環境讀回＋對照組"
def "重驗證-自檢" F9A825 "②密鑰共用設定④不可逆（含對外送出）⑤個人資料：中級全部＋該類專屬證據"
def "重驗證-外審" D93F0B "①部署管線③存取權限、身分判斷：中級全部＋換廠牌對抗式外審"
def "衍生"   FEF2C0 "做的過程中意外冒出、超出原票完成定義的票（直接掛 SPEC）"
if [ "${STATUS}" = labels ]; then
  def "施工中" 1D76DB "有人正在做"
  def "待驗證" 5DADE2 "做完了，等驗證"
fi
NFIXED=${#WANT[@]}   # 以上是固定標籤；以下是使用者指定名稱的標籤（等待擁有者、機器）
def "${WAIT}" D6007A "等擁有者合併、部署、拍板或動手"
MCOLORS=(006B75 1B9AAA)
if [ -n "${MACHINES}" ]; then
  i=0; IFS=',' read -r -a _m <<< "${MACHINES}"
  for m in "${_m[@]}"; do
    [ -n "${m}" ] || { echo "--machine-labels 有空的名稱" >&2; exit 64; }
    def "${m}" "${MCOLORS[$((i % ${#MCOLORS[@]}))]}" "現在處理這張票的人在這台機器上"; i=$((i+1))
  done
fi

# GitHub 預設英文標籤：三個改名（已掛的票自動跟著改），六個在沒有票使用時刪除。
RENAME_FROM=(bug documentation enhancement)
RENAME_TO=(錯誤 文件 改善)
DEFAULT_DROP=(duplicate wontfix invalid question "good first issue" "help wanted")
# 狀態記法是 project 時，這兩個標籤只在沒有「開著的」票使用時刪除。等待擁有者的標籤不在這裡，永不刪。
STATUS_DROP=()
[ "${STATUS}" = project ] && STATUS_DROP=(施工中 待驗證)

# ── 撞名檢查（還沒讀、還沒寫）：指定名稱的標籤撞到固定標籤、狀態標籤、會改名或刪的英文標籤，或彼此撞名 ⇒ 64 ──
lc(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }   # GitHub 的標籤名不分大小寫
taken="|"
for w in "${WANT[@]:0:${NFIXED}}"; do taken="${taken}$(lc "${w%%$'\t'*}")|"; done
for l in 施工中 待驗證 "${RENAME_FROM[@]}" "${DEFAULT_DROP[@]}"; do taken="${taken}$(lc "${l}")|"; done
for w in "${WANT[@]:${NFIXED}}"; do
  n="${w%%$'\t'*}" k="$(lc "${w%%$'\t'*}")"
  case "${taken}" in *"|${k}|"*)
    echo "標籤名「${n}」與本腳本會建、改名或刪除的標籤（或另一個指定的名稱）撞名，中止（什麼都沒讀、沒寫）" >&2; exit 64 ;;
  esac
  taken="${taken}${k}|"
done

# ── 讀現況（只讀）──
if ! CUR_JSON=$(gh label list -R "${R}" --limit 500 --json name,color,description); then
  echo "✘ 讀不到 ${R} 的標籤清單，中止（什麼都沒寫）" >&2; exit 2
fi
if ! CUR=$(printf '%s' "${CUR_JSON}" | jq -r '.[] | [.name, (.color|ascii_upcase), (.description // "")] | @tsv'); then
  echo "✘ ${R} 的標籤清單不是預期的 JSON，中止（什麼都沒寫）" >&2; exit 2
fi
have(){ printf '%s\n' "${CUR}" | cut -f1 | grep -Fxq -- "$1"; }
cur_of(){ printf '%s\n' "${CUR}" | awk -F'\t' -v n="$1" '$1==n {print $2"\t"$3; exit}'; }
# 用 REST 列票而不用 gh issue list --label：後者走搜尋索引，剛改名時會暫時回 0。
count(){ # 標籤 狀態(all|open)；失敗回非 0
  local e out
  e=$(jq -rn --arg s "$1" '$s|@uri') || return 1
  out=$(gh api "repos/${R}/issues?state=$2&labels=${e}&per_page=100" --paginate --jq '.[].number') || return 1
  printf '%s\n' "${out}" | grep -c '[0-9]'
}
# 結果放在全域 CNT。不可以寫成 $(count_or_die …)：exit 2 只會離開子殼層，主程式照跑。
count_or_die(){ local n rc; n=$(count "$1" "$2"); rc=$?
  # grep -c 沒命中回 1 但會印 0；沒印出數字、或退出碼大於 1，才算查詢失敗
  case "${n}" in ''|*[!0-9]*) rc=9 ;; esac
  [ "${rc}" -le 1 ] || { echo "✘ 數不到 $1 的票數，中止（什麼都沒寫）" >&2; exit 2; }
  CNT="${n}"; }

# ── 算計畫 ──
P_CREATE=() P_UPDATE=() P_RENAME=() P_DELETE=() P_KEEP=() P_WARN=()
renamed_to=""
for k in "${!RENAME_FROM[@]}"; do
  o="${RENAME_FROM[${k}]}" n="${RENAME_TO[${k}]}"
  have "${o}" || continue
  if have "${n}"; then
    count_or_die "${o}" all; P_WARN+=("${o} 與 ${n} 並存（${o} 有 ${CNT} 張），要手動合併")
  else
    count_or_die "${o}" all; P_RENAME+=("${o}"$'\t'"${n}"$'\t'"${CNT}"); renamed_to+="|${n}|"
  fi
done
for w in "${WANT[@]}"; do
  IFS=$'\t' read -r n c d <<< "${w}"
  case "${renamed_to}" in *"|${n}|"*) continue ;; esac   # 由改名產生，改名時一併設顏色與說明
  if have "${n}"; then
    [ "$(cur_of "${n}")" = "${c}"$'\t'"${d}" ] || P_UPDATE+=("${w}")
  else
    P_CREATE+=("${w}")
  fi
done
for l in "${DEFAULT_DROP[@]}"; do
  have "${l}" || continue
  count_or_die "${l}" all; u="${CNT}"
  if [ "${u}" = 0 ]; then P_DELETE+=("${l}"); else P_KEEP+=("${l}（${u} 張在用，列給擁有者決定）"); fi
done
for l in ${STATUS_DROP[@]+"${STATUS_DROP[@]}"}; do   # macOS 的 bash 3.2 在 set -u 下展開空陣列會報錯
  have "${l}" || continue
  count_or_die "${l}" open; u="${CNT}"
  if [ "${u}" = 0 ]; then P_DELETE+=("${l}"); else P_KEEP+=("${l}（${u} 張開著的票在用，先把狀態搬進 Project 再重跑）"); fi
done

# ── 印計畫 ──
[ "${DRY}" = 1 ] && echo "== ${R}（dry-run，只讀）" || echo "== ${R}"
for w in ${P_CREATE[@]+"${P_CREATE[@]}"}; do IFS=$'\t' read -r n c _ <<< "${w}"; echo "  + ${n} (#${c})"; done
for w in ${P_UPDATE[@]+"${P_UPDATE[@]}"}; do IFS=$'\t' read -r n c _ <<< "${w}"; echo "  ~ ${n} (#${c})"; done
for w in ${P_RENAME[@]+"${P_RENAME[@]}"}; do IFS=$'\t' read -r o n u <<< "${w}"; echo "  > ${o} → ${n}（改名前 ${u} 張）"; done
for l in ${P_DELETE[@]+"${P_DELETE[@]}"}; do echo "  - ${l}"; done
for l in ${P_KEEP[@]+"${P_KEEP[@]}"}; do echo "  ⚠️ 保留 ${l}"; done
for l in ${P_WARN[@]+"${P_WARN[@]}"}; do echo "  ⚠️ ${l}"; done
SUMMARY="建立 ${#P_CREATE[@]}、改名 ${#P_RENAME[@]}、刪除 ${#P_DELETE[@]}、更新 ${#P_UPDATE[@]}"

if [ "${DRY}" = 1 ]; then echo "會：${SUMMARY}"; exit 0; fi

# ── 執行（只有非 dry-run 走到這裡）──
fail(){ echo "✘ 寫入失敗：$1（已完成的步驟不回復，修好後重跑即可，腳本冪等）" >&2; exit 1; }
for w in ${P_RENAME[@]+"${P_RENAME[@]}"}; do
  IFS=$'\t' read -r o n _ <<< "${w}"
  for x in "${WANT[@]}"; do IFS=$'\t' read -r xn xc xd <<< "${x}"; [ "${xn}" = "${n}" ] && break; done
  gh label edit "${o}" -R "${R}" --name "${n}" --color "${xc}" --description "${xd}" > /dev/null || fail "改名 ${o} → ${n}"
done
for w in ${P_CREATE[@]+"${P_CREATE[@]}"} ${P_UPDATE[@]+"${P_UPDATE[@]}"}; do
  IFS=$'\t' read -r n c d <<< "${w}"
  gh label create "${n}" -R "${R}" --color "${c}" --description "${d}" --force > /dev/null || fail "建立/更新 ${n}"
done
for l in ${P_DELETE[@]+"${P_DELETE[@]}"}; do
  gh label delete "${l}" -R "${R}" --yes > /dev/null || fail "刪除 ${l}"
done

# ── 讀回：每個要有的標籤都在、顏色與說明相符；刪掉的與改名前的不在。不符就不印「已」──
if ! AFTER_JSON=$(gh label list -R "${R}" --limit 500 --json name,color,description); then
  echo "✘ 寫完讀不回 ${R} 的標籤清單，不能確認寫入生效（重跑 --dry-run 看現況）" >&2; exit 1
fi
if ! AFTER=$(printf '%s' "${AFTER_JSON}" | jq -r '.[] | [.name, (.color|ascii_upcase), (.description // "")] | @tsv'); then
  echo "✘ 寫完讀回的標籤清單不是預期的 JSON，不能確認寫入生效" >&2; exit 1
fi
MISS=()
for w in "${WANT[@]}"; do
  printf '%s\n' "${AFTER}" | grep -Fxq -- "${w}" || MISS+=("${w%%$'\t'*}（不在或顏色、說明不符）")
done
for w in ${P_RENAME[@]+"${P_RENAME[@]}"}; do
  o="${w%%$'\t'*}"; printf '%s\n' "${AFTER}" | cut -f1 | grep -Fxq -- "${o}" && MISS+=("${o}（改名後還在）")
done
for l in ${P_DELETE[@]+"${P_DELETE[@]}"}; do
  printf '%s\n' "${AFTER}" | cut -f1 | grep -Fxq -- "${l}" && MISS+=("${l}（刪除後還在）")
done
if [ "${#MISS[@]}" -gt 0 ]; then
  echo "✘ 寫完讀回與計畫不符（不算完成，修好後重跑即可，腳本冪等）：" >&2
  printf '  %s\n' "${MISS[@]}" >&2
  exit 1
fi
echo "已：${SUMMARY}"
