#!/usr/bin/env bash
# 開票自檢：施工票的錨點（SHA 固定連結、那顆 SHA 真的存在）、標籤格 1～8、「做完能展示什麼」（格 9）。
# 每格查什麼、判紅條件、三態意思：references/ticket-check.md。
#
# 用法：ticket-check.sh <owner/repo> [票號 ...]
#   給了票號只查那幾張（標籤、格 5～9、錨點都只查那幾張）；不給查整個 repo。
# 退出碼：0＝全過；1＝有 NG；2＝參數用錯。正常跑完一定印 `--` 開頭的總結；沒有總結＝沒跑完（不是 NG）。
#
# repo 特有的值一律讀目標 repo 的 docs/agents/github.md（「機器讀的欄位」區塊，見 setup 的 repo 設定範本）：
#   只檢查誰開的票、施工狀態記法、Project 所在、機器標籤名。
#   值去頭尾空白；機器標籤名逐個去空白；帳號比對不分大小寫。
#   讀不到「施工狀態記法」⇒ 格 3、8 印 UNKNOWN、不判；讀不到「機器標籤名」⇒ 格 3、4 不判；其他格照跑。
#   環境變數 LABEL_OWNER 覆寫「只檢查誰開的票」；兩者都沒有 ⇒ 標籤格整個印 UNKNOWN（錨點與格 9 照跑）。
#
# 三態：OK＝問到了而且對；NG＝問到了而且不對；UNKNOWN（`??` 開頭）＝沒問到（離線、沒權限、限流、設定讀不到）。
#   UNKNOWN 不算 NG——否則離線時這支永遠紅，永遠紅的燈等於沒有燈。但它一定會被印出來。
#
# 只讀：這支只呼叫 GitHub 的讀取 API，不改任何票、標籤或設定。
set -euo pipefail
TCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 9
# 「合併後還有步驟嗎」的唯一判法（與 pr-risk.sh 共用，不另寫一份 pattern）。
# shellcheck source=lib/after-merge-step.sh
. "${TCK_DIR}/lib/after-merge-step.sh" || exit 9
# 錨點段怎麼讀、哪些連結算錨點、「- 無：<理由>」怎麼認（與 anchor-overlap.sh 共用，不另寫一份）。
# shellcheck source=lib/anchor-links.sh
. "${TCK_DIR}/lib/anchor-links.sh" || exit 9
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
# 機器標籤名來自 repo 設定，放在全域 MACHINE_LABELS（逗號分隔；空＝這個 repo 不用機器標籤）。
MACHINE_LABELS=''
_label_group() {
  case "$1" in
    錯誤|文件|改善|新功能|維護|資安)            printf '類型'; return 0 ;;
    P0-阻斷|P1-高|P2-一般|P3-低)                  printf '優先'; return 0 ;;
    輕驗證|中驗證|重驗證-自檢|重驗證-外審)        printf '驗證'; return 0 ;;
  esac
  case ",$MACHINE_LABELS," in *,"$1",*) [ -n "$1" ] && printf '機器' ;; esac
  return 0
}
_label_count() {  # labels（逗號分隔） 組名
  local c=0 l arr=()
  IFS=, read -r -a arr <<<"$1"
  for l in ${arr[@]+"${arr[@]}"}; do [ "$(_label_group "$l")" = "$2" ] && c=$((c+1)); done
  printf '%s' "$c"
}
_has_label() { case ",$1," in *,"$2",*) return 0 ;; esac; return 1; }

# 狀態標籤記法（labels）的狀態標籤；Project 記法（project）不准掛它們（格 8）。
STATUS_LABELS='施工中 待驗證'

