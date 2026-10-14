#!/usr/bin/env bash
# scripts/anchor-overlap.sh 的測試。gh 一律換成讀夾具的假程式（mktemp 目錄、放在 PATH 最前面），不碰任何真 repo。
# 夾具：body-<n>＝票內文（gh 的 --jq .body 之後）；blocked-<n>＝blocked_by（--jq 之後，一行 `owner/repo<TAB>號碼`）；
#       fail-body-<n>／fail-blocked-<n> 存在 ⇒ 那一顆回 HTTP 錯誤。
# 票號一律在執行時組出（H 變數），檔案裡不寫「井號接數字」。
#
# 用法：tests/test-anchor-overlap.sh
# 退出碼：0＝全過；1＝有案例失敗。
set -uo pipefail
TAO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 9
TAO_SCRIPT="${TAO_DIR}/../scripts/anchor-overlap.sh"
[ -f "${TAO_SCRIPT}" ] || { echo "FAIL 檔案不存在：${TAO_SCRIPT}"; exit 1; }

H='#'
pass=0; fail=0
T=$(mktemp -d) || exit 9
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
case " $* " in
  *" -X "*|*" --method "*|*" -f "*|*" -F "*) echo "假 gh：拒絕寫入型呼叫 $*" >&2; exit 97 ;;
