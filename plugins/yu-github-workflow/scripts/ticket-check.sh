#!/usr/bin/env bash
# 開票自檢：施工票的錨點（SHA 固定連結、那顆 SHA 真的存在）、標籤格 1、2、6、「做完能展示什麼」（格 9）。
# 每格查什麼、判紅條件、三態意思：references/ticket-check.md。
#
# 用法：ticket-check.sh <owner/repo> [票號 ...]
#   給了票號只查那幾張（標籤、格 6、格 9、錨點都只查那幾張）；不給查整個 repo。
# 退出碼：0＝全過；1＝有 NG；2＝參數用錯。正常跑完一定印 `--` 開頭的總結；沒有總結＝沒跑完（不是 NG）。
#
# repo 特有的值讀目標 repo 的 docs/agents/github.md（「機器讀的欄位」區塊，見 setup 的 repo 設定範本）：
#   只檢查誰開的票（值去頭尾空白；帳號比對不分大小寫）。
#   環境變數 LABEL_OWNER 覆寫它；兩者都沒有 ⇒ 標籤格整個印 UNKNOWN（錨點與格 9 照跑）。
#
# 三態：OK＝問到了而且對；NG＝問到了而且不對；UNKNOWN（`??` 開頭）＝沒問到（離線、沒權限、限流、設定讀不到）。
#   UNKNOWN 不算 NG——否則離線時這支永遠紅，永遠紅的燈等於沒有燈。但它一定會被印出來。
#
# 只讀：這支只呼叫 GitHub 的讀取 API，不改任何票、標籤或設定。
set -euo pipefail
# ── 錨點段的判法（只在這裡判一次） ─────────────────────────────
#   錨點段在哪、哪些連結算錨點、連結怎麼剝結尾、「- 無：<理由>」怎麼認、理由空白怎麼算。
#
# anchor_section：stdin＝票內文 ⇒ 印「## 錨點」段（`##` 開頭那行裡有「錨點」，到下一個 `## ` 為止；去掉 CR）。
# anchor_parse：stdin＝錨點段 ⇒ 一行一筆，TAB 分隔：
#   F<TAB>種類<TAB>owner<TAB>repo<TAB>SHA<TAB>比對鍵   釘了 40 碼 SHA 的檔案連結（種類＝blob／tree／blame／raw）；
#                                                       比對鍵＝小寫 owner/repo＋`/`＋路徑（tree 結尾加 `/`）
#   B<TAB>連結                                         指向檔案、卻抽不出 40 碼 SHA 的連結（`blob/main/…`、`refs/heads/main/…`）
#   N<TAB>R<TAB>理由／N<TAB>EMPTY                       第一行「- 無：<理由>」（程式碼圍欄外）；理由空白 ⇒ EMPTY
#   解析失敗 ⇒ 非 0 退出。
#
# 哪些連結算錨點：`https://github.com/<owner>/<repo>/(blob|tree|blame|raw)/<40 碼 SHA>/<路徑>`，
#   與 `https://raw.githubusercontent.com/<owner>/<repo>/<40 碼 SHA>/<路徑>`（補上 blob 照同一套規則）；
#   host 不分大小寫、可帶 `www.`。不指向檔案的 github 連結（issue、pull、commit、留言）不是錨點，略過。
#   SHA 不同也算同一個檔，`?plain=1` 與 `#L…` 不算進路徑；百分比編碼解回來。
# 結尾怎麼剝：
#   - 全形／半形標點、引號、波浪號、刪節號、`|`、反引號不進連結；結尾的 `.,;:!?~` 剝掉。
#   - 結尾的 `*`（Markdown 強調）剝掉；結尾的 `_` 只在同一行、連結前面有 `_` 強調的開頭（`__…__`、`_見 …_`）時才剝——
#     檔名本身結尾的 `_`（`foo_`）不剝。
#   - 結尾的 `:行號`（`a.md:10`、`a.md:10-12`）剝掉。
#   - 最後一段後面直接接中文、而中文後面沒有再一個「.」⇒ 中文是正文，砍掉：
#     `a.md的說明` ⇒ `a.md`；`README的說明`（沒有副檔名、前面全是 ASCII）⇒ `README`；
#     `v1.2版說明.md`（中文後面還有副檔名）、`審查證據`（整段是中文）是檔名本身，不砍。
# 「無」怎麼認：錨點段裡一行 `- 無：<理由>`（`-`／`*`／`+` 清單符號；半形或全形冒號），程式碼圍欄裡的不算。
#   理由去掉頭尾空白（含全形空白）後是空的、或只剩 `-`、`—`、`*`、`_`、`~`、`.`、`。`、`…`、`、`、`，`、`:`、`：` 這類符號 ⇒ EMPTY。
# 用 python3 -I（不讀 cwd 的模組）；比對用位元組、不吃語系排序（呼叫端 sort 一律 LC_ALL=C）。

