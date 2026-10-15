#!/usr/bin/env bash
# scripts/ticket-check.sh 的測試。只對假 gh 跑（mktemp 目錄、放在 PATH 最前面），不碰任何真 repo。
#   上半：source 腳本取函式，逐格測判準（每格一張「從好票故意做壞一處」的陽性對照，好票先要是綠的）。
#   下半：整支對假 gh 跑主體——設定讀不到（帳號不知道 ⇒ UNKNOWN 不判紅，⬛ 對照：同一份夾具有設定 ⇒ 紅）、
#         格 9、錨點、project 記法不讀 Project。
#   最後：開票自檢 workflow 範本的 run: 主體裡不得出現 ${{ github.event.…（靜態檢查）。
# 票號一律在執行時組出（H 變數），檔案裡不寫「井號接數字」；署名裡的 id 用純字母的虛構值。
#
# 用法：tests/test-ticket-check.sh
# 退出碼：0＝全過；1＝有案例失敗。
set -uo pipefail
TTC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 9
TTC_SCRIPT="$(cd "${TTC_DIR}/../scripts" && pwd -P)/ticket-check.sh" || exit 9
[ -f "${TTC_SCRIPT}" ] || { echo "FAIL 檔案不存在：${TTC_SCRIPT}"; exit 1; }
# shellcheck source=/dev/null
source "${TTC_SCRIPT}"   # 只取函式；腳本有 sourced 防護，不會跑主體
set +e                   # 腳本開了 -e；測試要自己數失敗，不能第一個紅就離開

H='#'
pass=0; fail=0
want_skip()  { if anchor_skip_title "$1"; then pass=$((pass+1)); else fail=$((fail+1)); printf '🔴 該跳過卻沒跳：%s\n' "$1"; fi; }
want_check() { if anchor_skip_title "$1"; then fail=$((fail+1)); printf '🔴 該檢查卻跳過了：%s\n' "$1"; else pass=$((pass+1)); fi; }

# ══ 錨點：哪些票該跳過 ══
want_skip  '[SPEC] 獎金串流：參加獎、獎金卡版面'
want_skip  'SPEC 前端與後端搬進新的組織'
want_skip  '協作指揮台：票序 + 誰在做哪張 + 下一步'
want_skip  "[外審] SPEC ${H}36 獎金串流：規格對抗驗證"
want_skip  '[外審] 規格對抗驗證'            # 不含 SPEC 也要跳

want_check "[施工] 依 SPEC ${H}36 實作參加獎"   # 標題提到 SPEC 不是豁免理由
want_check '[施工] 參加獎：報到即得'
want_check '[查證] 報到紀錄的內部碼欄'
want_check '[修正] 獎金卡改用內部碼對人'
want_check '[閘門] 實機：線上／離線同快照一致'
want_check 'Sheet 公式套用'                  # 方括號沒加引號就會變字元類而誤跳
want_check 'Codex 外審腳本修正'

# ══ 標籤格 1、2 ══
L48='重驗證-外審,維護,P2-一般'
L50='文件,中驗證,P2-一般'
L41='資安,P2-一般'
T48="[實作] ${H}41 第 0 批：測試地基、機器檢查、過期註解"
T50='[衍生] 文件裡的舊函式名跟上'
T41='[SPEC] 第二道全面補上比角色'

want_kind() {  # 標題 期望種類 [附註要含的字]
  local got k note; got=$(ticket_kind "$1"); k="${got%%$'\t'*}"; note="${got#*$'\t'}"
  if [ "$k" != "$2" ]; then fail=$((fail+1)); printf '🔴 票種 %s：要 %s、得 %s\n' "$1" "$2" "$k"; return; fi
  if [ -z "${3:-}" ] && [ -n "$note" ]; then fail=$((fail+1)); printf '🔴 票種 %s：不該有附註、得「%s」\n' "$1" "$note"; return; fi
  case "$note" in *"${3:-}"*) pass=$((pass+1)) ;;
    *) fail=$((fail+1)); printf '🔴 票種附註 %s：要含「%s」、得「%s」\n' "$1" "$3" "$note" ;; esac
}
# state title labels ⇒ 不該有任何違規。
want_clean() {
  local out; out=$(label_problems "$1" "$2" "$3")
  if [ -z "$out" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf '🔴 該綠卻紅（%s｜%s）：%s\n' "$1" "$3" "$out"; fi
}
want_ng() {  # 格號 state title labels ⇒ 必須出現「格N」
  local out; out=$(label_problems "$2" "$3" "$4")
  case "$out" in
    *"格$1"*) pass=$((pass+1)); printf '   ✔ 陽性對照 格%s 紅：%s\n' "$1" "$(printf '%s' "$out" | tr '\n' '／')" ;;
    *) fail=$((fail+1)); printf '🔴 格%s 該紅卻沒紅（%s｜%s）：%s\n' "$1" "$2" "$4" "$out" ;;
  esac
}

