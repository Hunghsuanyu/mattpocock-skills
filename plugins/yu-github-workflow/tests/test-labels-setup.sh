#!/usr/bin/env bash
# scripts/labels-setup.sh 的測試。只對假 gh 跑（mktemp 目錄、放在 PATH 最前面），不碰任何真 repo。
#   ① 兩份相等：references/labels.md 表格裡的標籤（名稱＋顏色）＝腳本會建的標籤
#   ② dry-run 不寫入：寫入類呼叫（label create／edit／delete）次數＝0；⬛ 對照：同一份夾具不加 dry-run ⇒ >0
#   ③ 查詢失敗 rc=2，而且什麼都沒寫
#   ④ 冪等：套用完的狀態再跑 dry-run ⇒ 建立 0、改名 0、刪除 0、更新 0
#   ⑤ 等待擁有者的標籤永不刪；狀態標籤只在 project 記法、沒有開著的票在用時刪
#   ⑥ 等待擁有者／機器標籤與會建、改名、刪的標籤撞名 ⇒ rc=64、一個 gh 呼叫都沒有
#   ⑦ 寫完讀回：寫入被靜默吃掉 ⇒ 不印「已」、rc=1
set -uo pipefail
TLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 9
PLUGIN="$(cd "${TLS_DIR}/.." && pwd -P)" || exit 9
S="${PLUGIN}/scripts/labels-setup.sh"
MD="${PLUGIN}/references/labels.md"
for f in "${S}" "${MD}"; do [ -f "${f}" ] || { echo "FAIL 檔案不存在：${f}"; exit 1; }; done

T="$(mktemp -d)" || exit 9
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin"
# 假 gh：記下每一次呼叫；label list 回 FAKE_LABELS 檔（寫入會改這個檔，所以讀回看得到寫入的結果）；
#   FAKE_DROP=1 ⇒ 寫入照記帳、回 0，但不改 FAKE_LABELS（模擬寫入被靜默吃掉）。
#   api 依 FAKE_COUNTS（標籤<TAB>狀態<TAB>張數）印出那麼多個票號；帶 -X／--method 的 api 呼叫算寫入，記進帳本。
cat > "${T}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_LOG}"
case "$1 $2" in
  "label list")
    [ "${FAKE_FAIL:-}" = list ] && { echo "HTTP 502" >&2; exit 1; }
    cat "${FAKE_LABELS}" ;;
  "label create"|"label edit"|"label delete")
    printf '%s\n' "$*" >> "${FAKE_WRITES}"
    op="$2" n="$3" c="" d="" nn=""; shift 3
    while [ $# -gt 0 ]; do case "$1" in --color) c="$2"; shift ;; --description) d="$2"; shift ;; --name) nn="$2"; shift ;; esac; shift; done
    if [ "${op}" = create ]; then # 另記一份「名稱<TAB>顏色<TAB>說明」，說明裡有空白也不會切錯
      printf '%s\t%s\t%s\n' "${n}" "${c}" "${d}" >> "${FAKE_WRITES}.created"
    fi
    [ "${FAKE_DROP:-}" = 1 ] && exit 0
    case "${op}" in
      create) jq --arg n "${n}" --arg c "${c}" --arg d "${d}" 'map(select(.name != $n)) + [{name: $n, color: $c, description: $d}]' ;;
      edit) jq --arg o "${n}" --arg n "${nn}" --arg c "${c}" --arg d "${d}" 'map(if .name == $o then {name: $n, color: $c, description: $d} else . end)' ;;
      delete) jq --arg n "${n}" 'map(select(.name != $n))' ;;
    esac < "${FAKE_LABELS}" > "${FAKE_LABELS}.new" && mv "${FAKE_LABELS}.new" "${FAKE_LABELS}" ;;
  api*)
    case " $* " in *" -X "*|*" --method "*) printf '%s\n' "$*" >> "${FAKE_WRITES}"; exit 0 ;; esac
    [ "${FAKE_FAIL:-}" = api ] && { echo "HTTP 502" >&2; exit 1; }
    url="$2"
    st=$(printf '%s' "${url}" | sed -n 's/.*[?&]state=\([^&]*\).*/\1/p')
    lb=$(printf '%s' "${url}" | sed -n 's/.*[?&]labels=\([^&]*\).*/\1/p')
    lb=$(python3 -I -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1]))' "${lb}")
    n=$(awk -F'\t' -v l="${lb}" -v s="${st}" '$1==l && $2==s {print $3; exit}' "${FAKE_COUNTS}")
    i=0; while [ "${i}" -lt "${n:-0}" ]; do echo $((100 + i)); i=$((i + 1)); done ;;
  *) echo "假 gh 不認得：$*" >&2; exit 3 ;;