anchor_section() { tr -d '\r' | awk '/^## /{f=0} /^## .*錨點/{f=1;next} f'; }

ANCHOR_PY=''
IFS= read -r -d '' ANCHOR_PY <<'PY' || true
import re, sys, urllib.parse
PUNCT = "，。、；：！？（）「」『』【】《》〈〉“”‘’～…｜"
TRAIL = ".,;:!?~"
url_re = re.compile(r"https?://(?:www\.)?(github\.com|raw\.githubusercontent\.com)/([^\s()\[\]<>\"'`|" + PUNCT + "]+)", re.I)
# 最後一段後面直接接中文、而中文後面沒有再一個「.」⇒ 中文是正文，不是檔名
cjk_tail = re.compile(r"^(.*\.[A-Za-z0-9]+)[^\x00-\x7f][^./]*$")
cjk_tail_noext = re.compile(r"^([\x21-\x7e]*[A-Za-z0-9_-])[^\x00-\x7f][^./]*$")
line_no = re.compile(r":[0-9]+(?:[-:][0-9]+)*$")
none_re = re.compile(r"^[ \t　]*[-*+][ \t　]+無[ \t　]*[:：](.*)$")
none_empty = re.compile(r"[\s\-‐‑–—―*_~.。…・、，,:：;；=]*")
# 這一行在連結前面有 `_` 強調的開頭（行首、空白或括號後面的 `_`，或緊貼連結的 `_`）⇒ 結尾的 `_` 才是強調、可以剝
under_open = re.compile(r"(?:^|[\s(（「『【])_+|_+$")
fence_open = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")

text = sys.stdin.buffer.read().decode("utf-8", "replace")
out = []

# 「無」：程式碼圍欄外的第一行。反引號圍欄的資訊字串不能含反引號（CommonMark）；關上要同一種字元、長度不少於開頭。
fence = ""
none = None
for line in text.split("\n"):
    if fence:
        m = re.match(r"^[ \t]*(`{3,}|~{3,})[ \t]*$", line)
        if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
            fence = ""
        continue
    m = fence_open.match(line)
    if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
        fence = m.group(1); continue
    if none is None:
        n = none_re.match(line)
        if n:
            v = n.group(1).strip()
            none = "EMPTY" if none_empty.fullmatch(v) else "R\t" + v.replace("\t", " ")

for mo in url_re.finditer(text):
    host, tail = mo.group(1).lower(), mo.group(2)
    before = text[text.rfind("\n", 0, mo.start()) + 1:mo.start()]
    strip = TRAIL + "*" + ("_" if under_open.search(before) else "")
    while True:
        t = line_no.sub("", tail.rstrip(strip))
        if t == tail:
            break
        tail = t
    head, sep, last = re.split(r"[?#]", tail, maxsplit=1)[0].rpartition("/")
    c = cjk_tail.match(last) or cjk_tail_noext.match(last)
    if c:
        tail = head + sep + c.group(1)
    u = mo.group(0)[:mo.start(2) - mo.start(0)] + tail
    path = urllib.parse.unquote(re.split(r"[?#]", tail, maxsplit=1)[0])
    if host == "raw.githubusercontent.com":
        path = re.sub(r"^([^/]+/[^/]+)/", r"\1/blob/", path)  # raw 網域沒有 blob 這一段：補上，照同一套規則
    if not re.match(r"[^/]+/[^/]+/(blob|tree|blame|raw)/", path):
        continue  # 不是指向檔案的連結（issue、pull、commit、留言）：不是錨點，略過
    m = re.match(r"([^/]+)/([^/]+)/(blob|tree|blame|raw)/([0-9a-f]{40})(?:/(.*))?$", path)
    rest = ((m.group(5) or "").rstrip("/")) if m else ""
    if not m or (m.group(3) != "tree" and not rest):
        out.append("B\t" + u + "\n"); continue
    key = (m.group(1) + "/" + m.group(2)).lower() + "/" + rest
    if m.group(3) == "tree":
        key = key.rstrip("/") + "/"
    out.append("\t".join(["F", m.group(3), m.group(1), m.group(2), m.group(4), key]) + "\n")
