#!/usr/bin/env bash
# scripts/ticket-check.sh 的測試。只對假 gh 跑（mktemp 目錄、放在 PATH 最前面），不碰任何真 repo。
#   上半：source 腳本取函式，逐格測判準（每格一張「從好票故意做壞一處」的陽性對照，好票先要是綠的）。
#   下半：整支對假 gh 跑主體——設定讀不到（UNKNOWN 不判紅，⬛ 對照：同一份夾具有設定 ⇒ 紅）、
#         整合 PR 的 Closes 與 Refs、格 9。
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

# ══ 標籤格 1～4、8 ══
M='機器A,機器B'
L48='重驗證-外審,維護,P2-一般,機器A'
P48='In Progress'
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
# state title labels [pstatus] [mode] [machines] ⇒ 不該有任何違規。mode 預設 project、machines 預設 M。
want_clean() {
  local out; out=$(label_problems "$1" "$2" "$3" "${4:-}" "${5:-project}" "${6-$M}")
  if [ -z "$out" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf '🔴 該綠卻紅（%s｜%s｜%s）：%s\n' "$1" "$3" "${5:-project}" "$out"; fi
}
want_ng() {  # 格號 state title labels [pstatus] [mode] [machines] ⇒ 必須出現「格N」
  local out; out=$(label_problems "$2" "$3" "$4" "${5:-}" "${6:-project}" "${7-$M}")
  case "$out" in
    *"格$1"*) pass=$((pass+1)); printf '   ✔ 陽性對照 格%s 紅：%s\n' "$1" "$(printf '%s' "$out" | tr '\n' '／')" ;;
    *) fail=$((fail+1)); printf '🔴 格%s 該紅卻沒紅（%s｜%s｜%s）：%s\n' "$1" "$2" "$4" "${6:-project}" "$out" ;;
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
want_clean open   "$T48" "$L48" "$P48"
want_clean closed "$T50" "$L50"
want_clean open   "$T41" "$L41" 'Todo'          # SPEC 沒掛驗證不判紅
want_clean open   '協作指揮台：票序' ''           # 協調類什麼都不必掛
want_clean OPEN   "$T48" "$L48" "$P48"          # 大寫的 state
want_clean open   "$T48" '重驗證-外審,維護,P2-一般' 'Todo'
want_clean closed '[實作] 舊票' '重驗證-外審'    # 已關的舊票不查格 1

# ── 格 1：必掛 ──
want_ng 1 open "$T48" "${L48/重驗證-外審,/}" "$P48"
want_ng 1 open "$T48" "${L48/維護,/}" "$P48"
want_ng 1 open "$T48" "${L48/P2-一般,/}" "$P48"
want_ng 1 open "$T41" "${L41/,P2-一般/}" 'Todo'
want_ng 1 open '[決定] 搬進組織後誰能寫' '改善,P2-一般' 'Todo'
want_ng 1 open "$T50" "${L50/中驗證,/}" 'Todo'
want_ng 1 open "$T48" "${L48/重驗證-外審/待驗證}" "$P48"   # 待驗證是狀態不是驗證分級（逐字比對）
want_ng 1 open "$T48" "${L48/維護/類型:維護}" "$P48"       # 帶前綴的舊名不算數

# ── 格 2：單選 ──
want_ng 2 open   "$T48" "$L48,錯誤" "$P48"
want_ng 2 open   "$T48" "$L48,P0-阻斷" "$P48"
want_ng 2 open   "$T48" "$L48,中驗證" "$P48"
want_ng 2 closed "$T50" "$L50,改善"
want_clean open  "$T48" "$L48,等擁有者" "$P48"   # 等待擁有者的標籤不是狀態組

