#!/usr/bin/env bash
# 錨點檔案重疊檢查：一批施工票裡，兩張票的錨點指到同一個檔、而兩者之間沒有任何方向的 blocked-by ⇒ NG。
# 碰同一批檔的票要嘛合成一張，要嘛用 blocked-by 排出先後；兩樣都沒有，就會有兩軌同時改同一個檔。
#
# 用法：anchor-overlap.sh <owner/repo> <票號> [<票號> ...]
#
# 怎麼判：
#   1. 讀每張票內文的「## 錨點」段（`##` 開頭那行裡有「錨點」，到下一個 `## ` 為止），
#      抽出 `https://github.com/<owner>/<repo>/blob/<40 碼 SHA>/<路徑>`（檔）與 `.../tree/<40 碼 SHA>/<目錄>`（目錄）連結。
#      `/blame/`、`/raw/` 與 `https://raw.githubusercontent.com/<owner>/<repo>/<40 碼 SHA>/<路徑>` 也算檔；
#      host 不分大小寫、可帶 `www.`。
#      同一個檔＝同一個 owner/repo（不分大小寫）＋同一個路徑；SHA 不同也算同一個檔，`?plain=1` 與 `#L…` 不算進路徑。
#      連結結尾黏著的全形／半形標點、引號、波浪號、刪節號、反引號、`|`、句點、`:行號`、Markdown 強調剝掉
#      （結尾的 `_` 只在連結前面有 `_` 強調開頭時才剝，檔名 `foo_` 不剝）；
#      最後一段後面直接接中文（`a.md的說明`、`README的說明`）⇒ 砍掉中文
#      （中文後面還有副檔名的，例如 `v1.2版說明.md`，當成檔名本身，不砍）。百分比編碼解回來再比；比對用位元組、不吃語系排序。
#      錨點段裡指向檔案（上面幾種）卻抽不出 40 碼 SHA 的連結（例如 `blob/main/…`、`refs/heads/main/…`）⇒ 那張票印 `UNKNOWN`，不略過；
#      不指向檔案的 github 連結（issue、pull、commit、留言）不是錨點，直接略過。
#      沒有任何檔案連結、明寫一行「- 無：<理由>」的票（只在 repo 外操作、只做決定）⇒ 錨點檔清單為空，不與任何票重疊；
#      理由空白（含全形空白、只有 `-`）、或那行在程式碼圍欄裡 ⇒ 照樣 UNKNOWN。
#      上面這些判法（連結怎麼認、結尾怎麼剝、「無」怎麼認）只寫在 lib/anchor-links.sh，與 ticket-check.sh 共用；細則見那一檔。
#   2. 兩兩比對交集：同一個檔，或一邊是目錄、另一邊是目錄底下的檔（或子目錄）。沒有交集 ⇒ 不印。
#   3. 有交集的一對，查兩個方向的 `issues/<n>/dependencies/blocked_by`（只看直接的擋，不追鏈）：
#      任一方向有擋 ⇒ `OK`；兩個方向都沒有 ⇒ 每個共用檔印一行 `NG <a> <b> <檔>`。
#
# 三態與退出碼：
#   0＝沒有 NG、也沒有讀不到的；1＝有 NG；2＝有任何一顆讀不到或解析失敗（就算同時有 NG 也回 2）。
#   讀不到印 `UNKNOWN <a> <b> <原因>`（只跟單一張票有關的印 `UNKNOWN <a> - <原因>`）——讀不到不可以讀成「沒有重疊」。
#   只給一張票（或去重後只剩一張）時，讀不到、沒錨點段、錨點段沒連結也照樣 UNKNOWN、回 2。參數用錯也回 2。
#   最後一行固定印 `END rc=<退出碼>`：中途崩潰就印不出來，靠它分辨「判定」與「崩潰」。
#
# 只讀：只呼叫 GitHub 的讀取 API，不改任何票、標籤或設定。
set -uo pipefail

finish() { echo "END rc=$1"; exit "$1"; }

