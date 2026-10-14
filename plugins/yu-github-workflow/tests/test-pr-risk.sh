#!/usr/bin/env bash
# scripts/pr-risk.sh 的測試。只對假 gh 跑（mktemp 目錄、放在 PATH 最前面），不碰任何真 repo。
# 夾具涵蓋：輕／中／重-自檢（有④、只有②、看不出②④⑤）／重-外審（通過、沒結論、不通過、先後兩則）、沒掛驗證標籤、
#           有無合併後步驟、整批混合、API 失敗、形狀不對、參數錯。
# 票的參照在執行時組出（不在檔內寫「repo 名＋井號＋數字」）。
set -uo pipefail
TPR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 9
PLUGIN="$(cd "${TPR_DIR}/.." && pwd -P)" || exit 9
S="${PLUGIN}/scripts/pr-risk.sh"
LIB="${PLUGIN}/scripts/lib/after-merge-step.sh"
for f in "${S}" "${LIB}"; do [ -f "${f}" ] || { echo "not ok 檔案不存在：${f}"; exit 1; }; done

T="$(mktemp -d)" || exit 9
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin" "${T}/fx"
# 假 gh：記下每一次呼叫；issue view <N> 回 FAKE_FX/<N>.json，沒有那個檔＝API 失敗。
cat > "${T}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_LOG}"
case "$1 $2" in
  "issue view")
    f="${FAKE_FX}/$3.json"
    [ -f "${f}" ] || { echo "HTTP 404: Not Found" >&2; exit 1; }
    cat "${f}" ;;
  *) echo "假 gh 不認得：$*" >&2; exit 3 ;;
esac
FAKE
chmod +x "${T}/bin/gh"
export PATH="${T}/bin:${PATH}" FAKE_LOG="${T}/log" FAKE_FX="${T}/fx"