# 格 1～4、8：印每一條違規（一行一條，`格N …`）；沒有違規就什麼都不印。
# 參數：state（open／closed，大小寫不拘）、title、labels（逗號分隔）、pstatus、mode、machines。
#   mode：repo 設定的施工狀態記法 `labels`／`project`；`?`＝設定讀不到 ⇒ 格 3、8 不判（呼叫端印 UNKNOWN）。
#   machines：機器標籤名（逗號分隔）；空＝不用機器標籤 ⇒ 格 3、4 不判；`?`＝讀不到 ⇒ 不判。
#   pstatus（只在 project 記法有意義）：`NONE`＝票不在 Project；`?`＝問不到；其餘＝Status 的值。
# ⚠️ 已關的票只查格 2、格 4：舊票沒有類型／優先，查格 1 會整片假紅。
label_problems() {
  local state title="$2" labels="$3" ps="${4:-}" mode="${5:-?}" machines="${6:-?}" kind g c busy=0 r
  state=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  kind=$(ticket_kind "$title"); kind="${kind%%$'\t'*}"
  local MACHINE_LABELS="$machines" mknown=1
  case "$machines" in '?'|'') mknown=0 ;; esac

  # 格 2：單選
  for g in 類型 優先 驗證; do
    c=$(_label_count "$labels" "$g")
    [ "$c" -le 1 ] || echo "格2 ${g} 掛了 $c 個（一組只能一個）"
  done

  if [ "$state" = closed ]; then
    # 格 4：關票清乾淨
    [ "$mknown" = 0 ] || [ "$(_label_count "$labels" 機器)" -eq 0 ] || echo "格4 已關閉還掛著機器標籤（${machines}）"
    return 0
  fi

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

  # 格 8：狀態只有一處（只在 project 記法判）
  if [ "$mode" = project ]; then
    if [ "$ps" = NONE ] && [ "$kind" != 協調 ]; then
      echo "格8 這個 repo 的狀態記在 Project，票卻不在 Project 裡（把票加進 Project、設 Status）"
    fi
    for r in $STATUS_LABELS; do
      _has_label "$labels" "$r" && echo "格8 狀態記在 Project 的 repo 掛了狀態標籤 ${r}（改設 Status，再拿掉標籤）"
    done
  fi

  # 格 3：找得到人
  case "$mode" in
    labels)  for r in $STATUS_LABELS; do _has_label "$labels" "$r" && busy=1; done ;;
    project) case "$ps" in 'In Progress'|施工中|待驗證) busy=1 ;; esac ;;
  esac
  [ "$busy" = 0 ] || [ "$mknown" = 0 ] || [ "$(_label_count "$labels" 機器)" -gt 0 ] \
    || echo "格3 有人在做／待驗證，卻沒掛機器標籤（${machines}）"
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

# 格 7：票上有「合併後／部署後」的步驟，卻有開著的 PR 會在合併時自動關它。
# 參數：票內文、會關它的開著 PR（逗號分隔，空＝沒有）。違規印一行，否則不印。
# 「有沒有合併後步驟」用 lib/after-merge-step.sh 的 has_after_merge_step（判準與理由寫在那一檔）。
closes_problem() {
  [ -n "$1" ] && [ -n "$2" ] || return 0
  has_after_merge_step "$1" || return 0
  echo "格7 票上有合併／部署後的步驟，但 PR ${2} 合併時會自動關票（PR 改寫 Refs；分支別用 gh issue develop 開）"
}