if none is not None:
    out.append("N\t" + none + "\n")
sys.stdout.buffer.write("".join(out).encode("utf-8"))
PY
anchor_parse() { python3 -I -c "${ANCHOR_PY}"; }

TCK_RAW_HOST='[Rr][Aa][Ww]\.[Gg][Ii][Tt][Hh][Uu][Bb][Uu][Ss][Ee][Rr][Cc][Oo][Nn][Tt][Ee][Nn][Tt]\.[Cc][Oo][Mm]'

# ── 錨點檢查要不要跳過這張票（也是格 9「施工票」的範圍） ─────────────
# 看標題的前綴，不看子字串：標題裡提到 SPEC 的施工票照查。
# ⚠️ 方括號必須加引號：case 的 glob 裡沒引號的 `[SPEC]*` 是字元類（開頭是 S、P、E 或 C）。
anchor_skip_title() {
  case "$1" in
    SPEC*|'[SPEC]'*|'[外審]'*|*指揮台*) return 0 ;;
  esac
  return 1
}

# ── 票種：印「種類<TAB>附註」。種類＝一般／SPEC／協調（labels.md 第七節：只認兩個例外）。附註欄保留，恆為空。
# 與 anchor_skip_title 刻意不同：`[外審]` 錨點跳過、標籤照查；協調類只認標題開頭「協作指揮台」。
ticket_kind() {
  case "$1" in
    協作指揮台*)       printf '協調\t\n' ;;
    SPEC*|'[SPEC]'*)   printf 'SPEC\t\n' ;;
    *)                 printf '一般\t\n' ;;
  esac
}

# 標籤屬於哪一組：逐字比對（labels.md 第一節），不用前綴或子字串。
_label_group() {
  case "$1" in
    錯誤|文件|改善|新功能|維護|資安)            printf '類型'; return 0 ;;
    P0-阻斷|P1-高|P2-一般|P3-低)                  printf '優先'; return 0 ;;
    輕驗證|中驗證|重驗證-自檢|重驗證-外審)        printf '驗證'; return 0 ;;
  esac
  return 0
}
_label_count() {  # labels（逗號分隔） 組名
  local c=0 l arr=()
  IFS=, read -r -a arr <<<"$1"
  for l in ${arr[@]+"${arr[@]}"}; do [ "$(_label_group "$l")" = "$2" ] && c=$((c+1)); done
  printf '%s' "$c"
}

# 格 1、2：印每一條違規（一行一條，`格N …`）；沒有違規就什麼都不印。
# 參數：state（open／closed，大小寫不拘）、title、labels（逗號分隔）。
# ⚠️ 已關的票只查格 2：舊票沒有類型／優先，查格 1 會整片假紅。
label_problems() {
  local state title="$2" labels="$3" kind g c
  state=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  kind=$(ticket_kind "$title"); kind="${kind%%$'\t'*}"

  # 格 2：單選
  for g in 類型 優先 驗證; do
    c=$(_label_count "$labels" "$g")
    [ "$c" -le 1 ] || echo "格2 ${g} 掛了 $c 個（一組只能一個）"
  done
  [ "$state" != closed ] || return 0

  # 格 1：必掛（依票種）
  case "$kind" in
    一般) for g in 類型 優先 驗證; do
            [ "$(_label_count "$labels" "$g")" -gt 0 ] || echo "格1 缺 ${g}（${kind}票）"
          done ;;
    SPEC) for g in 類型 優先; do
            [ "$(_label_count "$labels" "$g")" -gt 0 ] || echo "格1 缺 ${g}（${kind}票）"
          done ;;
    協調) ;;
  esac
  return 0
}

