# 錨點段的唯一判法：ticket-check.sh 與 anchor-overlap.sh 共用（只給 source 用），不各寫一份。
#   錨點段在哪、哪些連結算錨點、連結怎麼剝結尾、「- 無：<理由>」怎麼認、理由空白怎麼算，都只在這裡判一次。
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