esac
num() { local s="${1#repos/*/issues/}"; printf '%s' "${s%%[/?]*}"; }
case "$1 $2" in
  'api --paginate')
    case "$3" in
      repos/*/issues/*/dependencies/blocked_by*)
        n=$(num "$3")
        [ -f "$FX/fail-blocked-$n" ] && { echo 'gh: Server Error (HTTP 502)' >&2; exit 1; }
        [ -f "$FX/blocked-$n" ] && cat "$FX/blocked-$n"; exit 0 ;;
    esac ;;
  'api repos/'*)
    n=$(num "$2")
    [ -f "$FX/fail-body-$n" ] && { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
    cat "$FX/body-$n"; exit 0 ;;
esac
echo "假 gh：沒預期的呼叫 $*" >&2; exit 97
FAKE
chmod +x "$T/bin/gh"
export PATH="${T}/bin:${PATH}" FAKE_LOG="${T}/calls.log"; : > "$FAKE_LOG"
if [ "$(command -v gh)" = "$T/bin/gh" ]; then pass=$((pass+1)); else echo "🔴 拿到的不是假 gh：$(command -v gh)"; echo "停：不是假 gh 就不跑"; exit 1; fi

R=example-org/app-one
S1=0123456789abcdef0123456789abcdef01234567
S2=89abcdef0123456789abcdef0123456789abcdef
link() { printf -- '- [%s](https://github.com/%s/blob/%s/%s)\n' "$3" "$1" "$2" "$3"; }
# 票內文：$1＝錨點段內容
body() { printf '%s\n\n## 做完能展示什麼\n跑得出來。\n\n## 錨點\n%s\n\n## 待辦\n- 不在錨點段的連結不算：https://github.com/%s/blob/%s/other.sh\n' \
  "依 SPEC 設計" "$1" "$R" "$S1"; }

RC=0; OUT=''
run() {  # 夾具目錄 票號…
  local d="$1"; shift
  OUT=$(FX="$d" bash "$TAO_SCRIPT" "$R" "$@" 2>&1); RC=$?
}
has() { printf '%s\n' "$OUT" | grep -Fq -- "$1"; }
hasline() { printf '%s\n' "$OUT" | grep -Fxq -- "$1"; } # 整行相等（路徑後面多黏一個字也要分得出來）
ngs() { printf '%s\n' "$OUT" | { grep -c '^NG' || true; }; }
want() {  # 名稱 條件結果（0＝過）
  if [ "$2" = 0 ]; then pass=$((pass+1)); printf '   ✔ %s\n' "$1"
  else fail=$((fail+1)); printf '🔴 %s（rc=%s）\n%s\n' "$1" "$RC" "$OUT"; fi
}
endline() { [ "$(printf '%s\n' "$OUT" | tail -1)" = "END rc=$RC" ]; }

# ── 基本夾具：1、2 共用 a.sh（SHA 不同、帶 ?plain=1 與 #L 也算同一個檔）；3 只碰 c.sh ──
mk() {
  local d="$1"; mkdir -p "$d"
  body "$(link "$R" "$S1" a.sh; link "$R" "$S1" b.md)" > "$d/body-1"
  body "$(printf -- '- [a](https://github.com/%s/blob/%s/a.sh?plain=1#L3-L9)\n' "$R" "$S2")" > "$d/body-2"
  body "$(link "$R" "$S1" c.sh)" > "$d/body-3"
}

# 有交集、沒有擋 ⇒ NG
D="$T/ng"; mk "$D"
run "$D" 1 2 3
want '有交集無擋 ⇒ rc=1、印 NG 那一對與共用檔' "$([ "$RC" = 1 ] && has "NG ${H}1 ${H}2 example-org/app-one/a.sh" && [ "$(ngs)" = 1 ] && endline; echo $?)"
want '沒交集的那幾對不印 NG' "$(! has "${H}3"; echo $?)"

# 有交集、2 被 1 擋（2 的 blocked_by 有 1）⇒ OK
D="$T/fwd"; mk "$D"; printf '%s\t%s\n' "$R" 1 > "$D/blocked-2"
run "$D" 1 2 3
want '有交集、後一張被前一張擋 ⇒ rc=0、OK' "$([ "$RC" = 0 ] && has "OK ${H}1 ${H}2" && [ "$(ngs)" = 0 ] && endline; echo $?)"

# 有交集、1 被 2 擋（反方向）⇒ OK
D="$T/rev"; mk "$D"; printf '%s\t%s\n' "$R" 2 > "$D/blocked-1"
run "$D" 1 2 3
want '有交集、前一張被後一張擋（反方向）⇒ rc=0、OK' "$([ "$RC" = 0 ] && has "OK ${H}1 ${H}2" && [ "$(ngs)" = 0 ] && endline; echo $?)"

# ⬛ 對照：擋它的是別的 repo 的同號票 ⇒ 不算擋
D="$T/other"; mk "$D"; printf '%s\t%s\n' example-org/app-two 2 > "$D/blocked-1"
run "$D" 1 2
want '⬛ 別的 repo 的同號票擋 ⇒ 不算擋、rc=1' "$([ "$RC" = 1 ] && [ "$(ngs)" = 1 ] && endline; echo $?)"

# 別的 repo 的同路徑 ⇒ 不是同一個檔
D="$T/xrepo"; mkdir -p "$D"
body "$(link "$R" "$S1" a.sh)" > "$D/body-1"
body "$(link example-org/app-two "$S1" a.sh)" > "$D/body-2"
run "$D" 1 2
want '不同 repo 的同名路徑 ⇒ 不算交集、rc=0' "$([ "$RC" = 0 ] && [ "$(ngs)" = 0 ] && endline; echo $?)"

# 無交集 ⇒ OK，而且不必查 blocked_by
D="$T/none"; mkdir -p "$D"
body "$(link "$R" "$S1" a.sh)" > "$D/body-1"
body "$(link "$R" "$S1" b.sh)" > "$D/body-2"
: > "$FAKE_LOG"
run "$D" 1 2
want '無交集 ⇒ rc=0、沒有 NG' "$([ "$RC" = 0 ] && [ "$(ngs)" = 0 ] && endline; echo $?)"
want '無交集 ⇒ 沒去查 blocked_by' "$(! grep -q blocked_by "$FAKE_LOG"; echo $?)"

# 兩個共用檔 ⇒ 一檔一行
D="$T/two"; mkdir -p "$D"
body "$(link "$R" "$S1" a.sh; link "$R" "$S1" b.sh)" > "$D/body-1"
body "$(link "$R" "$S2" b.sh; link "$R" "$S2" a.sh)" > "$D/body-2"
run "$D" 1 2
want '共用兩個檔 ⇒ 兩行 NG' "$([ "$RC" = 1 ] && [ "$(ngs)" = 2 ] && endline; echo $?)"

# API 失敗（blocked_by 讀不到）⇒ UNKNOWN、rc=2
D="$T/apifail"; mk "$D"; : > "$D/fail-blocked-2"
run "$D" 1 2
want 'blocked_by 讀不到 ⇒ 印 UNKNOWN 且 rc=2（不是 0）' "$([ "$RC" = 2 ] && has "UNKNOWN ${H}1 ${H}2" && [ "$(ngs)" = 0 ] && endline; echo $?)"

# 內文讀不到 ⇒ UNKNOWN、rc=2
D="$T/bodyfail"; mk "$D"; : > "$D/fail-body-3"
run "$D" 1 3
want '內文讀不到 ⇒ UNKNOWN、rc=2' "$([ "$RC" = 2 ] && has "UNKNOWN ${H}1 ${H}3" && endline; echo $?)"

# 錨點段沒有連結（解析失敗）⇒ UNKNOWN、rc=2
D="$T/noanc"; mk "$D"; printf '%s\n\n## 錨點\n- 見上一張票\n' 'x' > "$D/body-3"
run "$D" 1 3
want '錨點段沒有 blob 連結 ⇒ UNKNOWN、rc=2' "$([ "$RC" = 2 ] && has 'blob/<40 碼 SHA>' && endline; echo $?)"

# 有 NG 又有一顆 API 失敗 ⇒ rc=2（NG 照印）
D="$T/mixed"; mk "$D"
body "$(link "$R" "$S1" c.sh)" > "$D/body-4"; : > "$D/fail-blocked-4"
run "$D" 1 2 3 4
want '有 NG 又有 API 失敗 ⇒ rc=2、NG 照印' "$([ "$RC" = 2 ] && [ "$(ngs)" = 1 ] && has "UNKNOWN ${H}3 ${H}4" && endline; echo $?)"

# 錨點連結後面黏著標點、反引號、句點 ⇒ 剝掉再比（三種寫法都是 a.sh）
D="$T/punct"; mkdir -p "$D"
body "$(printf -- '- `https://github.com/%s/blob/%s/a.sh`\n' "$R" "$S1")" > "$D/body-1"
body "$(printf -- '- 見 https://github.com/%s/blob/%s/a.sh，與上一張相同。\n' "$R" "$S2")" > "$D/body-2"
body "$(printf -- '- 見 https://github.com/%s/blob/%s/a.sh.\n' "$R" "$S1")" > "$D/body-3"
run "$D" 1 2 3
want '結尾標點／反引號／句點剝掉 ⇒ 三對都 NG a.sh' "$([ "$RC" = 1 ] && [ "$(ngs)" = 3 ] && has "NG ${H}1 ${H}2 example-org/app-one/a.sh" && ! has 'a.sh`' && ! has 'a.sh，' && ! has 'a.sh.' && endline; echo $?)"

# 百分比編碼 ⇒ 解回來再比
D="$T/pct"; mkdir -p "$D"
body "$(link "$R" "$S1" 'docs/審查.md')" > "$D/body-1"
body "$(printf -- '- [x](https://github.com/%s/blob/%s/docs/%%E5%%AF%%A9%%E6%%9F%%A5.md)\n' "$R" "$S2")" > "$D/body-2"
run "$D" 1 2
want '百分比編碼解回來 ⇒ 與原字同一個檔、NG' "$([ "$RC" = 1 ] && [ "$(ngs)" = 1 ] && has "NG ${H}1 ${H}2 example-org/app-one/docs/審查.md" && endline; echo $?)"

# 抽不出 SHA 的 github 連結 ⇒ UNKNOWN，不略過
D="$T/nosha"; mkdir -p "$D"
body "$(link "$R" "$S1" a.sh; printf -- '- https://github.com/%s/blob/main/b.sh\n' "$R")" > "$D/body-1"
body "$(link "$R" "$S1" c.sh)" > "$D/body-2"
run "$D" 1 2
want '錨點段有抽不出 SHA 的 github 連結 ⇒ UNKNOWN、rc=2' "$([ "$RC" = 2 ] && has "UNKNOWN ${H}1" && has "blob/main/b.sh" && endline; echo $?)"

# 非檔案的 github 連結（issue、pull、commit、留言）直接略過、不算 UNKNOWN；檔案連結照常比對
D="$T/nonfile"; mkdir -p "$D"
body "$(printf -- '- 依 https://github.com/%s/issues/%s#issuecomment-%s 的決定\n- https://github.com/%s/pull/%s\n- https://github.com/%s/commit/%s\n' "$R" 3 77 "$R" 4 "$R" "$S1"; link "$R" "$S1" a.sh)" > "$D/body-1"
body "$(link "$R" "$S2" a.sh)" > "$D/body-2"
run "$D" 1 2
want 'issue／pull／commit／留言連結略過 ⇒ 沒有 UNKNOWN、照常比對出 NG' "$([ "$RC" = 1 ] && ! printf '%s\n' "$OUT" | grep -q '^UNKNOWN' && [ "$(ngs)" = 1 ] && endline; echo $?)"

# tree/<sha>/<目錄> 與目錄下的檔算交集
D="$T/tree"; mkdir -p "$D"
body "$(printf -- '- [scripts](https://github.com/%s/tree/%s/scripts)\n' "$R" "$S1")" > "$D/body-1"
body "$(link "$R" "$S2" scripts/lib/x.sh)" > "$D/body-2"
body "$(link "$R" "$S2" scriptsx/y.sh)" > "$D/body-3"
run "$D" 1 2 3
want 'tree 目錄與目錄下的檔 ⇒ 交集、NG；同前綴的別的目錄不算' "$([ "$RC" = 1 ] && [ "$(ngs)" = 1 ] && has "NG ${H}1 ${H}2 example-org/app-one/scripts/lib/x.sh" && ! has "${H}3 " && endline; echo $?)"

# 結尾黏著的 Markdown 強調、全形引號／波浪號／刪節號、緊接的中文字 ⇒ 剝掉再比（各自與乾淨的 a.sh 比）
D="$T/trail"; mkdir -p "$D"
U="https://github.com/$R/blob/$S1/a.sh"
body "$(link "$R" "$S2" a.sh)" > "$D/body-1"
k=2
for v in "**${U}**" "「${U}”" "${U}～" "__${U}__" "${U}…" "${U}的說明" "${U}**。" "${U}（v1.2）"; do
  body "- 見 ${v}" > "$D/body-$k"
  run "$D" 1 "$k"
  want "結尾字元剝掉：${v#*a.sh} ⇒ NG a.sh" "$([ "$RC" = 1 ] && [ "$(ngs)" = 1 ] && hasline "NG ${H}1 ${H}${k} example-org/app-one/a.sh" && endline; echo $?)"
  k=$((k+1))
done
# ⬛ 對照：路徑本身有中文、而且中文後面還有副檔名 ⇒ 不砍
body "$(link "$R" "$S2" 'docs/v1.2版說明.md')" > "$D/body-20"
body "- 見 https://github.com/$R/blob/$S1/docs/v1.2版說明.md" > "$D/body-21"
run "$D" 20 21
want '⬛ 對照：路徑裡的中文不被當成結尾砍掉' "$([ "$RC" = 1 ] && [ "$(ngs)" = 1 ] && hasline "NG ${H}20 ${H}21 example-org/app-one/docs/v1.2版說明.md" && endline; echo $?)"

# 目錄連結（沒有副檔名可以砍）結尾黏著全形引號／刪節號 ⇒ 也要剝掉
for v in '”' '…'; do
  body "- 見「https://github.com/$R/tree/$S1/scripts${v}" > "$D/body-30"
  body "$(link "$R" "$S2" scripts/x.sh)" > "$D/body-31"
  run "$D" 30 31
  want "目錄連結結尾 ${v} 剝掉 ⇒ NG scripts/x.sh" "$([ "$RC" = 1 ] && hasline "NG ${H}30 ${H}31 example-org/app-one/scripts/x.sh" && endline; echo $?)"
done

# ⬛ 對照：檔名真的多一個「”」（百分比編碼寫出來）是另一個檔 ⇒ 不算交集（比對不吃語系的排序規則）
body "$(printf -- '- [x](https://github.com/%s/blob/%s/a.sh%%E2%%80%%9D)\n' "$R" "$S1")" > "$D/body-22"
run "$D" 1 22
want '⬛ 對照：a.sh 與 a.sh” 是不同檔 ⇒ rc=0、沒有 NG' "$([ "$RC" = 0 ] && [ "$(ngs)" = 0 ] && endline; echo $?)"

# 其他寫法的檔案連結：www、大寫 host、/blame/、/raw/、raw.githubusercontent.com ⇒ 照同一套 SHA 規則算錨點
D="$T/hosts"; mkdir -p "$D"
body "$(link "$R" "$S2" a.sh)" > "$D/body-1"
k=2
for v in "https://www.github.com/$R/blob/$S1/a.sh" "https://GitHub.com/$R/blob/$S1/a.sh" \
         "https://github.com/$R/blame/$S1/a.sh" "https://github.com/$R/raw/$S1/a.sh" \
         "https://raw.githubusercontent.com/$R/$S1/a.sh"; do
  body "- ${v}" > "$D/body-$k"
  run "$D" 1 "$k"
  want "檔案連結 ${v%%/$R*}…${v#*$R/} ⇒ NG a.sh" "$([ "$RC" = 1 ] && [ "$(ngs)" = 1 ] && hasline "NG ${H}1 ${H}${k} example-org/app-one/a.sh" && endline; echo $?)"
  k=$((k+1))
done
for v in "https://raw.githubusercontent.com/$R/refs/heads/main/a.sh" "https://www.github.com/$R/blob/main/a.sh"; do
  body "- ${v}" > "$D/body-$k"
  run "$D" 1 "$k"
  want "抽不出 SHA：${v} ⇒ UNKNOWN、rc=2" "$([ "$RC" = 2 ] && has "UNKNOWN ${H}${k} - " && has "${v}" && endline; echo $?)"
  k=$((k+1))
done

# 單票：讀不到、沒錨點段、錨點段沒連結 ⇒ 都不回 0
D="$T/single"; mkdir -p "$D"; : > "$D/fail-body-1"
printf '%s\n\n## 做什麼\nx\n' 'x' > "$D/body-2"
printf '%s\n\n## 錨點\n- 見上一張票\n' 'x' > "$D/body-3"
link "$R" "$S1" a.sh > "$D/anc4"; body "$(cat "$D/anc4")" > "$D/body-4"
for n in 1 2 3; do
  run "$D" "$n"
  want "單票 ${n}（讀不到／沒錨點／沒連結）⇒ UNKNOWN、rc=2" "$([ "$RC" = 2 ] && has "UNKNOWN ${H}${n}" && endline; echo $?)"
done
run "$D" 4
want '⬛ 對照：單票有錨點 ⇒ rc=0' "$([ "$RC" = 0 ] && endline; echo $?)"
run "$D" 1 1
want '同一張給兩次（去重後單票）讀不到 ⇒ rc=2' "$([ "$RC" = 2 ] && endline; echo $?)"

# 參數用錯 ⇒ rc=2、仍印結束行
run "$T/none"
want '只給 repo 沒給票號 ⇒ rc=2、END 行' "$([ "$RC" = 2 ] && endline; echo $?)"

want '假 gh 沒收到寫入型呼叫' "$(! grep -Eq -- '(^| )(-X|--method|-f|-F)( |$)' "$FAKE_LOG"; echo $?)"
want '假 gh 有被呼叫到（上一條不是空帳本的假綠）' "$([ "$(grep -c . "$FAKE_LOG")" -gt 5 ]; echo $?)"

printf '\n%d 過／%d 失敗（共 %d）\n' "$pass" "$fail" "$((pass+fail))"
[ "$fail" -eq 0 ]