esac
FAKE
chmod +x "${T}/bin/gh"
export PATH="${T}/bin:${PATH}" FAKE_LOG="${T}/log" FAKE_WRITES="${T}/writes" FAKE_LABELS="${T}/labels.json" FAKE_COUNTS="${T}/counts"

PASS=0 FAILN=0
ok(){ echo "ok   $1"; PASS=$((PASS + 1)); }
ng(){ echo "FAIL $1"; FAILN=$((FAILN + 1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else ng "$1（預期 [$3]，實際 [$2]）"; fi; }
reset(){ : > "${FAKE_LOG}"; : > "${FAKE_WRITES}"; : > "${FAKE_WRITES}.created"; : > "${FAKE_COUNTS}"; unset FAKE_FAIL FAKE_DROP; printf '%s' "${1:-[]}" > "${FAKE_LABELS}"; }
writes(){ grep -c . "${FAKE_WRITES}"; }
M="--machine-labels 機器甲,機器乙 --owner-wait-label 等主人"

reset '[]'
if [ "$(command -v gh)" = "${T}/bin/gh" ]; then ok "腳本拿到的是假 gh"
else ng "腳本拿到的是假 gh（$(command -v gh)）"; echo "停：不是假 gh 就不跑"; exit 1; fi

# ── ① 兩份相等 ──
md_set(){ # $1＝labels|project；印「名稱 顏色」
  awk -F'|' -v mode="$1" '
    /^\|/ && NF >= 4 {
      name=$2; color=$(NF-1); gsub(/^ +| +$/, "", name); gsub(/^ +| +$/, "", color)
      if (name !~ /^`[^`]+`$/ || color !~ /^`#[0-9A-Fa-f]{6}`$/) next
      if (mode == "project" && $0 ~ /\| *只在 `labels` 記法建 *\|/) next
      gsub(/`/, "", name); gsub(/`|#/, "", color)
      print name " " toupper(color)
    }' "${MD}" | sed -e 's/^<機器 A> /機器甲 /' -e 's/^<機器 B> /機器乙 /' -e 's/^<等待擁有者> /等主人 /' | LC_ALL=C sort
}
script_set(){ # $1＝labels|project；對空 repo 跑 dry-run，「+ 名稱 (#色)」就是會建的
  reset '[]'
  # shellcheck disable=SC2086
  bash "${S}" fake/repo --dry-run --status "$1" ${M} > "${T}/out" 2>&1 || { echo "(dry-run rc=$?)"; cat "${T}/out"; return; }
  sed -n 's/^  + \(.*\) (#\([0-9A-F]\{6\}\))$/\1 \2/p' "${T}/out" | LC_ALL=C sort
}
for mode in labels project; do
  a="$(md_set "${mode}")"; b="$(script_set "${mode}")"
  na=$(printf '%s\n' "${a}" | grep -c .)
  if [ "${na}" -ge 15 ] && [ "${a}" = "${b}" ]; then ok "① ${mode}：labels.md 與腳本的標籤相等（${na} 個）"
  else ng "① ${mode}：labels.md ${na} 個與腳本不相等"; diff <(printf '%s\n' "${a}") <(printf '%s\n' "${b}") | sed 's/^/     /'; fi
done
la=$(md_set labels | grep -c .); pa=$(md_set project | grep -c .)
check "① project 記法比 labels 記法少兩個（施工中、待驗證）" "$((la - pa))" 2

# ── ② dry-run 不寫入（⬛ 對照：拿掉 --dry-run 同一份夾具要有寫入）──
FIX='[{"name":"bug","color":"d73a4a","description":"x"},{"name":"duplicate","color":"cfd3d7","description":""},{"name":"question","color":"d876e3","description":""},{"name":"P1-高","color":"000000","description":"舊說明"},{"name":"施工中","color":"1D76DB","description":"有人正在做"},{"name":"等主人","color":"D6007A","description":"x"}]'
fill_counts(){ printf 'bug\tall\t3\nquestion\tall\t2\nduplicate\tall\t0\n施工中\topen\t0\n等主人\tall\t0\n等主人\topen\t0\n' > "${FAKE_COUNTS}"; }
for mode in labels project; do
  reset "${FIX}"; fill_counts
  # shellcheck disable=SC2086
  bash "${S}" fake/repo --dry-run --status "${mode}" ${M} > "${T}/out" 2>&1; rc=$?
  check "② ${mode} dry-run rc" "${rc}" 0
  check "② ${mode} dry-run 寫入次數" "$(writes)" 0
  grep -q '^  > bug → 錯誤（改名前 3 張）$' "${T}/out" && ok "② ${mode} dry-run 有列出改名（不是空計畫）" || ng "② ${mode} dry-run 沒列出改名"
  reset "${FIX}"; fill_counts
  # shellcheck disable=SC2086
  bash "${S}" fake/repo --status "${mode}" ${M} > "${T}/out" 2>&1; rc=$?
  w=$(writes)
  if [ "${rc}" = 0 ] && [ "${w}" -gt 0 ]; then ok "② ⬛ 對照 ${mode} 非 dry-run 有寫入（${w} 次）"; else ng "② ⬛ 對照 ${mode} 非 dry-run rc=${rc} 寫入 ${w}"; fi
done

# ── ⑤ 刪什麼、不刪什麼（接著用上面 project 記法的對照組輸出）──
grep -qx 'label delete duplicate -R fake/repo --yes' "${FAKE_WRITES}" && ok "⑤ 沒人用的預設標籤刪除" || ng "⑤ duplicate 沒被刪"
grep -q '^label delete question' "${FAKE_WRITES}" && ng "⑤ 有票在用的 question 被刪了" || ok "⑤ 有票在用的預設標籤保留"
grep -qx 'label delete 施工中 -R fake/repo --yes' "${FAKE_WRITES}" && ok "⑤ project 記法刪除沒人用的施工中" || ng "⑤ project 記法沒刪施工中"
grep -q '^label delete 等主人' "${FAKE_WRITES}" && ng "⑤ 等待擁有者的標籤被刪了" || ok "⑤ 等待擁有者的標籤不刪（沒票在用也一樣）"
grep -q '^label edit bug -R fake/repo --name 錯誤 --color 5319E7' "${FAKE_WRITES}" && ok "⑤ bug 改名成錯誤並設顏色" || ng "⑤ bug 沒改名"
reset "${FIX}"; printf '施工中\topen\t2\n' > "${FAKE_COUNTS}"
# shellcheck disable=SC2086
bash "${S}" fake/repo --status project ${M} > "${T}/out" 2>&1
grep -q '^label delete 施工中' "${FAKE_WRITES}" && ng "⑤ 有開著的票在用的施工中被刪了" || ok "⑤ 有開著的票在用的施工中保留"

# ── ③ 查詢失敗 rc=2、什麼都沒寫 ──
for f in list api; do
  reset "${FIX}"; fill_counts; export FAKE_FAIL="${f}"
  # shellcheck disable=SC2086
  bash "${S}" fake/repo --status labels ${M} > "${T}/out" 2>&1; rc=$?
  check "③ ${f} 查詢失敗 rc" "${rc}" 2
  check "③ ${f} 查詢失敗寫入次數" "$(writes)" 0
done
unset FAKE_FAIL

# ── ④ 冪等：照非 dry-run 實際建出的標籤當現況，再跑 dry-run ⇒ 全部 0 ──
reset '[]'
# shellcheck disable=SC2086
bash "${S}" fake/repo --status labels ${M} > /dev/null 2>&1
jq -Rn '[inputs | split("\t") | {name: .[0], color: .[1], description: .[2]}]' "${FAKE_WRITES}.created" > "${T}/applied.json"
reset "$(cat "${T}/applied.json")"
# shellcheck disable=SC2086
bash "${S}" fake/repo --dry-run --status labels ${M} > "${T}/out" 2>&1
check "④ 套用後再跑 dry-run" "$(grep '^會：' "${T}/out")" "會：建立 0、改名 0、刪除 0、更新 0"
check "④ 夾具不是空的" "$([ "$(jq length "${T}/applied.json")" -ge 15 ] && echo y)" y

# ── ⑥ 撞名 ⇒ rc=64、零呼叫（連讀都不讀）──
collide(){ # 名稱 參數…
  local name="$1"; shift
  reset "${FIX}"; fill_counts
  bash "${S}" fake/repo "$@" > "${T}/out" 2>&1; rc=$?
  check "⑥ ${name}：rc=64、零 gh 呼叫" "${rc} $(grep -c . "${FAKE_LOG}")" "64 0"
}
collide '等待擁有者＝固定標籤' --owner-wait-label 錯誤
collide '等待擁有者＝會改名的英文標籤' --owner-wait-label bug
collide '等待擁有者＝會刪的預設標籤' --owner-wait-label duplicate
collide '等待擁有者＝project 記法會刪的狀態標籤' --status project --owner-wait-label 施工中
collide '等待擁有者＝labels 記法的狀態標籤' --status labels --owner-wait-label 待驗證
collide '機器標籤＝固定標籤' --machine-labels 中驗證,機器乙
collide '機器標籤＝會刪的預設標籤' --machine-labels 機器甲,wontfix
collide '機器標籤＝等待擁有者' --machine-labels 機器甲,等主人 --owner-wait-label 等主人
collide '兩個機器標籤同名' --machine-labels 機器甲,機器甲
collide '大小寫不同也算撞名' --owner-wait-label Duplicate
reset "${FIX}"; fill_counts
# shellcheck disable=SC2086
bash "${S}" fake/repo --dry-run ${M} > "${T}/out" 2>&1; rc=$?
check "⑥ ⬛ 對照：不撞名 ⇒ rc=0" "${rc}" 0

# ── ⑦ 寫完讀回 ──
reset "${FIX}"; fill_counts; export FAKE_DROP=1
# shellcheck disable=SC2086
bash "${S}" fake/repo --status labels ${M} > "${T}/out" 2>&1; rc=$?
check "⑦ 寫入被吃掉：rc=1" "${rc}" 1
check "⑦ 寫入被吃掉：不印「已」" "$(grep -c '^已：' "${T}/out")" 0
check "⑦ 寫入被吃掉：有寫過（不是空跑）" "$([ "$(writes)" -gt 0 ] && echo y)" y
unset FAKE_DROP
reset "${FIX}"; fill_counts
# shellcheck disable=SC2086
bash "${S}" fake/repo --status project ${M} > "${T}/out" 2>&1; rc=$?
check "⑦ ⬛ 對照：寫入有生效 ⇒ rc=0、印「已」" "${rc} $(grep -c '^已：' "${T}/out")" "0 1"
check "⑦ 寫完有再讀一次清單" "$(grep -c '^label list' "${FAKE_LOG}")" 2

echo "通過 ${PASS}、失敗 ${FAILN}"
[ "${FAILN}" = 0 ]