# ── 票種（只認 SPEC 與協作指揮台兩個例外） ──
want_kind "$T48" 一般
want_kind '[施工] 參加獎：報到即得' 一般
want_kind 'Sheet 公式套用' 一般
want_kind "$T41" SPEC
want_kind 'SPEC 前端與後端搬進新的組織' SPEC
want_kind '[決定] 搬進組織後誰能寫' 一般
want_kind '[盤點] 全組織 Actions 憑證' 一般
want_kind "[外審] ${H}12 規格對抗驗證" 一般   # 錨點跳過、標籤照查
want_kind '協作指揮台：票序 + 誰在做哪張' 協調
want_kind '[施工] 指揮台格式修正' 一般        # 只認開頭
want_kind "$T50" 一般
want_kind '[修正] preflight' 一般

# ── 基準票：要是綠的 ──
want_clean open   "$T48" "$L48"
want_clean closed "$T50" "$L50"
want_clean open   "$T41" "$L41"                 # SPEC 沒掛驗證不判紅
want_clean open   '協作指揮台：票序' ''           # 協調類什麼都不必掛
want_clean OPEN   "$T48" "$L48"                 # 大寫的 state
want_clean closed '[實作] 舊票' '重驗證-外審'    # 已關的舊票不查格 1
want_clean open   "$T48" "$L48,施工中,機器A"     # 狀態與機器標籤不歸這支管

# ── 格 1：必掛 ──
want_ng 1 open "$T48" "${L48/重驗證-外審,/}"
want_ng 1 open "$T48" "${L48/維護,/}"
want_ng 1 open "$T48" "${L48/,P2-一般/}"
want_ng 1 open "$T41" "${L41/,P2-一般/}"
want_ng 1 open '[決定] 搬進組織後誰能寫' '改善,P2-一般'
want_ng 1 open "$T50" "${L50/中驗證,/}"
want_ng 1 open "$T48" "${L48/重驗證-外審/待驗證}"   # 待驗證是狀態不是驗證分級（逐字比對）
want_ng 1 open "$T48" "${L48/維護/類型:維護}"       # 帶前綴的舊名不算數

# ── 格 2：單選 ──
want_ng 2 open   "$T48" "$L48,錯誤"
want_ng 2 open   "$T48" "$L48,P0-阻斷"
want_ng 2 open   "$T48" "$L48,中驗證"
want_ng 2 closed "$T50" "$L50,改善"
want_clean open  "$T48" "$L48,等擁有者"   # 等待擁有者的標籤不是狀態組

# ══ 格 6：衍生（掛了 `衍生` ⇒ 上層必須是 SPEC） ══
want_d6() {  # 期望（clean／NG） 上層票標題（空＝沒有上層） labels
  local out; out=$(derive_problems "$2" "$3")
  case "$1:$out" in
    clean:) pass=$((pass+1)) ;;
    NG:*格6*) pass=$((pass+1)); printf '   ✔ 陽性對照 %s\n' "$out" ;;
    *) fail=$((fail+1)); printf '🔴 格6 要 %s（上層「%s」｜%s）：得「%s」\n' "$1" "$2" "$3" "$out" ;;
  esac
}
want_d6 clean "$T41" "$L50,衍生"
want_d6 clean 'SPEC 前端搬進組織' "衍生,$L50"
want_d6 clean "$T41" "$L48"
want_d6 clean ''     "$L48"
want_d6 clean "$T48" "$L50"
want_d6 clean "$T41" "$L50,衍生票"                # 名字不對＝沒掛
want_d6 NG    "$T48" "$L50,衍生"                  # 掛在施工票底下 ⇒ SPEC 看不到
want_d6 NG    '[查證] 角色來源' "衍生,$L50"
want_d6 NG    ''     "$L50,衍生"