# ── 格 3：找得到人 ──
L0='重驗證-外審,維護,P2-一般'
want_clean open "$T48" "$L48" '待驗證'
want_clean open "$T48" "$L0"  '待合併'
want_clean open "$T48" "$L0,等擁有者" 'Todo'
want_clean open "$T48" "$L0"  'Todo'
want_clean open "$T48" "$L0"  '?'                 # 問不到：不判（呼叫端印 UNKNOWN）
want_ng 3 open "$T48" "$L0" 'In Progress'
want_ng 3 open "$T48" "$L0" '待驗證'
# labels 記法：狀態看標籤
want_ng 3 open "$T48" "$L0,施工中" '' labels
want_ng 3 open "$T48" "$L0,待驗證" '' labels
want_clean open "$T48" "$L0,施工中,機器B" '' labels
want_clean open "$T48" "$L0" '' labels             # 沒開工
want_clean open "$T48" "$L0" 'In Progress' labels  # labels 記法不看 Status
# 不用機器標籤、或設定讀不到 ⇒ 格 3 不判
want_clean open "$T48" "$L0,施工中" '' labels ''
want_clean open "$T48" "$L0,施工中" '' '?' '?'
want_clean open "$T48" "$L0" 'In Progress' project '?'

# ── 格 8：狀態只有一處（project 記法） ──
want_ng 8 open "$T48" "$L0"  'NONE'                # 狀態記在 Project 的 repo：票不在 Project ⇒ 紅
want_clean open "$T48" "$L0"  'NONE' labels        # labels 記法：不在 Project＝正常
want_clean open "$T48" "$L48" "$P48"
want_clean open "$T48" "$L0"  '?'                  # 問不到 ≠ 不在 Project
want_clean open '協作指揮台：票序' '' 'NONE'         # 協調類不要求在 Project
want_clean closed "$T50" "$L50" 'NONE'             # 已關的票不查格 8
want_ng 8 open "$T48" "$L48,施工中" "$P48"         # 狀態標籤與 Status 並存
want_ng 8 open "$T48" "$L0,待驗證"  'NONE'
want_ng 8 open '協作指揮台：票序' '施工中' 'Todo'    # 協調類也不該掛
want_clean closed "$T50" "$L50,施工中"             # 已關的票不查格 8
want_clean open "$T48" "$L48,施工中" "$P48" labels # labels 記法：狀態標籤是正常的
want_clean open "$T48" "$L0,施工中" 'NONE' '?' '?' # 設定讀不到 ⇒ 不判（呼叫端印 UNKNOWN）

# ── 格 4：關票清乾淨 ──
want_ng 4 closed "$T50" "$L50,機器A"
want_ng 4 closed "$T50" "$L50,機器B"
want_clean open  "$T50" "$L50,機器A" "$P48"        # 同樣的標籤、票開著 ⇒ 綠
want_clean closed "$T50" "$L50,機器A" '' project '?'   # 設定讀不到 ⇒ 不判
want_clean closed "$T50" "$L50,機器A" '' project ''    # 這個 repo 不用機器標籤 ⇒ 不判
want_clean closed "$T50" "$L50,機器" ''                # 名字不對＝不是機器標籤（逐字比對）