# 格 6：衍生。參數：上層票標題（沒有上層＝空字串）、labels。掛了 `衍生` 的票上層必須是 SPEC。
derive_problems() {
  local pkind=''
  [ -z "$1" ] || { pkind=$(ticket_kind "$1"); pkind="${pkind%%$'\t'*}"; }
  case ",$2," in
    *,衍生,*) [ "$pkind" = SPEC ] && return 0
              if [ -n "$1" ]; then echo "格6 掛了 衍生，但上層不是 SPEC（$1）＝SPEC 與閘門看不到（衍生票要直接掛 SPEC）"
              else echo "格6 掛了 衍生，但沒有上層票＝SPEC 與閘門看不到（衍生票要直接掛 SPEC）"; fi ;;
  esac
  return 0
}

# 格 9：施工票要有「做完能展示什麼」段，而且不是空的。stdin＝票內文。違規印一行，否則不印。
# 段落＝標題行含「做完能展示什麼」的那一段，到下一個同級或更高級的標題為止；只有空白或只有子標題＝空的。
demo_problem() {
  awk '
    match($0, /^#+ /) {
      lv = RLENGTH - 1
      if (f && lv <= sl) { f = 0; done = 1 }
      if (!done && !found && $0 ~ /做完能展示什麼/) { f = 1; found = 1; sl = lv; next }
    }
    f && !/^#+ / && /[^[:space:]]/ { c = 1 }   # 子標題本身不算內容
    END {
      if (!found) print "格9 沒有「做完能展示什麼」段"
      else if (!c) print "格9 「做完能展示什麼」段是空的"
    }'
}

# ⚠️ 本檔裡「printf 大字串 | awk」的 awk 一律讀完輸入、不用 exit 提早離開：
#   awk 先離開會讓上游 printf 吃 SIGPIPE，在 pipefail＋set -e 下整支靜靜死在半路（票多、內文大時才發生）。

# ── repo 設定（docs/agents/github.md） ─────────────────────────────
# stdin＝設定檔全文；印「## 機器讀的欄位」標題下第一個 text 區塊的內容。
cfg_block() {
  awk '
    stop { next }
    /^## 機器讀的欄位[[:space:]]*$/ { sec = 1; next }
    sec && !inb && /^## / { stop = 1; next }
    sec && !inb && /^```text[[:space:]]*$/ { inb = 1; next }
    inb && /^```/ { stop = 1; next }
    inb { print }'
}
# 參數：區塊內容、欄位名。印值（行首是欄位名接半形冒號，逐字比對；值去頭尾空白）；沒有這個欄位印空。
cfg_get() {
  printf '%s\n' "$1" | awk -v k="$2:" '!d && index($0, k) == 1 {
    v = substr($0, length(k) + 1); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); print v; d = 1 }'
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# 被 source 時只提供函式、不跑主體（給 tests/ 用）。
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