# 格 7 的整合 PR：PR 內文用關閉關鍵字（close／fix／resolve 各種時態）指到本 repo 的票號，一行一個。
# 參數：PR 內文、本 repo（owner/repo）。`Refs` 不是關閉關鍵字；code span 與 fenced code block 裡的關鍵字 GitHub 不認，先拿掉。
# 票可以寫 `#N`、`owner/repo#N`，或票的網址 `https://github.com/owner/repo/issues/N`（GitHub 都認）。
# 指到別的 repo（且不是本 repo）的不算。
pr_closing_refs() {
  printf '%s\n' "$1" | awk -v me="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" '
    # fenced code block：三個以上的 ` 或 ~ 開頭的行開始，到「同一種字元、長度不少於開頭」的圍欄行結束
    # （圍欄行本身也不掃；四個反引號開的區塊，裡面的三個反引號不會關上它）。
    # 反引號圍欄的資訊字串不能含反引號（CommonMark）：行首的 ```x``` 是行內的 code span，不是圍欄開頭。
    fence == "" && match($0, /^[ \t]*(```+|~~~+)/) {
      f = substr($0, RSTART, RLENGTH); sub(/^[ \t]*/, "", f)
      if (!(substr(f, 1, 1) == "`" && index(substr($0, RSTART + RLENGTH), "`") > 0)) { fc = substr(f, 1, 1); fence = f; next } }
    fence != "" {
      if (match($0, /^[ \t]*(```+|~~~+)[ \t]*$/)) {
        g = substr($0, RSTART, RLENGTH); gsub(/[ \t]/, "", g)
        if (substr(g, 1, 1) == fc && length(g) >= length(fence)) fence = ""
      }
      next }
    { s = tolower($0); gsub(/`[^`]*`/, "", s)
      while (match(s, /(^|[^a-z0-9_])(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):?[ \t]+(https:\/\/github\.com\/[a-z0-9_.-]+\/[a-z0-9_.-]+\/issues\/|([a-z0-9_.-]+\/[a-z0-9_.-]+)?#)[0-9]+/)) {
        m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        n = m; sub(/.*[#\/]/, "", n)
        q = m; sub(/^.*[ \t]/, "", q); sub(/^https:\/\/github\.com\//, "", q); sub(/(\/issues\/|#)[0-9]+$/, "", q)
        if (q == "" || q == me) print n
      } }' | sort -un
}

# 格 5：不驗自己的票。stdin＝每則留言的「最後一個非空行」（一行一則）。
# 印一行：`OK …`／`NG …`／`UNKNOWN …`（沒讀出來不算 NG，但要講）。
# 署名兩種格式都認（欄位用全形「｜」分隔）：
#   新：`— 🔨 施工｜機器｜執行者｜分支`（第 3 欄＝執行者）
#   舊：`— 🔨 施工軌｜機器｜軌號｜執行者｜分支`（角色以「軌」結尾；第 4 欄＝執行者）
# 執行者：對話本身 `session <id>`；子代理 `agent-<id>@<派它的 session id>`（前面可有「施工子代理」等字）。
# 判 NG：施工與驗證的 session 部分相同（`session <id>` 的 id；`agent-<id>@<session>` 的 @ 後面）——
#   同一個對話自己驗、驗自己派的子代理、或自己派的兩個子代理一施工一驗證，都是同一個對話在驗自己。
# 多則驗證署名：任一則判得出自驗就 NG；讀不出執行者的那幾則不蓋掉它（沒有 NG 時才印 UNKNOWN）。
# id 比對用「前綴相同」（8 碼與完整 id 視為同一個）。
_same_id() { case "$1" in "$2"*) return 0 ;; esac; case "$2" in "$1"*) return 0 ;; esac; return 1; }
_executor() {  # 署名行 ⇒ 印「agent <id> <session>」或「session <id> <session>」；讀不出來印空
  local line="$1" rest f=() ef x
  rest="$line"
  while [[ "$rest" == *｜* ]]; do f+=("${rest%%｜*}"); rest="${rest#*｜}"; done
  f+=("$rest")
  case "${f[0]}" in
    *軌) ef=3 ;;  # 舊署名：角色｜機器｜軌號｜執行者｜分支
    *) ef=2 ;;    # 新署名：角色｜機器｜執行者｜分支
  esac
  [ "${#f[@]}" -gt "$ef" ] || return 0
  x="${f[$ef]}"
  if [[ "$x" =~ agent-([A-Za-z0-9_-]+)@([A-Za-z0-9_-]+) ]]; then
    printf 'agent %s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  elif [[ "$x" =~ ^[[:space:]]*session[[:space:]]+([A-Za-z0-9_-]+) ]]; then
    printf 'session %s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[1]}"
  fi
  return 0
}
# 署名行前面的 markdown 修飾（空白、引用的 `>`、粗體斜體的 `*`／`_`、清單符號 `- `／`+ `、HTML 標籤如 `<sub>`）先去掉再認；
# emoji 與角色之間、破折號與 emoji 之間漏了空白（`🔍驗證`、`—🔨 施工`）補回來再認。
# 去掉之後仍不是以署名開頭、但行內有「🔍 驗證」的，算一則讀不出執行者的驗證署名（不當成沒有驗證署名）。
_sig_strip() {
  local x="$1" tag='^<[A-Za-z][A-Za-z0-9]*>'
  while :; do
    case "$x" in
      [[:space:]\>\*_]*) x="${x#?}" ;;
      [-+][[:space:]]*)  x="${x#?}" ;;
      '<'*) [[ "$x" =~ $tag ]] || break; x="${x#"${BASH_REMATCH[0]}"}" ;;
      *) break ;;
    esac
  done
  x="${x//🔍驗證/🔍 驗證}"; x="${x//🔨施工/🔨 施工}"; x="${x/#—🔍/— 🔍}"; x="${x/#—🔨/— 🔨}"
  printf '%s' "$x"
}
self_verify_verdict() {
  local line e builders=() verifiers=() b v bk bi bs vk vi vs nv=0 unread=''
  while IFS= read -r line; do
    line=$(_sig_strip "$line")
    case "$line" in
      '— 🔨 施工'*|'— 🔍 驗證'*) ;;
      *'🔍 驗證'*) nv=$((nv+1)); [ -n "$unread" ] || unread="$line"; continue ;;
      *) continue ;;
    esac
    e=$(_executor "$line")
    case "$line" in
      '— 🔨 施工'*) [ -z "$e" ] || builders+=("$e") ;;
      '— 🔍 驗證'*)
        nv=$((nv+1))
        if [ -z "$e" ]; then [ -n "$unread" ] || unread="$line"; else verifiers+=("$e"); fi ;;
    esac
  done
  [ "$nv" -gt 0 ] || { echo "OK 沒有驗證署名"; return 0; }
  for v in ${verifiers[@]+"${verifiers[@]}"}; do
    read -r vk vi vs <<<"$v"
    for b in ${builders[@]+"${builders[@]}"}; do
      read -r bk bi bs <<<"$b"
      if _same_id "$vs" "$bs"; then
        echo "NG 驗證者 ${vk} ${vi} 與施工者 ${bk} ${bi} 是同一個對話（session ${bs}）"; return 0; fi
    done
  done
  [ -z "$unread" ] || { echo "UNKNOWN 驗證署名讀不出執行者：$unread"; return 0; }
  [ "${#builders[@]}" -gt 0 ] || { echo "UNKNOWN 有驗證署名、但沒有讀得出執行者的施工署名可比"; return 0; }
  echo "OK 驗證者（${verifiers[*]}）與施工者（${builders[*]}）獨立"
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
# 逗號分隔的清單逐個去頭尾空白、丟掉空項。
trim_list() {
  printf '%s\n' "$1" | tr ',' '\n' | awk '{ sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "") } NF' | paste -sd, -
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# 一個 repo 一次 GraphQL：每張開著的票 `<票號>\t<Status｜（未設）｜NONE>`（NONE＝不在那個 Project）。
# 參數：owner/repo、Project 擁有者、Project 號碼。失敗 ⇒ 非 0 退出（呼叫端印 UNKNOWN，不能當成「都不在 Project」）。
# 有設 GH_TOKEN 而那把沒有 project 權限時，改用 gh 自己的登入再試一次。
project_status_rows() {
  local q jq
  q='query($o:String!,$r:String!,$endCursor:String){repository(owner:$o,name:$r){
      issues(first:100,after:$endCursor,states:OPEN){pageInfo{hasNextPage endCursor}
        nodes{number projectItems(first:20){nodes{project{number owner{... on Organization{login} ... on User{login}}}
          fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}}'
  jq=".data.repository.issues.nodes[]|[.number,([.projectItems.nodes[]|select(.project.number==$3 and .project.owner.login==\"$2\")|(.fieldValueByName.name // \"（未設）\")]|first // \"NONE\")]|@tsv"
  gh api graphql --paginate -F o="${1%%/*}" -F r="${1##*/}" -f query="$q" --jq "$jq" && return 0
  [ -n "${GH_TOKEN:-}" ] || return 1
  env -u GH_TOKEN gh api graphql --paginate -F o="${1%%/*}" -F r="${1##*/}" -f query="$q" --jq "$jq"
}
ticket_pstatus() {  # ok（1＝問得到）、project_status_rows 的輸出、票號
  [ "$1" = 1 ] || { printf '?'; return 0; }
  local s; s=$(printf '%s\n' "$2" | awk -F'\t' -v n="$3" '!d && $1==n{print $2; d=1}')
  printf '%s' "${s:-NONE}"
}

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

  # ── repo 設定：讀不到就讓依賴它的格子印 UNKNOWN，不猜預設值 ──
  cfg=''; arc=0
  raw=$(gh api -H 'Accept: application/vnd.github.raw+json' "repos/$repo/contents/docs/agents/github.md" 2>"$errf") || arc=$?
  if [ "$arc" = 0 ]; then
    cfg=$(printf '%s\n' "$raw" | cfg_block)
    [ -n "$cfg" ] || printf '?? %-14s docs/agents/github.md 沒有「## 機器讀的欄位」的 text 區塊\n' "$short"
  else
    printf '?? %-14s 讀不到 docs/agents/github.md（%s）\n' "$short" "$(tr '\n' ' ' <"$errf")"
  fi
  mode='?'; machines='?'; powner=''; pnum=''; owner="${LABEL_OWNER:-}"
  if [ -n "$cfg" ]; then
    v=$(cfg_get "$cfg" 施工狀態記法)
    case "$v" in labels|project) mode="$v" ;; esac
    v=$(cfg_get "$cfg" 機器標籤名)
    case "$v" in 無) machines='' ;; ''|見*) ;; *) machines=$(trim_list "$v") ;; esac
    if [ "$mode" = project ]; then
      v=$(cfg_get "$cfg" 'Project 所在')
      if [[ "$v" =~ ^([A-Za-z0-9][A-Za-z0-9-]*)[^A-Za-z0-9]+([0-9]+)$ ]]; then
        powner="${BASH_REMATCH[1]}"; pnum="${BASH_REMATCH[2]}"
      fi
    fi
    if [ -z "$owner" ]; then
      v=$(cfg_get "$cfg" 只檢查誰開的票)
      case "$v" in ''|未設定|見*) ;; *) owner="$v" ;; esac
    fi
  fi
  # 實際不判哪幾格：記法讀不到 ⇒ 格 3、8；機器標籤名讀不到 ⇒ 格 3、4。
  skipc=''
  case "$mode:$machines" in
    '?:?') skipc='3、4、8' ;; '?:'*) skipc='3、8' ;; *':?') skipc='3、4' ;;
  esac
  if [ -n "$skipc" ]; then
    printf '?? %-14s repo 設定缺「施工狀態記法」或「機器標籤名」，格 %s 不判\n' "$short" "$skipc"
    lunk=$((lunk+1))
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

  # 格 3、8 在 project 記法要每張開著的票在 Project 的 Status。問不到 ⇒ 印 UNKNOWN（不能當成「都不在」）。
  pstat=''; ps_ok=0
  if [ "$lab_on" = 1 ] && [ "$mode" = project ]; then
    arc=0
    if [ -z "$pnum" ]; then
      printf '?? %-14s repo 設定的「Project 所在」讀不出擁有者與號碼，格 3、8 的 Project 判斷不做\n' "$short"
      lunk=$((lunk+1))
    elif pstat=$(project_status_rows "$repo" "$powner" "$pnum" 2>"$errf"); then ps_ok=1; else
      printf '?? %-14s 問不到 Project Status，格 3、8 的 Project 判斷不做（%s）\n' "$short" "$(tr '\n' ' ' <"$errf")"
      lunk=$((lunk+1))
    fi
  fi

  # 每張開著的票的內文（錨點、格 7、格 9 都用）與 GitHub 原生登記的「會關它的 PR」：一個 repo 一次 GraphQL，不逐票 issue view。
  # 問不到 ⇒ 錨點與格 9 每張印 UNKNOWN、格 7 整個 repo 印 UNKNOWN。
  arc=0; body_ok=0
  closers=$(gh api graphql --paginate -F o="${repo%%/*}" -F r="${repo##*/}" -f query='
    query($o:String!,$r:String!,$endCursor:String){repository(owner:$o,name:$r){
      issues(first:100,after:$endCursor,states:OPEN){pageInfo{hasNextPage endCursor}
        nodes{number body closedByPullRequestsReferences(first:25,includeClosedPrs:false){nodes{number}}}}}}' \
    --jq '.data.repository.issues.nodes[]|[.number,([.closedByPullRequestsReferences.nodes[].number|"#\(.)"]|join(",")),(.body|@base64)]|@tsv' 2>"$errf") || arc=$?
  if [ "$arc" = 0 ]; then body_ok=1; else
    printf '?? %-14s 問不到開著的票內文，錨點、格 7、格 9 不查（%s）\n' "$short" "$(tr '\n' ' ' <"$errf")"
    lunk=$((lunk+1))
  fi

  # 格 7 要「哪些開著的 PR 合併時會關這張票」，兩個來源取聯集：
  #   ① GitHub 原生的 closedByPullRequestsReferences（PR 寫關閉關鍵字、或從 gh issue develop 開的分支）
  #   ② 整合 PR：開著、目標是預設分支的 PR，內文用關閉關鍵字指到的票（pr_closing_refs）
  # 任一個問不到 ⇒ 格 7 整個 repo 印 UNKNOWN——不能當成「沒有 PR 會關它」（那是假綠）。
  prrefs=''; cl_ok=0
  if [ "$lab_on" = 1 ] && [ "$body_ok" = 1 ]; then
    arc=0
    defb=''
    [ "$arc" != 0 ] || defb=$(gh api "repos/$repo" --jq .default_branch 2>"$errf") || arc=$?
    pulls=''
    [ "$arc" != 0 ] || pulls=$(gh api --paginate "repos/$repo/pulls?state=open&per_page=100" \
                                 --jq '.[]|[.number,.base.ref,((.body // "")|@base64)]|@tsv' 2>"$errf") || arc=$?
    if [ "$arc" = 0 ] && [ -n "$defb" ]; then
      cl_ok=1
      while IFS=$'\t' read -r pn pbase pbody; do
        [ -n "$pn" ] || continue
        [ "$pbase" = "$defb" ] || continue
        for x in $(pr_closing_refs "$(printf '%s' "$pbody" | base64 -d)" "$repo"); do
          prrefs="$prrefs$x"$'\t'"#$pn"$'\n'
        done
      done <<<"$pulls"
    else
      printf '?? %-14s 問不到會關票的 PR，略過格 7（%s）\n' "$short" "$(tr '\n' ' ' <"$errf")"
      lunk=$((lunk+1))
    fi
  fi

  # 開著＋已關的票都要拿（格 4 看已關的）；錨點與格 9 只查開著的。
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
      ps=''
      [ "$state" = open ] && [ "$mode" = project ] && ps=$(ticket_pstatus "$ps_ok" "$pstat" "$n")
      probs=$(label_problems "$state" "$rtitle" "$labels" "$ps" "$mode" "$machines")
      if [ "$par_ok" = 1 ] && [ "$state" = open ]; then
        ptitle=$(printf '%s\n' "$parents" | awk -F'\t' -v n="$n" '!d && $1==n{print $2; d=1}')
        p6=$(derive_problems "$ptitle" "$labels")
        if [ -n "$p6" ]; then [ -z "$probs" ] || probs="$probs"$'\n'; probs="$probs$p6"; fi
      fi
      if [ "$state" = open ]; then
        lopen=$((lopen+1))
        # 格 5：只查開著的（一張票一次 API）。
        arc=0
        lasts=$(gh api --paginate "repos/$repo/issues/$n/comments?per_page=100" \
                  --jq '.[].body|split("\n")|map(select(test("\\S")))|last // ""' 2>"$errf") || arc=$?
        if [ "$arc" != 0 ]; then
          v5="UNKNOWN 問不到留言（$(tr '\n' ' ' <"$errf")）"
        else
          v5=$(printf '%s\n' "$lasts" | self_verify_verdict)
        fi
        case "$v5" in
          NG*)      [ -z "$probs" ] || probs="$probs"$'\n'
                    probs="${probs}格5 ${v5#NG }" ;;
          UNKNOWN*) printf '?? %-14s#%-3s 格5 %s\n' "$short" "$n" "${v5#UNKNOWN }"; lunk=$((lunk+1)) ;;
        esac
        # 格 7：原生與整合 PR 兩個來源取聯集；都沒有 ⇒ 不判。
        if [ "$cl_ok" = 1 ]; then
          crow=$(printf '%s\n' "$closers" | awk -F'\t' -v n="$n" '!d && $1==n{print; d=1}')
          prs=$( { printf '%s\n' "$crow" | cut -f2 | tr ',' '\n'
                   printf '%s' "$prrefs" | awk -F'\t' -v n="$n" '$1==n{print $2}'; } | awk 'NF && !s[$0]++' | paste -sd, -)
          if [ -n "$prs" ] && [ -n "$crow" ]; then
            p7=$(closes_problem "$(printf '%s' "$crow" | cut -f3 | base64 -d)" "$prs")
            if [ -n "$p7" ]; then [ -z "$probs" ] || probs="$probs"$'\n'; probs="$probs$p7"; fi
          fi
        fi
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
    crow=$(printf '%s\n' "$closers" | awk -F'\t' -v n="$n" '!d && $1==n{print; d=1}')
    if [ -z "$crow" ]; then
      printf '?? %-14s#%-3s 問不到這張票的內文，錨點與格 9 不查 — %s\n' "$short" "$n" "$title"
      lunk=$((lunk+1)); continue
    fi
    printf '%s' "$crow" | cut -f3 | base64 -d > "$tmp"
    total=$((total+1))

    # 格 9：做完能展示什麼
    p9=$(demo_problem < "$tmp")
    if [ -n "$p9" ]; then
      printf 'NG %-14s#%-3s %s — %s\n' "$short" "$n" "$p9" "$title"
      b9=$((b9+1))
    fi

    # 錨點段與連結的判法：lib/anchor-links.sh（anchor_section／anchor_parse，與 anchor-overlap.sh 同一份）。
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
    # 有 SHA 連結、又有沒釘 SHA 的檔案連結：那幾條沒被驗（anchor-overlap 對同一張票印 UNKNOWN）。
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
echo "標籤：開著 $lopen 張（格 1～3、5～8）、已關 $lclosed 張（格 2、4），NG $lbad 張，問不到 $lunk 處；別人開的 $lother 張不查"
[ "$bad" -eq 0 ] && [ "$lbad" -eq 0 ] && [ "$b9" -eq 0 ]