# ══ 格 5：不驗自己的票（新舊兩種署名） ══
want_v5() {  # 期望（OK/NG/UNKNOWN） 署名行…（一個參數＝一則留言的最後一行）
  local want="$1" out; shift
  out=$(printf '%s\n' "$@" | self_verify_verdict)
  case "$out" in
    "$want "*) pass=$((pass+1)); [ "$want" = OK ] || printf '   ✔ 格5 %s\n' "$out" ;;
    *) fail=$((fail+1)); printf '🔴 格5 要 %s、得 %s（%s）\n' "$want" "$out" "$*" ;;
  esac
}
# 舊署名：角色｜機器｜軌號｜執行者｜分支
B='— 🔨 施工軌｜機器A｜軌3｜session PqrsTuvw｜分支 docs/50-names'
C='— 📌 指揮台軌｜機器A｜軌3｜session PqrsTuvw'
want_v5 OK "$B" "$C" '一般留言的最後一行'         # 指揮台同 session 不算驗證
want_v5 OK "$B" '— 🔍 驗證軌｜機器B｜軌4｜session KlmnOpqr｜重跑結果：通過'
want_v5 OK ''
want_v5 NG "$B" '— 🔍 驗證軌｜機器A｜軌3｜session PqrsTuvw｜重跑結果：通過'
want_v5 NG "$B" '— 🔍 驗證軌｜機器A｜軌3｜session PqrsTuvwXyzXyzXyzXyzXyz｜重跑結果：通過'   # 驗證寫全碼
want_v5 NG '— 🔨 施工軌｜機器A｜軌3｜session PqrsTuvwXyzXyzXyzXyzXyz｜分支 x' '— 🔍 驗證軌｜機器A｜軌3｜session PqrsTuvw｜重跑結果：通過'   # 施工寫全碼
want_v5 NG "$B" '— 🔨 施工軌｜機器B｜軌5｜session AAAAAAAA｜分支 x' '— 🔍 驗證軌｜機器B｜軌5｜session AAAAAAAA｜重跑結果：通過'   # 換手後的施工者自驗
AB='— 🔨 施工軌｜機器A｜軌3｜agent-ghijklmn@PqrsTuvw｜分支 x'
want_v5 OK "$AB" '— 🔍 驗證軌｜機器A｜軌3｜agent-opqrstuv@PqrsTuvw｜重跑結果：通過'   # 同對話兩個子代理 ⇒ 獨立
want_v5 NG "$AB" '— 🔍 驗證軌｜機器A｜軌3｜agent-ghijklmn@PqrsTuvw｜重跑結果：通過'   # 同一個子代理
want_v5 NG "$B"  '— 🔍 驗證軌｜機器A｜軌3｜agent-opqrstuv@PqrsTuvw｜重跑結果：通過'   # 對話施工、自己派的子代理驗
want_v5 OK "$AB" '— 🔍 驗證軌｜機器A｜軌3｜session PqrsTuvw｜重跑結果：通過'          # 派工的對話驗子代理的工作
want_v5 OK "$B"  '— 🔍 驗證軌｜機器B｜軌4｜agent-wxyzwxyz@KlmnOpqr｜重跑結果：通過'   # 別的對話派的子代理
want_v5 UNKNOWN "$B" '— 🔍 驗證軌｜機器B｜軌4｜重跑結果：通過'   # 驗證署名沒有執行者
want_v5 UNKNOWN '— 🔍 驗證軌｜機器B｜軌4｜session KlmnOpqr｜重跑結果：通過'   # 沒有施工署名可比
# 新署名：角色｜機器｜執行者｜分支（labels.md 第三節）
NB='— 🔨 施工｜機器A｜session PqrsTuvw｜分支 fix/12-null-check'
want_v5 OK "$NB" '— 🔍 驗證｜機器B｜session KlmnOpqr｜分支 fix/12-null-check｜結果：通過'
want_v5 NG "$NB" '— 🔍 驗證｜機器B｜session PqrsTuvw｜分支 fix/12-null-check｜結果：通過'          # 同一個執行者
want_v5 NG "$NB" '— 🔍 驗證｜機器A｜驗證子代理 agent-opqrstuv@PqrsTuvw｜分支 x｜結果：通過'          # 自己派的子代理驗
NAB='— 🔨 施工｜機器A｜施工子代理 agent-ghijklmn@PqrsTuvw｜分支 x'
want_v5 OK "$NAB" '— 🔍 驗證｜機器A｜驗證子代理 agent-opqrstuv@PqrsTuvw｜分支 x｜結果：通過'       # 同對話兩個子代理 ⇒ 獨立
want_v5 NG "$NAB" '— 🔍 驗證｜機器A｜驗證子代理 agent-ghijklmn@PqrsTuvw｜分支 x｜結果：通過'
want_v5 UNKNOWN "$NB" '— 🔍 驗證｜機器B｜分支 x｜結果：通過'     # 新署名缺執行者欄
# 新舊混用：舊施工署名＋新驗證署名
want_v5 NG "$B" '— 🔍 驗證｜機器B｜session PqrsTuvw｜分支 x｜結果：通過'
want_v5 OK "$B" '— 🔍 驗證｜機器B｜session KlmnOpqr｜分支 x｜結果：通過'
# 欄位對位：執行者字樣只出現在別的欄（新署名的分支欄）不算執行者
want_v5 UNKNOWN "$NB" '— 🔍 驗證｜機器B｜—｜分支 session PqrsTuvw｜結果：通過'

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