PASS=0 FAILN=0
ok() { echo "ok $1"; PASS=$((PASS + 1)); }
ng() { echo "not ok $1"; FAILN=$((FAILN + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1（預期 [$3]，實際 [$2]）"; fi; }
ref() { printf '%s#%s' fake/repo "$1"; }
cnt() { grep -cxF -- "$2" "$1"; } # 整行相等的行數

# 夾具：mk <票號> <逗號分隔的標籤> <內文> [留言…]
mk() {
  python3 -I - "${T}/fx/$1.json" "$@" <<'PY'
import json, sys
out, n, labels, body = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
comments = [{"body": b, "url": "https://example.test/c/%d-%d" % (n, i)} for i, b in enumerate(sys.argv[5:])]
d = {"number": n, "url": "https://example.test/i/%d" % n,
     "labels": [{"name": x} for x in labels.split(",") if x], "body": body, "comments": comments}
json.dump(d, open(out, "w", encoding="utf-8"), ensure_ascii=False)
PY
}
SIG_OK='— 🔍 驗證｜機器A｜session abcdefgh｜分支 fix/x｜結果：通過'
mk 1 改善,輕驗證,P2-一般 $'## 做什麼\n改說明文字'
mk 2 改善,中驗證,P2-一般 $'## 做什麼\n改行為\n## 驗證\n`中驗證`'
mk 3 維護,重驗證-自檢,P1-高 $'## 驗證\n`重驗證-自檢`：④刪除舊資源'
mk 4 維護,重驗證-自檢,P1-高 $'## 驗證\n`重驗證-自檢`：②改 secret'
mk 5 資安,重驗證-外審,P1-高 $'## 驗證\n`重驗證-外審`：③權限' '施工回報' "$(printf '外審判讀：通過\n\n%s' "${SIG_OK}")" '後續閒聊'
mk 6 資安,重驗證-外審,P1-高 $'## 驗證\n`重驗證-外審`：①部署管線' '— 🔨 施工｜機器A｜session abcdefgh｜分支 fix/x'
mk 7 改善,中驗證,P2-一般 $'## 完成定義\nK1 通過；合併後由擁有者部署一次'
mk 8 改善,中驗證,P2-一般 $'## 完成定義\n部署後讀回一次'
mk 9 改善,P2-一般 '沒掛驗證標籤'
mk 10 改善,中驗證,P2-一般 $'## 驗證\n`中驗證`（引用第一節④的說明）'
mk 11 維護,重驗證-自檢,P1-高 $'## 驗證\n`重驗證-自檢`：要另外驗'
SIG_NG='— 🔍 驗證｜機器A｜session abcdefgh｜分支 fix/x｜結果：不通過'
mk 12 資安,重驗證-外審,P1-高 $'## 驗證\n`重驗證-外審`：③權限' "$(printf '外審判讀：F1 未修\n\n%s' "${SIG_NG}")"
mk 13 資安,重驗證-外審,P1-高 $'## 驗證\n`重驗證-外審`：③權限' "${SIG_NG}" "${SIG_OK}"
mk 14 資安,重驗證-外審,P1-高 $'## 驗證\n`重驗證-外審`：③權限' "${SIG_OK}" "${SIG_NG}"
mk 15 維護,重驗證-自檢,P1-高 $'## 驗證\n`重驗證-自檢`：⑤寄出名冊'
printf '[]' > "${T}/fx/98.json"

run() { : > "${FAKE_LOG}"; bash "${S}" "$@" > "${T}/out" 2> "${T}/err"; echo $?; }

if [ "$(command -v gh)" = "${T}/bin/gh" ]; then ok "腳本拿到的是假 gh"
else ng "腳本拿到的是假 gh（$(command -v gh)）"; echo "停：不是假 gh 就不跑"; exit 1; fi

# ── 單張 ──
rc=$(run fake/repo 1)
check "輕：rc=0" "${rc}" 0
check "輕：雙向門" "$(cnt "${T}/out" '**門：** 雙向門')" 1
check "輕：Closes" "$(cnt "${T}/out" "Closes $(ref 1)")" 1
check "輕：沒有外審段" "$(grep -c 外審 "${T}/out")" 0

rc=$(run fake/repo 2)
check "中：rc=0" "${rc}" 0
check "中：雙向門" "$(cnt "${T}/out" '**門：** 雙向門')" 1
check "中：沒有外審段" "$(grep -c 外審 "${T}/out")" 0
check "中：影響範圍佔位" "$(cnt "${T}/out" '**影響範圍：** <一個詞，開 PR 的人填>')" 1

rc=$(run fake/repo 3)
check "重-自檢有④：rc=0" "${rc}" 0
check "重-自檢有④：單向門" "$(cnt "${T}/out" '**門：** 單向門')" 1
check "重-自檢有④：那一列寫單向門" "$(cnt "${T}/out" "| $(ref 3) | 重驗證-自檢 | 單向門（內文標了④不可逆） |")" 1

rc=$(run fake/repo 4)
check "重-自檢只有②：rc=0" "${rc}" 0
check "重-自檢只有②：雙向門" "$(cnt "${T}/out" '**門：** 雙向門')" 1
rc=$(run fake/repo 15)
check "重-自檢只有⑤：rc=0、雙向門" "${rc} $(cnt "${T}/out" '**門：** 雙向門')" "0 1"

rc=$(run fake/repo 11)
check "重-自檢看不出②④⑤：rc=3" "${rc}" 3
check "重-自檢看不出②④⑤：門未定並寫原因" "$(cnt "${T}/out" '**門：** 未定（重驗證-自檢的票看不出②／④／⑤）')" 1
check "重-自檢看不出②④⑤：那一列寫未定" "$(cnt "${T}/out" "| $(ref 11) | 重驗證-自檢 | 未定（內文看不出②／④／⑤） |")" 1
check "重-自檢看不出②④⑤：連票段照印" "$(cnt "${T}/out" "Closes $(ref 11)")" 1

rc=$(run fake/repo 10)
check "中驗證內文提到④：仍是雙向門（④只看重驗證的票）" "$(cnt "${T}/out" '**門：** 雙向門')" 1

rc=$(run fake/repo 5)
check "重-外審有結論：rc=0" "${rc}" 0
check "重-外審有結論：列出結論留言的連結" "$(cnt "${T}/out" "- $(ref 5)：https://example.test/c/5-1")" 1
check "重-外審有結論：門照④判（沒④＝雙向門）" "$(cnt "${T}/out" '**門：** 雙向門')" 1

rc=$(run fake/repo 6)
check "重-外審沒結論：rc=3" "${rc}" 3
check "重-外審沒結論：照實印出找不到" "$(grep -c "^- $(ref 6)：找不到驗證者的結論留言" "${T}/out")" 1
check "重-外審沒結論：門未定並寫原因" "$(cnt "${T}/out" '**門：** 未定（重驗證-外審的票沒有通過的外審結論）')" 1
check "重-外審沒結論：連票段照印" "$(cnt "${T}/out" "Closes $(ref 6)")" 1

rc=$(run fake/repo 12)
check "重-外審結論不通過：rc=3" "${rc}" 3
check "重-外審結論不通過：門未定" "$(cnt "${T}/out" '**門：** 未定（重驗證-外審的票沒有通過的外審結論）')" 1
check "重-外審結論不通過：列出那則留言並標不通過" "$(grep -c "^- $(ref 12)：結論不是通過（https://example.test/c/12-0）" "${T}/out")" 1

rc=$(run fake/repo 13)
check "重-外審先不通過後通過：rc=0、取最後一則" "${rc} $(cnt "${T}/out" "- $(ref 13)：https://example.test/c/13-1")" "0 1"
rc=$(run fake/repo 14)
check "重-外審先通過後不通過：rc=3" "${rc}" 3

rc=$(run fake/repo 9)
check "沒掛驗證標籤：rc=3" "${rc}" 3
check "沒掛驗證標籤：門未定" "$(cnt "${T}/out" '**門：** 未定（有票沒掛驗證標籤）')" 1
check "沒掛驗證標籤：連票段照印" "$(cnt "${T}/out" "Closes $(ref 9)")" 1

rc=$(run fake/repo 3 9)
check "單向門＋沒掛標籤：未定蓋過單向門、rc=3" "${rc} $(cnt "${T}/out" '**門：** 未定（有票沒掛驗證標籤）')" "3 1"
rc=$(run fake/repo 9 11 6)
check "三種未定同時出現：原因全列" "$(cnt "${T}/out" '**門：** 未定（有票沒掛驗證標籤；重驗證-自檢的票看不出②／④／⑤；重驗證-外審的票沒有通過的外審結論）')" 1

# ── 合併後步驟 ──
rc=$(run fake/repo 7)
check "合併後有步驟：Refs" "$(cnt "${T}/out" "Refs $(ref 7)")" 1
check "合併後有步驟：沒有 Closes" "$(grep -c '^Closes ' "${T}/out")" 0
rc=$(run fake/repo 8)
check "部署後有步驟：Refs" "$(cnt "${T}/out" "Refs $(ref 8)")" 1

# ── 整批混合 ──
rc=$(run fake/repo 2 3 7 5)
check "整批：rc=0" "${rc}" 0
check "整批：有一張④＝整批單向門" "$(cnt "${T}/out" '**門：** 單向門')" 1
check "整批：連票四行照票號順序" "$(sed -n '/^## 連票$/,$p' "${T}/out" | grep -E '^(Closes|Refs) ' | tr '\n' ' ')" \
  "Closes $(ref 2) Closes $(ref 3) Refs $(ref 7) Closes $(ref 5) "
check "整批：外審段只列外審那張" "$(sed -n '/^\*\*外審結論：\*\*$/,/^$/p' "${T}/out" | grep -c '^- ')" 1

# ── 讀不到：rc=2、不印半份 ──
rc=$(run fake/repo 2 99 3)
check "API 失敗：rc=2" "${rc}" 2
check "API 失敗：stdout 什麼都沒印" "$(wc -c < "${T}/out" | tr -d ' ')" 0
check "API 失敗：stderr 講出哪一張" "$(grep -c "讀不到 fake/repo 的票 99" "${T}/err")" 1
rc=$(run fake/repo 2 98)
check "形狀不對：rc=2" "${rc}" 2
check "形狀不對：stdout 什麼都沒印" "$(wc -c < "${T}/out" | tr -d ' ')" 0

# ── 參數 ──
check "沒給票號：rc=64" "$(run fake/repo)" 64
check "票號不是數字：rc=64" "$(run fake/repo 1x)" 64
check "repo 不是 owner/repo：rc=64" "$(run fakerepo 1)" 64

# ── 只讀：只呼叫 issue view ──
run fake/repo 2 3 5 > /dev/null
check "只讀：每一次呼叫都是 issue view" "$(grep -vc '^issue view ' "${FAKE_LOG}")" 0

# ── 合併後步驟的判法只有一份 ──
check "pr-risk.sh 沒有自己的合併後 pattern" "$(grep -cF '(合併|部署)後' "${S}")" 0
check "pr-risk.sh 讀共用的判法" "$(grep -cF '. "${PRR_DIR}/lib/after-merge-step.sh"' "${S}")" 1

echo "通過 ${PASS}，失敗 ${FAILN}"
[ "${FAILN}" -eq 0 ]