if [ $# -lt 2 ] || [[ ! "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "UNKNOWN - - 參數用錯。用法：$0 <owner/repo> <票號> [<票號> ...]"
  finish 2
fi
repo="$1"; shift
nums=()
for a in "$@"; do
  a="${a#\#}"
  [[ "$a" =~ ^[0-9]+$ ]] || { echo "UNKNOWN - - 票號不是數字：$a"; finish 2; }
  case " ${nums[*]-} " in *" $a "*) ;; *) nums+=("$a") ;; esac
done

AOV_TMP=$(mktemp -d) || { echo "UNKNOWN - - 建不了暫存目錄"; finish 2; }
trap 'rm -rf "$AOV_TMP"' EXIT
errf="$AOV_TMP/err"

# 錨點段怎麼讀、哪些連結算、「- 無：<理由>」怎麼認：lib/anchor-links.sh（與 ticket-check.sh 共用同一份判法）。
AOV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || { echo "UNKNOWN - - 找不到腳本目錄"; finish 2; }
# shellcheck source=lib/anchor-links.sh
. "${AOV_DIR}/lib/anchor-links.sh" || { echo "UNKNOWN - - 讀不到 lib/anchor-links.sh"; finish 2; }

# ── 每張票的錨點檔清單：$AOV_TMP/files-<n>（排序去重）；讀不到或解析失敗 ⇒ $AOV_TMP/why-<n> 寫原因；
#    抽不出 SHA 的連結 ⇒ $AOV_TMP/bad-<n>（照樣比對其他連結，但這張票印 UNKNOWN）──
for n in "${nums[@]}"; do
  arc=0
  body=$(gh api "repos/$repo/issues/$n" --jq .body 2>"$errf") || arc=$?
  if [ "$arc" != 0 ]; then
    printf '讀不到內文（%s）' "$(tr '\n' ' ' <"$errf")" > "$AOV_TMP/why-$n"; continue
  fi
  anc=$(printf '%s\n' "$body" | anchor_section)
  if [ -z "$anc" ]; then
    printf '沒有「## 錨點」段' > "$AOV_TMP/why-$n"; continue
  fi
  if ! printf '%s\n' "$anc" | anchor_parse > "$AOV_TMP/raw-$n" 2>"$errf"; then
    printf '錨點段解析失敗（%s）' "$(tr '\n' ' ' <"$errf")" > "$AOV_TMP/why-$n"; continue
  fi
  awk -F'\t' '$1 == "F" { print $6 }' "$AOV_TMP/raw-$n" | LC_ALL=C sort -u > "$AOV_TMP/files-$n"
  awk -F'\t' '$1 == "B" { print $2 }' "$AOV_TMP/raw-$n" > "$AOV_TMP/bad-$n"
  none=$(awk -F'\t' '$1 == "N" { print $2 }' "$AOV_TMP/raw-$n")
  # 沒有任何檔案連結：明寫「- 無：<理由>」＝錨點檔清單為空（不與任何票重疊）；理由空白或沒寫「無」⇒ 讀不到
  if [ ! -s "$AOV_TMP/files-$n" ] && [ ! -s "$AOV_TMP/bad-$n" ]; then
    case "$none" in
      R) ;;
      EMPTY) printf '錨點寫了「無」但沒寫理由（寫成「- 無：<理由>」）' > "$AOV_TMP/why-$n" ;;
      *) printf '錨點段沒有 blob/<40 碼 SHA>/<路徑> 連結，也沒有「- 無：<理由>」' > "$AOV_TMP/why-$n" ;;
    esac
  fi
done

# ── 每張票直接被誰擋：$AOV_TMP/blk-<n>（一行一個 `owner/repo<TAB>號碼`，owner/repo 小寫）；讀不到 ⇒ 回 1 ──
blocked_by() {
  local n="$1" out arc=0
  [ -f "$AOV_TMP/blk-$n" ] && return 0
  [ -f "$AOV_TMP/blkerr-$n" ] && return 1
  out=$(gh api --paginate "repos/$repo/issues/$n/dependencies/blocked_by?per_page=100" \
          --jq '.[]|[(.repository_url|sub("^.*/repos/";"")|ascii_downcase),(.number|tostring)]|@tsv' 2>"$errf") || arc=$?
  if [ "$arc" != 0 ]; then
    printf '讀不到 %s 的 blocked_by（%s）' "$n" "$(tr '\n' ' ' <"$errf")" > "$AOV_TMP/blkerr-$n"; return 1
  fi
  printf '%s\n' "$out" > "$AOV_TMP/blk-$n"
}
# $1 是否直接被 $2 擋（同一個 repo）
is_blocked() {
  awk -F'\t' -v r="$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')" -v m="$2" \
    '$1 == r && $2 == m { f = 1 } END { exit !f }' "$AOV_TMP/blk-$1"
}

