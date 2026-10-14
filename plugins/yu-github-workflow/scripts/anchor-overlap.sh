#!/usr/bin/env bash
# 錨點檔案重疊檢查：一批施工票裡，兩張票的錨點指到同一個檔、而兩者之間沒有任何方向的 blocked-by ⇒ NG。
# 碰同一批檔的票要嘛合成一張，要嘛用 blocked-by 排出先後；兩樣都沒有，就會有兩軌同時改同一個檔。
#
# 用法：anchor-overlap.sh <owner/repo> <票號> [<票號> ...]
#
# 怎麼判：
#   1. 讀每張票內文的「## 錨點」段（`##` 開頭那行裡有「錨點」，到下一個 `## ` 為止），
#      抽出 `https://github.com/<owner>/<repo>/blob/<40 碼 SHA>/<路徑>`（檔）與 `.../tree/<40 碼 SHA>/<目錄>`（目錄）連結。
#      同一個檔＝同一個 owner/repo（不分大小寫）＋同一個路徑；SHA 不同也算同一個檔，`?plain=1` 與 `#L…` 不算進路徑。
#      連結結尾黏著的全形／半形標點、反引號、句點剝掉；百分比編碼解回來再比。
#      錨點段裡指向檔案（`/blob/`、`/tree/`）卻抽不出 40 碼 SHA 的 github 連結（例如 `blob/main/…`）⇒ 那張票印 `UNKNOWN`，不略過；
#      不指向檔案的 github 連結（issue、pull、commit、留言）不是錨點，直接略過。
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

# 錨點段 → 一行一個 `owner/repo/路徑`（owner/repo 小寫；目錄結尾加 `/`）；抽不出 SHA 的 github 連結寫進 argv[1]。
AOV_PY=''
IFS= read -r -d '' AOV_PY <<'PY' || true
import re, sys, urllib.parse
bad = open(sys.argv[1], "w", encoding="utf-8")
PUNCT = "，。、；：！？（）「」『』【】《》〈〉"
url_re = re.compile(r"https?://github\.com/[^\s()\[\]<>\"'`" + PUNCT + "]+")
out = []
for u in url_re.findall(sys.stdin.buffer.read().decode("utf-8", "replace")):
    u = u.rstrip(".,;:!?")
    path = urllib.parse.unquote(re.split(r"[?#]", u.split("github.com/", 1)[1], 1)[0])
    if not re.match(r"[^/]+/[^/]+/(blob|tree)/", path):
        continue  # 不是指向檔案的連結（issue、pull、commit、留言）：不是錨點，略過
    m = re.match(r"([^/]+)/([^/]+)/(blob|tree)/([0-9a-f]{40})(?:/(.*))?$", path)
    rest = ((m.group(5) or "").rstrip("/")) if m else ""
    if not m or (m.group(3) == "blob" and not rest):
        bad.write(u + "\n"); continue
    key = (m.group(1) + "/" + m.group(2)).lower() + "/" + rest
    if m.group(3) == "tree":
        key = key.rstrip("/") + "/"
    out.append(key + "\n")
sys.stdout.buffer.write("".join(out).encode("utf-8"))
PY

# ── 每張票的錨點檔清單：$AOV_TMP/files-<n>（排序去重）；讀不到或解析失敗 ⇒ $AOV_TMP/why-<n> 寫原因；
#    抽不出 SHA 的連結 ⇒ $AOV_TMP/bad-<n>（照樣比對其他連結，但這張票印 UNKNOWN）──
for n in "${nums[@]}"; do
  arc=0
  body=$(gh api "repos/$repo/issues/$n" --jq .body 2>"$errf") || arc=$?
  if [ "$arc" != 0 ]; then
    printf '讀不到內文（%s）' "$(tr '\n' ' ' <"$errf")" > "$AOV_TMP/why-$n"; continue
  fi
  anc=$(printf '%s\n' "$body" | tr -d '\r' | awk '/^## /{f=0} /^## .*錨點/{f=1;next} f')
  if [ -z "$anc" ]; then
    printf '沒有「## 錨點」段' > "$AOV_TMP/why-$n"; continue
  fi
  if ! printf '%s\n' "$anc" | python3 -I -c "$AOV_PY" "$AOV_TMP/bad-$n" > "$AOV_TMP/raw-$n" 2>"$errf"; then
    printf '錨點段解析失敗（%s）' "$(tr '\n' ' ' <"$errf")" > "$AOV_TMP/why-$n"; continue
  fi
  LC_ALL=C sort -u "$AOV_TMP/raw-$n" > "$AOV_TMP/files-$n"
  if [ ! -s "$AOV_TMP/files-$n" ] && [ ! -s "$AOV_TMP/bad-$n" ]; then
    printf '錨點段沒有 blob/<40 碼 SHA>/<路徑> 連結' > "$AOV_TMP/why-$n"
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
  awk 'NR == FNR { a[++na] = $0; next }
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