# ══ 格 7：合併後有步驟的票，會不會被 PR 自動關 ══
want_c7() {
  local out; out=$(closes_problem "$2" "$3")
  case "$1:$out" in
    clean:)   pass=$((pass+1)) ;;
    NG:格7*)  pass=$((pass+1)) ;;
    *) fail=$((fail+1)); printf '🔴 格7 要 %s（PR「%s」）：得「%s」\n' "$1" "$3" "$out" ;;
  esac
}
B19='## 完成定義
K0～K3 重跑通過；擁有者合併部署；K4 部署後補算貼回本票後關票。'
B13='- [ ] 合併部署後：在說明票留言'
BPLAIN='## 完成定義
K1、K2 重跑通過；擁有者合併。'
want_c7 NG    "$B19"    "${H}24"
want_c7 NG    "$B13"    "${H}25,${H}26"
want_c7 clean "$B19"    ''
want_c7 clean "$BPLAIN" "${H}9"
want_c7 clean ''        "${H}9"

# 整合 PR 內文的關閉關鍵字
want_refs() {  # 期望（空白分隔的票號） PR 內文
  local got; got=$(pr_closing_refs "$2" example-org/app-one | tr '\n' ' ' | sed 's/ $//')
  if [ "$got" = "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf '🔴 整合 PR 關閉關鍵字：要「%s」、得「%s」（%s）\n' "$1" "$got" "$2"; fi
}
want_refs '5'     "$(printf 'Closes %s5' "$H")"
want_refs '5 7'   "$(printf '整合三張票\n- Closes %s5\n- fixes %s7\n- Refs %s9' "$H" "$H" "$H")"   # Refs 不算
want_refs '5'     "$(printf 'Resolved: %s5' "$H")"
want_refs ''      "$(printf 'Refs %s5' "$H")"
want_refs ''      "$(printf '`Closes %s5`' "$H")"                       # code span 裡 GitHub 不認
want_refs '5'     "$(printf 'closes example-org/app-one%s5' "$H")"      # 指名本 repo
want_refs ''      "$(printf 'closes example-org/other%s5' "$H")"        # 別的 repo
want_refs ''      "$(printf 'encloses %s5' "$H")"                       # 字中間不算關鍵字

# ══ 設定區塊解析 ══
CFG_DOC="$(printf '%s\n' '# GitHub 工作流設定' '' '## 機器讀的欄位' '' '```text' \
  '票開在哪個 repo: 本 repo' '施工狀態記法: project' 'Project 所在: example-org 3' \
  '機器標籤名: 機器A,機器B' '只檢查誰開的票: owner-a' '特殊禁忌: 無' '```' '' '## 部署線' '' '```text' '施工狀態記法: labels' '```')"
blk=$(printf '%s\n' "$CFG_DOC" | cfg_block)
want_cfg() {  # 欄位 期望
  local got; got=$(cfg_get "$blk" "$1")
  if [ "$got" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf '🔴 設定 %s：要「%s」、得「%s」\n' "$1" "$2" "$got"; fi
}
want_cfg 施工狀態記法 project                 # 只讀「機器讀的欄位」底下第一個 text 區塊
want_cfg 'Project 所在' 'example-org 3'
want_cfg 機器標籤名 '機器A,機器B'
want_cfg 只檢查誰開的票 owner-a
want_cfg 等待擁有者的標籤名 ''                   # 沒有這個欄位 ⇒ 空

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
      *projectItems*)                      fx pstatus ;;
      *closedByPullRequestsReferences*)    fx closers ;;
      *) echo "假 gh：沒預期的 graphql $*" >&2; exit 97 ;;
    esac ;;
  'api --paginate')
    case "$3" in
      repos/*/labels*)        fx labels ;;
      repos/*/pulls*)         fx pulls ;;
      repos/*/issues/*/comments*) n="${3#repos/*/issues/}"; n="${n%%/*}"; fx "comments-$n" ;;
      repos/*/issues*)        fx issues ;;
      *) echo "假 gh：沒預期的呼叫 $*" >&2; exit 97 ;;
    esac ;;
  'api repos/'*)
    case "$2" in
      */commits/*) exit 0 ;;
      *) cat "$FX/default_branch" ;;
    esac ;;
  'issue view') fx "view-$3" ;;
  *) echo "假 gh：沒預期的呼叫 $*" >&2; exit 97 ;;
esac
FAKE
chmod +x "$T/bin/gh"
export FAKE_LOG="$T/calls.log"; : > "$FAKE_LOG"

if [ "$(PATH="$T/bin:$PATH" command -v gh)" = "$T/bin/gh" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "🔴 拿到的不是假 gh"; fi

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
SHA=0123456789abcdef0123456789abcdef01234567
ANC="## 錨點
- [x](https://github.com/example-org/app-one/blob/${SHA}/a.sh)"
DEMO='## 做完能展示什麼
跑出來的清單。'
GOODL='改善,P2-一般,中驗證'
# 一個 repo 的夾具：$1＝目錄、$2＝已關的票 2 多掛的標籤；票 1 開著（施工中）、票 2 已關、票 3 SPEC。
mkfx() {
  local d="$1" extra="${2:-}"; mkdir -p "$d"
  printf '錯誤\n文件\n改善\n施工中\n待驗證\n機器A\n機器B\n' > "$d/labels"
  : > "$d/parents"
  printf 'main' > "$d/default_branch"
  : > "$d/pulls"
  {
    printf '1\topen\towner-a\t[實作] 甲\t%s\n' "$GOODL,施工中,機器A"
    printf '2\tclosed\towner-a\t[實作] 乙\t%s\n' "$GOODL$extra"
    printf '3\topen\towner-a\t[SPEC] 丙\t改善,P2-一般\n'
  } > "$d/issues"
  printf '%s\n \n%s\n%s\n' '[實作] 甲' "$DEMO" "$ANC" > "$d/view-1"
  printf '%s\n \n%s\n' '[SPEC] 丙' '## 背景' > "$d/view-3"
  printf '1\t\t%s\n3\t\t%s\n' "$(b64 "$DEMO")" "$(b64 '## 背景')" > "$d/closers"
}
cfg_labels() {  # 目錄 機器標籤名
  printf '%s\n' '## 機器讀的欄位' '' '```text' '施工狀態記法: labels' 'Project 所在: 不適用' \
    "機器標籤名: $2" '只檢查誰開的票: owner-a' '```' > "$1/config.md"
}
run_main() {  # 夾具目錄 [env 指派…] ⇒ 輸出放 $T/out，退出碼放 RC
  local d="$1"; shift
  env PATH="$T/bin:$PATH" FX="$d" "$@" bash "$TTC_SCRIPT" example-org/app-one > "$T/out" 2>&1; RC=$?
}
has()  { grep -Fq -- "$1" "$T/out"; }
want_main() {  # 說明 條件（0＝成立）
  if [ "$2" = 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); printf '🔴 主體：%s\n' "$1"; sed 's/^/     /' "$T/out"; fi
}

# ── 設定讀不到：格 3、4、8 印 UNKNOWN、不判紅；其他格照跑 ──
FA="$T/fx-a"; mkfx "$FA" ",機器A"   # 已關還掛機器標籤：有設定就該紅
run_main "$FA" LABEL_OWNER=owner-a
want_main '設定讀不到 ⇒ rc=0（UNKNOWN 不判紅）' "$([ "$RC" = 0 ]; echo $?)"
want_main '設定讀不到 ⇒ 印出讀不到設定的 ?? 行' "$(has '讀不到 docs/agents/github.md'; echo $?)"
want_main '設定讀不到 ⇒ 印出格 3、4、8 不判' "$(has '格 3、4、8 不判'; echo $?)"
want_main '設定讀不到 ⇒ 沒有格 4 的 NG' "$(! has '格4'; echo $?)"
want_main '設定讀不到 ⇒ 標籤格照跑（開著的票 OK）' "$(has '標籤 OK（一般票）'; echo $?)"
# ⬛ 對照：同一份夾具、有設定（labels 記法、機器標籤 機器A,機器B）⇒ 已關的票掛著機器A 要紅
cp -R "$FA" "$T/fx-a2"; cfg_labels "$T/fx-a2" '機器A,機器B'
run_main "$T/fx-a2"
want_main '⬛ 有設定 ⇒ 格 4 紅、rc=1' "$([ "$RC" = 1 ] && has '標籤 格4'; echo $?)"
want_main '⬛ 有設定 ⇒ 只檢查誰開的票從設定讀到（不必 LABEL_OWNER）' "$(! has '不知道只檢查誰開的票'; echo $?)"
want_main '⬛ 有設定 ⇒ 不印格 3、4、8 不判' "$(! has '格 3、4、8 不判'; echo $?)"
# 設定讀不到、也沒有 LABEL_OWNER ⇒ 標籤格整個 UNKNOWN，錨點照跑
run_main "$FA"
want_main '不知道誰開的票 ⇒ 印 UNKNOWN、rc=0、錨點照跑' "$([ "$RC" = 0 ] && has '不知道只檢查誰開的票' && has '錨點 SHA 連結 1 條'; echo $?)"

# ── 整合 PR：Closes 了有合併後步驟的票 ⇒ 格 7；Refs 不算；目標不是預設分支不算 ──
FB="$T/fx-b"; mkfx "$FB"; cfg_labels "$FB" '機器A,機器B'
AFTER="$DEMO
## 完成定義
合併後由擁有者補跑一次。"
printf '%s\n \n%s\n%s\n' '[實作] 甲' "$AFTER" "$ANC" > "$FB/view-1"
printf '1\t\t%s\n3\t\t%s\n' "$(b64 "$AFTER")" "$(b64 '## 背景')" > "$FB/closers"   # 原生來源刻意是空的
printf '40\tmain\t%s\n' "$(b64 "$(printf '整合分支合併\n- Closes %s1\n- Refs %s3' "$H" "$H")")" > "$FB/pulls"
run_main "$FB"
want_main '整合 PR 寫 Closes ⇒ 格 7 紅' "$([ "$RC" = 1 ] && has "格7" && has "PR ${H}40"; echo $?)"
printf '40\tmain\t%s\n' "$(b64 "$(printf '整合分支合併\n- Refs %s1' "$H")")" > "$FB/pulls"
run_main "$FB"
want_main '⬛ 同一張票、整合 PR 改寫 Refs ⇒ 格 7 不紅' "$([ "$RC" = 0 ] && ! has "格7"; echo $?)"
printf '41\tinteg/9-x\t%s\n' "$(b64 "$(printf 'Closes %s1' "$H")")" > "$FB/pulls"
run_main "$FB"
want_main '目標不是預設分支的 PR 寫 Closes ⇒ 格 7 不紅' "$([ "$RC" = 0 ] && ! has "格7"; echo $?)"
: > "$FB/pulls"; printf '1\t%s\t%s\n3\t\t%s\n' "${H}42" "$(b64 "$AFTER")" "$(b64 '## 背景')" > "$FB/closers"
run_main "$FB"
want_main '原生來源（closedByPullRequestsReferences）照舊認得' "$([ "$RC" = 1 ] && has "PR ${H}42"; echo $?)"

# ── 格 9：施工票缺段、空段 ⇒ 紅；SPEC 不查 ──
FC="$T/fx-c"; mkfx "$FC"; cfg_labels "$FC" '機器A,機器B'
printf '%s\n \n%s\n' '[實作] 甲' "$ANC" > "$FC/view-1"
run_main "$FC"
want_main '缺「做完能展示什麼」⇒ 格 9 紅、rc=1' "$([ "$RC" = 1 ] && has '格9 沒有「做完能展示什麼」段'; echo $?)"
want_main 'SPEC 票不查格 9' "$(! grep -q "${H}3 .*格9" "$T/out"; echo $?)"
printf '%s\n \n%s\n\n%s\n' '[實作] 甲' '## 做完能展示什麼' "$ANC" > "$FC/view-1"
run_main "$FC"
want_main '空的「做完能展示什麼」⇒ 格 9 紅' "$([ "$RC" = 1 ] && has '格9 「做完能展示什麼」段是空的'; echo $?)"
printf '%s\n \n%s\n%s\n' '[實作] 甲' "$DEMO" "$ANC" > "$FC/view-1"
run_main "$FC"
want_main '⬛ 補上內容 ⇒ 全綠' "$([ "$RC" = 0 ] && ! has '格9'; echo $?)"

# ── 只讀：整支跑下來沒有任何寫入型呼叫 ──
want_main '假 gh 沒收到寫入型呼叫' "$(! grep -Eq -- '(^| )(-X|--method)( |$)|issue (edit|create|close|comment)|label (create|edit|delete)' "$FAKE_LOG"; echo $?)"
want_main '假 gh 有被呼叫到（上一條不是空帳本的假綠）' "$([ "$(grep -c . "$FAKE_LOG")" -gt 20 ]; echo $?)"

printf '\n%d 過／%d 失敗（共 %d）\n' "$pass" "$fail" "$((pass+fail))"
[ "$fail" -eq 0 ]