# 兩份清單的交集：同一個檔，或一邊是目錄（結尾 `/`）、另一邊在它底下；印較深的那一個
shared_of() {
  LC_ALL=C awk 'NR == FNR { a[++na] = $0; next }
       { for (k = 1; k <= na; k++) { x = a[k]; y = $0
           if (x == y) print x
           else if (substr(x, length(x)) == "/" && index(y, x) == 1) print y
           else if (substr(y, length(y)) == "/" && index(x, y) == 1) print x } }' "$1" "$2" | LC_ALL=C sort -u
}

ng=0; unk=0; pairs=0; overl=0
cnt=${#nums[@]}
# 只跟一張票有關的 UNKNOWN：抽不出 SHA 的連結（每張票印一次）；只有一張票時，讀不到或沒錨點也在這裡印
for n in "${nums[@]}"; do
  if [ -s "$AOV_TMP/bad-$n" ]; then
    while IFS= read -r u; do printf 'UNKNOWN #%s - 錨點段有抽不出 40 碼 SHA 的檔案連結：%s\n' "$n" "$u"; done < "$AOV_TMP/bad-$n"
    unk=$((unk+1))
  fi
  if [ "$cnt" -eq 1 ] && [ -f "$AOV_TMP/why-$n" ]; then
    printf 'UNKNOWN #%s - %s\n' "$n" "$(cat "$AOV_TMP/why-$n")"; unk=$((unk+1))
  fi
done
i=0
while [ "$i" -lt "$cnt" ]; do
  j=$((i+1))
  while [ "$j" -lt "$cnt" ]; do
    a="${nums[$i]}"; b="${nums[$j]}"; pairs=$((pairs+1))
    if [ -f "$AOV_TMP/why-$a" ] || [ -f "$AOV_TMP/why-$b" ]; then
      for x in "$a" "$b"; do
        [ -f "$AOV_TMP/why-$x" ] && printf 'UNKNOWN #%s #%s %s：%s\n' "$a" "$b" "$x" "$(cat "$AOV_TMP/why-$x")"
      done
      unk=$((unk+1)); j=$((j+1)); continue
    fi
    shared=$(shared_of "$AOV_TMP/files-$a" "$AOV_TMP/files-$b")
    if [ -z "$shared" ]; then j=$((j+1)); continue; fi
    overl=$((overl+1))
    bad=0
    for x in "$a" "$b"; do
      blocked_by "$x" || { printf 'UNKNOWN #%s #%s %s\n' "$a" "$b" "$(cat "$AOV_TMP/blkerr-$x")"; bad=1; }
    done
    if [ "$bad" = 1 ]; then unk=$((unk+1)); j=$((j+1)); continue; fi
    if is_blocked "$a" "$b"; then
      printf 'OK #%s #%s 共用 %s 個檔，#%s 被 #%s 擋\n' "$a" "$b" "$(printf '%s\n' "$shared" | grep -c .)" "$a" "$b"
    elif is_blocked "$b" "$a"; then
      printf 'OK #%s #%s 共用 %s 個檔，#%s 被 #%s 擋\n' "$a" "$b" "$(printf '%s\n' "$shared" | grep -c .)" "$b" "$a"
    else
      while IFS= read -r f; do printf 'NG #%s #%s %s\n' "$a" "$b" "$f"; done <<<"$shared"
      ng=$((ng+1))
    fi
    j=$((j+1))
  done
  i=$((i+1))
done

echo "-- ${cnt} 張票、${pairs} 對：有共用檔 ${overl} 對，其中沒有擋 ${ng} 對；UNKNOWN ${unk} 筆"
if [ "$unk" -gt 0 ]; then
  echo "有讀不到的：這是沒量到，不是沒問題。"
  finish 2
fi
[ "$ng" -eq 0 ] && finish 0
finish 1