usage() { echo "用法：$0 <owner/repo> [票號 ...]" >&2; exit 2; }
[ $# -ge 1 ] || usage
repo="$1"; shift
case "$repo" in */*) ;; *) usage ;; esac
only=''   # 空＝查整個 repo；否則「 號 號 」
for x in "$@"; do
  x="${x#\#}"
  case "$x" in ''|*[!0-9]*) usage ;; esac
  x=$((10#$x))   # 012 ＝ 12（GitHub 的票號沒有前導零）
  only="${only:- } $x "
done
want_n() { [ -z "$only" ] || case "$only" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
tmp=$(mktemp); errf=$(mktemp); trap 'rm -f "$tmp" "$errf"' EXIT
bad=0; total=0; b9=0
seen_ok=''; seen_ng=''
lbad=0; lunk=0; lopen=0; lclosed=0; lother=0; oopen=0

{
  short="${repo##*/}"

  # ── repo 設定：讀不到就讓依賴它的格子印 UNKNOWN，不猜預設值（LABEL_OWNER 可補上帳號） ──
  cfg=''; arc=0
  raw=$(gh api -H 'Accept: application/vnd.github.raw+json' "repos/$repo/contents/docs/agents/github.md" 2>"$errf") || arc=$?
  if [ "$arc" = 0 ]; then
    cfg=$(printf '%s\n' "$raw" | cfg_block)
    [ -n "$cfg" ] || printf '?? %-14s docs/agents/github.md 沒有「## 機器讀的欄位」的 text 區塊\n' "$short"
  else
    printf '?? %-14s 讀不到 docs/agents/github.md（%s）\n' "$short" "$(tr '\n' ' ' <"$errf")"
  fi
  owner="${LABEL_OWNER:-}"
  if [ -n "$cfg" ] && [ -z "$owner" ]; then
    v=$(cfg_get "$cfg" 只檢查誰開的票)
    case "$v" in ''|未設定|見*) ;; *) owner="$v" ;; esac
  fi

  # ── 標籤：這個 repo 套用了沒？沒有類型標籤＝未套用，整個略過（否則整片紅）。 ──
  lab_on=0; arc=0
  names=$(gh api --paginate "repos/$repo/labels?per_page=100" --jq '.[].name' 2>"$errf") || arc=$?
  if [ "$arc" != 0 ]; then
    printf '?? %-14s 問不到標籤清單，略過標籤檢查（%s）\n' "$short" "$(tr '\n' ' ' <"$errf")"
    lunk=$((lunk+1))
  elif printf '%s\n' "$names" | grep -Eq '^(錯誤|文件|改善|新功能|維護|資安)$'; then
    if [ -n "$owner" ]; then lab_on=1; else
      printf '?? %-14s 不知道只檢查誰開的票（repo 設定「只檢查誰開的票」與 LABEL_OWNER 都沒有），略過標籤檢查\n' "$short"
      lunk=$((lunk+1))
    fi
  else
    printf '   %-14s 沒有類型標籤＝未套用標籤系統，略過標籤檢查\n' "$short"
  fi

  # 格 6 要上層票（一個 repo 一次 GraphQL）。問不到 ⇒ 格 6 整個 repo 不判、印 UNKNOWN。
  parents=''; par_ok=0
  if [ "$lab_on" = 1 ]; then
    arc=0
    parents=$(gh api graphql --paginate -F o="${repo%%/*}" -F r="${repo##*/}" -f query='
      query($o:String!,$r:String!,$endCursor:String){repository(owner:$o,name:$r){
        issues(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}
          nodes{number parent{title}}}}}' \
      --jq '.data.repository.issues.nodes[]|select(.parent!=null)|[.number,.parent.title]|@tsv' 2>"$errf") || arc=$?
    if [ "$arc" = 0 ]; then par_ok=1; else
      printf '?? %-14s 問不到上層票，略過格 6（%s）\n' "$short" "$(tr '\n' ' ' <"$errf")"
      lunk=$((lunk+1))
    fi
  fi

  # 每張開著的票的內文（錨點、格 9 用）：一個 repo 一次 GraphQL，不逐票 issue view。
  # 問不到 ⇒ 錨點與格 9 不查、印 UNKNOWN。
  arc=0; body_ok=0
  bodies=$(gh api graphql --paginate -F o="${repo%%/*}" -F r="${repo##*/}" -f query='
    query($o:String!,$r:String!,$endCursor:String){repository(owner:$o,name:$r){
      issues(first:100,after:$endCursor,states:OPEN){pageInfo{hasNextPage endCursor}
        nodes{number body}}}}' \
    --jq '.data.repository.issues.nodes[]|[.number,(.body|@base64)]|@tsv' 2>"$errf") || arc=$?
  if [ "$arc" = 0 ]; then body_ok=1; else
    printf '?? %-14s 問不到開著的票內文，錨點、格 9 不查（%s）\n' "$short" "$(tr '\n' ' ' <"$errf")"
    lunk=$((lunk+1))
  fi

  # 開著＋已關的票都要拿（格 2 也看已關的）；錨點與格 9 只查開著的。
  # ⚠️ 標籤放最後一欄：@tsv 的 tab 是 read 的空白分隔符，空欄會被吞掉——放中間會讓標題往前挪。
  # ⚠️ 不要寫成 `for n in $(gh api …)`：命令替換失敗不會觸發 set -e，問不到會變成「0 張票、全過」。
  arc=0
  rows=$(gh api --paginate "repos/$repo/issues?state=all&per_page=100" \
           --jq '.[]|select(.pull_request==null)|[.number,.state,.user.login,.title,([.labels[].name]|join(","))]|@tsv' 2>"$errf") || arc=$?
  if [ "$arc" != 0 ]; then
    printf '?? %-14s 問不到票清單（%s）\n' "$short" "$(tr '\n' ' ' <"$errf")"
    lunk=$((lunk+1)); rows=''
  fi
  # 給了票號：清單裡找不到的票號印 UNKNOWN（打錯號、或那是 PR）。
  if [ -n "$rows" ]; then
    for x in $only; do
      printf '%s\n' "$rows" | awk -F'\t' -v n="$x" '$1==n{f=1} END{exit !f}' \
        || { printf '?? %-14s#%-3s 找不到這張票（不在票清單裡；PR 不算票）\n' "$short" "$x"; lunk=$((lunk+1)); }
    done
  fi
  lowner=$(lower "$owner")
  # fd 3：迴圈裡的 gh 不可以吃到這份清單的 stdin。
  while IFS=$'\t' read -r -u 3 n state author rtitle labels; do
    [ -n "$n" ] || continue
    want_n "$n" || continue
    if [ "$lab_on" = 1 ] && [ "$(lower "$author")" != "$lowner" ]; then
      lother=$((lother+1))
      [ "$state" != open ] || oopen=$((oopen+1))
    elif [ "$lab_on" = 1 ]; then
      probs=$(label_problems "$state" "$rtitle" "$labels")
      if [ "$par_ok" = 1 ] && [ "$state" = open ]; then
        ptitle=$(printf '%s\n' "$parents" | awk -F'\t' -v n="$n" '!d && $1==n{print $2; d=1}')
        p6=$(derive_problems "$ptitle" "$labels")
        if [ -n "$p6" ]; then [ -z "$probs" ] || probs="$probs"$'\n'; probs="$probs$p6"; fi
      fi
      if [ "$state" = open ]; then
        lopen=$((lopen+1))
      else
        lclosed=$((lclosed+1))
      fi
      kind=$(ticket_kind "$rtitle"); kind="${kind%%$'\t'*}"
      if [ -n "$probs" ]; then
        lbad=$((lbad+1))
        while IFS= read -r p; do
          printf 'NG %-14s#%-3s 標籤 %s — %s\n' "$short" "$n" "$p" "$rtitle"
        done <<<"$probs"
      elif [ "$state" = open ]; then
        printf '   %-14s#%-3s 標籤 OK（%s票）\n' "$short" "$n" "$kind"
      fi
    fi
    [ "$state" = open ] || continue

    title="$rtitle"
    # SPEC、外審與指揮台沒有程式碼錨點，也不是施工票——跳過，但印出來讓人看得見跳了誰。
    if anchor_skip_title "$title"; then
      printf '  skip %-14s#%-3s %s\n' "$short" "$n" "$title"; continue
    fi
    [ "$body_ok" = 1 ] || continue   # 內文問不到：repo 層已印 ??
    brow=$(printf '%s\n' "$bodies" | awk -F'\t' -v n="$n" '!d && $1==n{print; d=1}')
    if [ -z "$brow" ]; then
      printf '?? %-14s#%-3s 問不到這張票的內文，錨點與格 9 不查 — %s\n' "$short" "$n" "$title"
      lunk=$((lunk+1)); continue
    fi
    printf '%s' "$brow" | cut -f2 | base64 -d > "$tmp"
    total=$((total+1))

    # 格 9：做完能展示什麼
    p9=$(demo_problem < "$tmp")
    if [ -n "$p9" ]; then
      printf 'NG %-14s#%-3s %s — %s\n' "$short" "$n" "$p9" "$title"
      b9=$((b9+1))
    fi

    # 錨點段與連結的判法：本檔上方的 anchor_section／anchor_parse。
    anc=$(anchor_section < "$tmp")
    if [ -z "$anc" ]; then
      printf 'NG %-14s#%-3s 沒有「## 錨點」段 — %s\n' "$short" "$n" "$title"
      bad=$((bad+1)); continue
    fi
    arc=0
    recs=$(printf '%s\n' "$anc" | anchor_parse 2>"$errf") || arc=$?
    if [ "$arc" != 0 ]; then
      printf '?? %-14s#%-3s 錨點段解析失敗，錨點不查（%s） — %s\n' "$short" "$n" "$(tr '\n' ' ' <"$errf")" "$title"
      lunk=$((lunk+1)); continue
    fi
    # 形狀（只數 40 碼十六進位接在 blob／tree／blame／raw 或 raw 網域後面）與抽得出網址的條數分開數，對不上就 !!。
    # 先 -o 攤成一行一條再數行（`grep -c` 數的是行數，一行兩個連結只算 1）。
    # grep 沒命中回 1，set -e ＋ pipefail 會讓整支靜靜死掉——`|| true` 是必須的。
    #   SHA 只認小寫十六進位（大寫的不是 GitHub 印出來的 SHA）；raw 網域的 host 不分大小寫，照 anchor_parse。
    sha=$(printf '%s' "$anc" \
      | { grep -Eo "(/(blob|tree|blame|raw)/|${TCK_RAW_HOST}/[^/[:space:]]+/[^/[:space:]]+/)[0-9a-f]{40}([^0-9a-fA-F]|\$)" || true; } \
      | { grep -c . || true; })
    nopin=$(printf '%s\n' "$recs" | awk -F'\t' '$1 == "B" { print $2 }')
    none=$(printf '%s\n' "$recs" | awk -F'\t' '$1 == "N" { print $2 "\t" $3 }')
    if [ "$sha" = 0 ]; then
      # 沒有程式碼錨點的票（開票、決定、查證…）在錨點段明寫一行「- 無：<理由>」；理由空白不算。
      # 寫了「無」又放了沒釘 SHA 的檔案連結 ⇒ NG（那條連結會跟著分支變，不是錨點）。
      case "$none" in
        R$'\t'*)
          if [ -n "$nopin" ]; then
            printf 'NG %-14s#%-3s 錨點寫了「無」又放了沒釘 SHA 的檔案連結（改成 SHA 固定連結，或拿掉）：%s — %s\n' \
              "$short" "$n" "$(printf '%s\n' "$nopin" | paste -sd ' ' -)" "$title"
            bad=$((bad+1)); continue
          fi
          printf '   %-14s#%-3s 錨點 無：%s\n' "$short" "$n" "${none#R$'\t'}"; continue ;;
        EMPTY*) printf 'NG %-14s#%-3s 錨點寫了「無」但沒寫理由（寫成「- 無：<理由>」） — %s\n' "$short" "$n" "$title"
               bad=$((bad+1)); continue ;;
      esac
      printf 'NG %-14s#%-3s 錨點沒有 SHA 固定連結 — %s\n' "$short" "$n" "$title"
      bad=$((bad+1)); continue
    fi

    # ── 形狀對不代表那顆存在：逐顆問 GitHub ──
    # 去重前後分開數：同一顆 SHA 的不同檔只問一次，但對照組要用去重前的條數。
    urls_raw=$(printf '%s\n' "$recs" | awk -F'\t' '$1 == "F" { print tolower($3 "/" $4) "@" $5 }')
    urls=$(printf '%s' "$urls_raw" | sort -u)
    # ⚠️ 不可以寫成 `[ -n "$urls" ] && nurl=$(…)`：set -e 之下 urls 為空時整式回 1，整支靜靜終止。
    nurl=0
    if [ -n "$urls_raw" ]; then nurl=$(printf '%s\n' "$urls_raw" | { grep -c . || true; }); fi
    # 有 SHA 連結、又有沒釘 SHA 的檔案連結：那幾條沒被驗存在。
    if [ -n "$nopin" ]; then
      while IFS= read -r u; do
        printf '!! %-14s#%-3s 錨點有沒釘 SHA 的檔案連結，沒被驗存在：%s\n' "$short" "$n" "$u"
      done <<<"$nopin"
    fi

    miss=0; unk=0
    if [ -n "$urls" ]; then
      while IFS= read -r url; do
        [ -n "$url" ] || continue
        o="${url%%/*}"; rest="${url#*/}"       # url＝owner/repo@SHA
        r="${rest%%@*}"; s40="${rest#*@}"
        key="$url"
        case " $seen_ok " in *" $key "*) continue ;; esac
        case " $seen_ng " in *" $key "*) miss=$((miss+1)); continue ;; esac

        # ⚠️ set -e：`err=$(cmd); arc=$?` 在 cmd 失敗時直接終止，那一行的 $? 永遠讀不到。
        arc=0
        err=$(gh api "repos/$o/$r/commits/$s40" --jq .sha 2>&1 >/dev/null) || arc=$?
        if [ "$arc" = 0 ]; then
          seen_ok="$seen_ok $key"
        else
          # 分得出「不在」與「沒問到」——這一格是本支唯一會冤枉人的地方。
          #   422（No commit found）＝ repo 讀得到、那顆 SHA 不在 ⇒ NG。
          #   404（Not Found）＝ repo 讀不到：沒權限讀的私有 repo 也回 404 ⇒ 分不出「不在」，落到下面的 ??。
          case "$err" in
            *'HTTP 422'*|*'No commit found'*)
              printf 'NG %-14s#%-3s 錨點指的 SHA 在 %s/%s **不存在**：%s\n' \
                "$short" "$n" "$o" "$r" "$s40"
              seen_ng="$seen_ng $key"; miss=$((miss+1)) ;;
            *)
              printf '?? %-14s#%-3s 問不到 %s/%s@%s（%s）\n' \
                "$short" "$n" "$o" "$r" "$s40" "$(printf '%s' "$err" | tr '\n' ' ')"
              unk=$((unk+1)) ;;
          esac
        fi
      done <<EOF