# ══ 設定區塊解析 ══
CFG_DOC="$(printf '%s\n' '# GitHub 工作流設定' '' '## 機器讀的欄位' '' '```text' \
  '票開在哪個 repo: 本 repo' '施工狀態記法: project' 'Project 所在: example-org 3' \
  '機器標籤名: 機器A,機器B' '只檢查誰開的票:  owner-a  ' '特殊禁忌: 無	' '```' '' '## 部署線' '' '```text' '施工狀態記法: labels' '```')"
blk=$(printf '%s\n' "$CFG_DOC" | cfg_block)
want_cfg() {  # 欄位 期望
  local got; got=$(cfg_get "$blk" "$1")
  if [ "$got" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf '🔴 設定 %s：要「%s」、得「%s」\n' "$1" "$2" "$got"; fi
}
want_cfg 施工狀態記法 project                 # 只讀「機器讀的欄位」底下第一個 text 區塊
want_cfg 只檢查誰開的票 owner-a
want_cfg 等待擁有者的標籤名 ''                   # 沒有這個欄位 ⇒ 空
want_cfg 特殊禁忌 '無'                           # 值去頭尾空白（含 tab）
# ══ 格 9：做完能展示什麼 ══
want_d9() {  # 期望（clean／NG） 內文
  local out; out=$(printf '%s\n' "$2" | demo_problem)
  case "$1:$out" in
    clean:) pass=$((pass+1)) ;;
    NG:格9*) pass=$((pass+1)); printf '   ✔ 陽性對照 %s\n' "$out" ;;
    *) fail=$((fail+1)); printf '🔴 格9 要 %s：得「%s」\n' "$1" "$out" ;;
  esac
}
want_d9 clean $'## 做完能展示什麼\n跑出來的清單和舊版相同。\n\n## 錨點\n- x'
want_d9 clean $'## 做完能展示什麼\n### 畫面\n看得到新欄位。\n## 錨點'   # 子標題底下的內容算數
want_d9 NG    $'## 錨點\n- x\n## 待辦\n1. y'                              # 沒有這段
want_d9 NG    $'## 做完能展示什麼\n\n   \n## 錨點\n- x'                    # 空段
want_d9 NG    $'## 做完能展示什麼\n## 錨點\n- x'                           # 緊接下一段
want_d9 NG    $'說明裡提到做完能展示什麼，但不是標題\n## 錨點'
want_d9 NG    $'## 做完能展示什麼\n### 畫面\n\n## 錨點\n- x'                # 只有子標題、沒有內容 ⇒ 空的

# ══ 整支對假 gh 跑主體 ══
# 假 gh：依 FX 目錄裡的夾具回「jq 之後」的輸出；記下每一次呼叫；只認讀取型呼叫，其他一律 exit 97。
T=$(mktemp -d) || exit 9
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
fx() { if [ -f "$FX/$1" ]; then cat "$FX/$1"; fi; }
case " $* " in
  *" -X "*|*" --method "*|*" -f body="*) echo "假 gh：拒絕寫入型呼叫 $*" >&2; exit 97 ;;
esac
case "$1 $2" in
  'api -H')
    case "$*" in
      *contents/docs/agents/github.md*)
        [ -f "$FX/config.md" ] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
        cat "$FX/config.md" ;;
      *) echo "假 gh：沒預期的呼叫 $*" >&2; exit 97 ;;
    esac ;;
  'api graphql')
    case "$*" in
      *'parent{title}'*)                   fx parents ;;
      *'nodes{number body}'*)              fx bodies ;;
      *) echo "假 gh：沒預期的 graphql $*" >&2; exit 97 ;;
    esac ;;
  'api --paginate')
    case "$3" in
      repos/*/labels*)        fx labels ;;
      repos/*/issues*)        fx issues ;;
      *) echo "假 gh：沒預期的呼叫 $*" >&2; exit 97 ;;
    esac ;;
  'api repos/'*)
    case "$2" in
      */commits/*) c="${2##*/}"
                   case "$(cat "$FX/commit-$c" 2>&1)" in
                     422) echo "gh: No commit found for SHA: $c (HTTP 422)" >&2; exit 1 ;;
                     404) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
                   esac; exit 0 ;;
      *) echo "假 gh：沒預期的呼叫 $*" >&2; exit 97 ;;
    esac ;;
  *) echo "假 gh：沒預期的呼叫 $*" >&2; exit 97 ;;