$urls
EOF
    fi

    # 對照組：只數形狀的那把（$sha）與抽得出網址的那把（$nurl）對不上 ⇒ 有錨點沒被驗存在。不判 NG，但一定講。
    if [ "$sha" != "$nurl" ]; then
      printf '!! %-14s#%-3s 形狀 %s 條、抽得出網址 %s 條 ⇒ 有 %s 條沒被驗存在\n' \
        "$short" "$n" "$sha" "$nurl" "$((sha-nurl))"
    fi

    lunk=$((lunk+unk))   # 錨點 SHA 問不到的也算進總結的「問不到 N 處」
    if [ "$miss" -gt 0 ]; then
      bad=$((bad+1))
    else
      nuniq=0
      if [ -n "$urls" ]; then nuniq=$(printf '%s\n' "$urls" | { grep -c . || true; }); fi
      printf '   %-14s#%-3s 錨點 SHA 連結 %s 條／%s 顆（驗存在 %s 顆，問不到 %s）\n' \
        "$short" "$n" "$sha" "$nuniq" "$((nuniq-unk))" "$unk"
    fi
  done 3<<<"$rows"
  # 有開著的票、卻沒有一張是設定的帳號開的 ⇒ 帳號多半設錯（全部「別人開的、不查」看起來跟全過一樣）。
  if [ "$lab_on" = 1 ] && [ "$lopen" = 0 ] && [ "$oopen" -gt 0 ]; then
    printf '?? %-14s 開著的票 %s 張，沒有一張是 %s 開的（「只檢查誰開的票」設對了嗎？）\n' "$short" "$oopen" "$owner"
    lunk=$((lunk+1))
  fi
}

echo "--"
echo "施工票 $total 張，缺錨點／缺 SHA／SHA 不存在 $bad 張，缺或空「做完能展示什麼」$b9 張"
echo "標籤：開著 $lopen 張（格 1、2、6）、已關 $lclosed 張（格 2），NG $lbad 張，問不到 $lunk 處；別人開的 $lother 張不查"
[ "$bad" -eq 0 ] && [ "$lbad" -eq 0 ] && [ "$b9" -eq 0 ]