esac
FAKE
chmod +x "$T/bin/gh"
export FAKE_LOG="$T/calls.log"; : > "$FAKE_LOG"

if [ "$(PATH="$T/bin:$PATH" command -v gh)" = "$T/bin/gh" ]; then pass=$((pass+1))
else echo "🔴 拿到的不是假 gh（$(PATH="$T/bin:$PATH" command -v gh)）"; echo "停：不是假 gh 就不跑"; exit 1; fi

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
SHA=0123456789abcdef0123456789abcdef01234567
ANC="## 錨點
- [x](https://github.com/example-org/app-one/blob/${SHA}/a.sh)"
DEMO='## 做完能展示什麼
跑出來的清單。'
GOODL='改善,P2-一般,中驗證'
# 票 1 的內文：票內文只從「開著的票內文」那一次 GraphQL 拿（每張開著的票都有 body），不逐票 issue view。
setbody() {  # 目錄 內文
  printf '1\t%s\n3\t%s\n' "$(b64 "$2")" "$(b64 '## 背景')" > "$1/bodies"
}
# 一個 repo 的夾具：$1＝目錄、$2＝已關的票 2 多掛的標籤；票 1 開著（施工中）、票 2 已關、票 3 SPEC。
mkfx() {
  local d="$1" extra="${2:-}"; mkdir -p "$d"
  printf '錯誤\n文件\n改善\n施工中\n待驗證\n機器A\n機器B\n' > "$d/labels"
  : > "$d/parents"
  {
    printf '1\topen\towner-a\t[實作] 甲\t%s\n' "$GOODL,施工中,機器A"
    printf '2\tclosed\towner-a\t[實作] 乙\t%s\n' "$GOODL$extra"
    printf '3\topen\towner-a\t[SPEC] 丙\t改善,P2-一般\n'
  } > "$d/issues"
  setbody "$d" "$DEMO
$ANC"
}
cfg_labels() {  # 目錄
  printf '%s\n' '## 機器讀的欄位' '' '```text' '施工狀態記法: labels' \
    '只檢查誰開的票: owner-a' '```' > "$1/config.md"
}
run_main() {  # 夾具目錄 [env 指派…] ⇒ 輸出放 $T/out，退出碼放 RC
  local d="$1"; shift
  env PATH="$T/bin:$PATH" FX="$d" "$@" bash "$TTC_SCRIPT" example-org/app-one > "$T/out" 2>&1; RC=$?
}
has()  { grep -Fq -- "$1" "$T/out"; }
want_main() {  # 說明 條件（0＝成立）
  if [ "$2" = 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); printf '🔴 主體：%s\n' "$1"; sed 's/^/     /' "$T/out"; fi
}

# ── 設定讀不到：只檢查誰開的票改由 LABEL_OWNER 給；兩者都沒有 ⇒ 標籤格 UNKNOWN、不判紅 ──
FA="$T/fx-a"; mkfx "$FA" ",錯誤"   # 已關的票掛兩個類型：知道帳號就該紅（格 2）
run_main "$FA" LABEL_OWNER=owner-a
want_main '設定讀不到 ⇒ 印出讀不到設定的 ?? 行' "$(has '讀不到 docs/agents/github.md'; echo $?)"
want_main '設定讀不到、有 LABEL_OWNER ⇒ 標籤格照跑（格 2 紅、rc=1）' "$([ "$RC" = 1 ] && has '標籤 格2'; echo $?)"
run_main "$FA"
want_main '設定讀不到、也沒有 LABEL_OWNER ⇒ 印 UNKNOWN、rc=0、錨點照跑' "$([ "$RC" = 0 ] && has '不知道只檢查誰開的票' && ! has '格2' && has '錨點 SHA 連結 1 條'; echo $?)"
# ⬛ 對照：同一份夾具、有設定 ⇒ 帳號從設定讀到，已關的票格 2 紅
cp -R "$FA" "$T/fx-a2"; cfg_labels "$T/fx-a2"
run_main "$T/fx-a2"
want_main '⬛ 有設定 ⇒ 格 2 紅、rc=1' "$([ "$RC" = 1 ] && has '標籤 格2'; echo $?)"
want_main '⬛ 有設定 ⇒ 只檢查誰開的票從設定讀到（不必 LABEL_OWNER）' "$(! has '不知道只檢查誰開的票'; echo $?)"

# ── 格 9：施工票缺段、空段 ⇒ 紅；SPEC 不查 ──
FC="$T/fx-c"; mkfx "$FC"; cfg_labels "$FC"
setbody "$FC" "$ANC"
run_main "$FC"
want_main '缺「做完能展示什麼」⇒ 格 9 紅、rc=1' "$([ "$RC" = 1 ] && has '格9 沒有「做完能展示什麼」段'; echo $?)"
want_main 'SPEC 票不查格 9' "$(! grep -q "${H}3 .*格9" "$T/out"; echo $?)"
setbody "$FC" "## 做完能展示什麼

$ANC"
run_main "$FC"
want_main '空的「做完能展示什麼」⇒ 格 9 紅' "$([ "$RC" = 1 ] && has '格9 「做完能展示什麼」段是空的'; echo $?)"
setbody "$FC" "$DEMO
$ANC"
run_main "$FC"
want_main '⬛ 補上內容 ⇒ 全綠' "$([ "$RC" = 0 ] && ! has '格9'; echo $?)"

# ── 大輸出：開著的票內文清單遠大於管線緩衝時，查前面的票不可以讓整支死在半路 ──
cp -R "$FC" "$T/fx-d"
pad=$(b64 "$(head -c 3000 /dev/zero | tr '\0' 'x')")
i=100; while [ "$i" -lt 200 ]; do printf '%s\t%s\n' "$i" "$pad" >> "$T/fx-d/bodies"; i=$((i+1)); done
run_main "$T/fx-d"
want_main '大輸出 ⇒ 跑到最後一行總結、rc=0' "$([ "$RC" = 0 ] && has '施工票 1 張' && ! has 'Broken pipe'; echo $?)"

# ── 單張票內文問不到（內文那次 GraphQL 裡缺這張的列）⇒ 那張印 ??、照樣跑到總結、rc=0 ──
FE="$T/fx-e"; mkfx "$FE"; cfg_labels "$FE"
grep -v '^1	' "$FE/bodies" > "$FE/bodies.x"; mv "$FE/bodies.x" "$FE/bodies"
run_main "$FE"
want_main 'bodies 缺這張的列 ⇒ ?? 問不到內文、跑到總結、rc=0' "$([ "$RC" = 0 ] && grep -q "^?? .*${H}1 .*問不到這張票的內文" "$T/out" && grep -qx -- '--' "$T/out" && has '施工票 0 張'; echo $?)"
# ── 錨點那顆 SHA：422（repo 讀得到、SHA 不在）⇒ NG；404（沒權限讀的私有 repo 也是 404）⇒ ??，不判紅 ──
FQ="$T/fx-q"; mkfx "$FQ"; cfg_labels "$FQ"
echo 422 > "$FQ/commit-$SHA"
run_main "$FQ"
want_main 'SHA 422 ⇒ 不存在、rc=1' "$([ "$RC" = 1 ] && grep -q "^NG .*${H}1 .*SHA 在 example-org/app-one \*\*不存在\*\*" "$T/out"; echo $?)"
echo 404 > "$FQ/commit-$SHA"
run_main "$FQ"
want_main 'SHA 404 ⇒ ?? 問不到、不判不存在、rc=0' "$([ "$RC" = 0 ] && grep -q "^?? .*${H}1 .*問不到 example-org/app-one@" "$T/out" && ! grep -q '^NG' "$T/out"; echo $?)"
want_main 'SHA 404 ⇒ 總結的「問不到」算進這一處' "$(has '問不到 1 處'; echo $?)"

# ── 錨點「無」：錨點段明寫一行「- 無：<理由>」⇒ OK、印出理由；理由空 ⇒ NG；完全沒有錨點段照樣 NG ──
FW="$T/fx-w"; mkfx "$FW"; cfg_labels "$FW"
setbody "$FW" "$DEMO
## 錨點
- 無：這張只決定下一階段要開哪些票，不碰程式碼"
run_main "$FW"
want_main '錨點「- 無：理由」（全形冒號）⇒ OK、印理由、rc=0' "$([ "$RC" = 0 ] && has '錨點 無：這張只決定下一階段要開哪些票' && ! grep -q '^NG' "$T/out"; echo $?)"
setbody "$FW" "$DEMO
## 錨點
- 無: 查證票，只讀不改"
run_main "$FW"
want_main '錨點「- 無: 理由」（半形冒號）⇒ OK' "$([ "$RC" = 0 ] && has '錨點 無：查證票，只讀不改'; echo $?)"
setbody "$FW" "$DEMO
## 錨點
- 無："
run_main "$FW"
want_main '錨點「- 無：」沒理由 ⇒ NG、rc=1' "$([ "$RC" = 1 ] && has '錨點寫了「無」但沒寫理由'; echo $?)"
setbody "$FW" "$DEMO
- 無：沒有錨點段，只有這一行"
run_main "$FW"
want_main '⬛ 沒有錨點段、只有「- 無：」⇒ 照樣 NG' "$([ "$RC" = 1 ] && has '沒有「## 錨點」段'; echo $?)"

# 第 3 輪：「無」的理由只有空白（含全形）或只有 -、程式碼圍欄裡的「無」⇒ 不算有理由；「無」又放沒釘 SHA 的檔案連結 ⇒ NG
for v in '- 無：　' '- 無：-' '- 無： — '; do
  setbody "$FW" "$DEMO
## 錨點
${v}"
  run_main "$FW"
  want_main "錨點「${v}」不算有理由 ⇒ NG、rc=1" "$([ "$RC" = 1 ] && has '錨點寫了「無」但沒寫理由'; echo $?)"
done
setbody "$FW" "$DEMO
## 錨點
\`\`\`text
- 無：圍欄裡的不算
\`\`\`"
run_main "$FW"
want_main '程式碼圍欄裡的「- 無：」不算 ⇒ 錨點沒有 SHA 固定連結、rc=1' "$([ "$RC" = 1 ] && has '錨點沒有 SHA 固定連結' && ! has '錨點 無：'; echo $?)"
setbody "$FW" "$DEMO
## 錨點
- 無：只改設定
- https://github.com/example-org/app-one/blob/main/a.sh"
run_main "$FW"
want_main '「無」又放了沒釘 SHA 的檔案連結 ⇒ NG、rc=1' "$([ "$RC" = 1 ] && grep -q '^NG .*沒釘 SHA 的檔案連結.*blob/main/a.sh' "$T/out"; echo $?)"

# 第 3 輪：錨點連結的認法（www.、大寫 host、/blame/、/raw/、raw 網域都算、都逐顆驗存在）
FV="$T/fx-v"; mkfx "$FV"; cfg_labels "$FV"
for u in "https://www.github.com/example-org/app-one/blob/${SHA}/a.sh" "https://GitHub.com/example-org/app-one/blob/${SHA}/a.sh" \
         "https://github.com/example-org/app-one/blame/${SHA}/a.sh" "https://raw.githubusercontent.com/example-org/app-one/${SHA}/a.sh"; do
  setbody "$FV" "$DEMO
## 錨點
- ${u}"
  rm -f "$FV/commit-$SHA"; : > "$FAKE_LOG"
  run_main "$FV"
  want_main "錨點 ${u%/${SHA}/a.sh} ⇒ 驗存在 1 顆、沒有 !!、rc=0" "$([ "$RC" = 0 ] && has '驗存在 1 顆' && ! grep -q '^!!' "$T/out" && grep -q "commits/$SHA" "$FAKE_LOG"; echo $?)"
  echo 422 > "$FV/commit-$SHA"
  run_main "$FV"
  want_main "⬛ 同一條、SHA 422 ⇒ NG 不存在（真的有驗）" "$([ "$RC" = 1 ] && has '**不存在**'; echo $?)"
done
rm -f "$FV/commit-$SHA"
setbody "$FV" "$DEMO
$ANC
- https://github.com/example-org/app-one/blob/main/b.sh"
run_main "$FV"
want_main '有 SHA 連結又有沒釘 SHA 的檔案連結 ⇒ 印 !!、那條沒被驗' "$([ "$RC" = 0 ] && grep -q '^!! .*blob/main/b.sh' "$T/out"; echo $?)"

# ── 錨點 SHA 要剛好 40 碼：41 碼的十六進位串不是 SHA 固定連結 ──
FS="$T/fx-s"; mkfx "$FS"; cfg_labels "$FS"
setbody "$FS" "$DEMO
## 錨點
- [x](https://github.com/example-org/app-one/blob/${SHA}9/a.sh)"
run_main "$FS"
want_main '41 碼 ⇒ 錨點沒有 SHA 固定連結、rc=1' "$([ "$RC" = 1 ] && has '錨點沒有 SHA 固定連結'; echo $?)"

# ── 給了票號只查那幾張（標籤、格 6、格 9、錨點都只查那幾張） ──
FN="$T/fx-n"; mkfx "$FN"; cfg_labels "$FN"
printf '4\topen\towner-a\t[實作] 丁\t改善,P2-一般\n' >> "$FN/issues"     # 缺驗證 ⇒ 格 1 紅
printf '4\t\n' >> "$FN/bodies"   # 內文是空的 ⇒ 錨點、格 9 紅
run_nums() { local d="$1"; shift; env PATH="$T/bin:$PATH" FX="$d" bash "$TTC_SCRIPT" example-org/app-one "$@" > "$T/out" 2>&1; RC=$?; }
run_nums "$FN"
want_main '⬛ 不給票號 ⇒ 整個 repo 查、票 4 紅' "$([ "$RC" = 1 ] && grep -q "${H}4 .*格1" "$T/out"; echo $?)"
run_nums "$FN" 1
want_main '只給票 1 ⇒ 票 4 不查、rc=0' "$([ "$RC" = 0 ] && ! grep -q "${H}4 " "$T/out" && grep -q "${H}1 .*錨點 SHA 連結" "$T/out"; echo $?)"
run_nums "$FN" 4
want_main '只給票 4 ⇒ 格 1、錨點、格 9 都紅' "$([ "$RC" = 1 ] && grep -q "${H}4 .*格1" "$T/out" && grep -q "${H}4 .*錨點" "$T/out" && grep -q "${H}4 .*格9" "$T/out"; echo $?)"
run_nums "$FN" 1 9
want_main '給了不存在的票號 ⇒ ?? 找不到' "$(grep -q "^?? .*${H}9 .*找不到" "$T/out"; echo $?)"
run_nums "$FN" x1
want_main '票號不是數字 ⇒ rc=2' "$([ "$RC" = 2 ]; echo $?)"
run_nums "$FN" 004
want_main '票號帶前導零（004）⇒ 當成 4 查、不靜默略過' "$([ "$RC" = 1 ] && grep -q "${H}4 .*格1" "$T/out"; echo $?)"

# ── repo 設定的值去頭尾空白、帳號不分大小寫 ──
FG="$T/fx-g"; mkfx "$FG" ',錯誤'
printf '%s\n' '## 機器讀的欄位' '' '```text' '施工狀態記法: labels ' \
  '只檢查誰開的票: Owner-A ' '```' > "$FG/config.md"
run_main "$FG"
want_main '設定值帶空白、帳號大小寫不同 ⇒ 照查、已關的票格 2 紅' "$([ "$RC" = 1 ] && has '標籤 格2' && has '別人開的 0 張'; echo $?)"
# 有開著的票、卻沒有一張是設定的帳號開的 ⇒ 帳號多半設錯，印 ??（不是全過）
FH="$T/fx-h"; mkfx "$FH"
printf '%s\n' '## 機器讀的欄位' '' '```text' '施工狀態記法: labels' \
  '只檢查誰開的票: someone-else' '```' > "$FH/config.md"
run_main "$FH"
want_main '開著的票沒有一張是設定的帳號開的 ⇒ ??' "$(grep -q '^?? .*沒有一張是 someone-else 開的' "$T/out"; echo $?)"

# ── project 記法：狀態記在 Project 的 repo 也不讀 Project（狀態與機器標籤歸使用端的每日稽核） ──
# 用獨立的呼叫帳本、跑完立刻斷言：只在 mode=project 才會走的查詢，labels 記法的夾具量不到。
FP="$T/fx-p"; mkfx "$FP"
printf '%s\n' '## 機器讀的欄位' '' '```text' '施工狀態記法: project' 'Project 所在: example-org 1' \
  '只檢查誰開的票: owner-a' '```' > "$FP/config.md"
: > "$T/calls-p.log"
run_main "$FP" FAKE_LOG="$T/calls-p.log"
want_main 'project 記法 ⇒ 照常跑完、rc=0、標籤照查' "$([ "$RC" = 0 ] && grep -qx -- '--' "$T/out" && has '標籤 OK' && ! has '讀不到 docs/agents/github.md'; echo $?)"
want_main 'project 記法 ⇒ 不讀 Project' "$(! grep -Eq 'projectItems|projectV2|ProjectV2|project item' "$T/calls-p.log"; echo $?)"
want_main '⬛ project 記法的帳本有記到呼叫（上一條不是空帳本的假綠）' "$(grep -q 'contents/docs/agents/github.md' "$T/calls-p.log" && grep -q 'nodes{number body}' "$T/calls-p.log"; echo $?)"

# ── 開票自檢 workflow 範本：run: 主體裡不得出現 ${{ github.event.… }}（票的標題、內文等直接插進 shell＝指令注入） ──
# 事件的值一律經 env: 進來、在 run: 裡用 "$變數" 讀。只看 run: 區塊，env: 裡的 ${{ github.event.issue.number }} 是正確寫法。
TTC_WF="${TTC_DIR}/../skills/setup/references/ticket-check-workflow.yml"
# stdin＝workflow YAML ⇒ 印每個 run: 的內容（區塊 `run: |`／`run: >` 印到縮排退回為止；單行 `run: x` 印 x），每個 run: 前印一行 `@@run`。
wf_run_bodies() {
  awk '
    function ind(s) { match(s, /^ */); return RLENGTH }
    inb { if ($0 ~ /^[[:space:]]*$/ || ind($0) > k) { print; next } inb = 0 }
    /^[[:space:]]*(- )?run:[[:space:]]*[|>][-+]?[[:space:]]*$/ {
      k = ind($0); if ($0 ~ /^[[:space:]]*- /) k += 2
      print "@@run"; inb = 1; next }
    /^[[:space:]]*(- )?run:[[:space:]]*[^|>[:space:]]/ { print "@@run"; v = $0; sub(/^[^:]*run:[[:space:]]*/, "", v); print v }'
}
wf_runs=$(wf_run_bodies < "$TTC_WF")
want_main '⬛ 範本抽得到 run: 主體（有 @@run、含 ticket-check.sh、含最後的 exit）' "$(printf '%s\n' "$wf_runs" | grep -qx '@@run' && printf '%s\n' "$wf_runs" | grep -q 'ticket-check.sh' && printf '%s\n' "$wf_runs" | grep -q 'exit "\$rc"'; echo $?)"
want_main '⬛ 範本本身有 ${{ github.event.（在 env: 與 if:；量法認得出這個寫法）' "$(grep -Eq '\$\{\{[[:space:]]*github\.event\.' "$TTC_WF"; echo $?)"
if printf '%s\n' "$wf_runs" | grep -En '\$\{\{[[:space:]]*github\.event\.' > "$T/wf-hit"; then
  fail=$((fail+1)); printf '🔴 workflow 範本的 run: 裡有 ${{ github.event.…（改成 env: 進來、run: 裡用 "$變數"）：\n'; sed 's/^/     /' "$T/wf-hit"
else pass=$((pass+1)); fi

# ── 只讀：整支跑下來沒有任何寫入型呼叫 ──
want_main '假 gh 沒收到寫入型呼叫' "$(! grep -Eq -- '(^| )(-X|--method)( |$)|issue (edit|create|close|comment)|label (create|edit|delete)' "$FAKE_LOG"; echo $?)"
want_main '不逐票 issue view（內文已在那次 GraphQL 裡）' "$(! grep -q '^issue view' "$FAKE_LOG"; echo $?)"
want_main '不讀留言、PR、Project（只服務被移走的格）' "$(! grep -Eq 'comments|pulls|projectItems|closedByPullRequests' "$FAKE_LOG"; echo $?)"
want_main '假 gh 有被呼叫到（上一條不是空帳本的假綠）' "$([ "$(grep -c . "$FAKE_LOG")" -gt 20 ]; echo $?)"

printf '\n%d 過／%d 失敗（共 %d）\n' "$pass" "$fail" "$((pass+fail))"
[ "$fail" -eq 0 ]
