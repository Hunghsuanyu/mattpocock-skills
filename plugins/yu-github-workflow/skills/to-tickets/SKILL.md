---
name: to-tickets
description: "Split an existing SPEC issue into tracer-bullet build tickets: one fresh context each, every ticket with a demo statement, SHA-pinned anchors, K/H checks and three label groups, ordered only by native blocked-by edges, all blocked by the SPEC's external-review ticket. Before publishing, shows the owner a table of which files each ticket will touch and asks about ordering; finishes by running the ticket self-check on this batch's ticket numbers, and a non-zero exit means the batch is not done. Use when the GitHub workflow entry skill routes here, or when the user runs /to-tickets with a SPEC."
---

# 拆票：把一張 SPEC 切成施工票

輸入是一張已經寫好的 SPEC（`to-spec` 開的）。輸出是一批施工票：每張一個對話做得完、做完能展示、先後只用原生 `blocked-by` 表達，全部被 SPEC 的 `[外審]` 票擋住。**計畫就是這批施工票本身**，不另寫計畫檔。

切法不拿給擁有者逐張確認，改由三個補位把關（第 4 節）；其中只有「每張票會動到哪些檔」列成一張表給擁有者看、問先後。業務上的先後在寫 SPEC 時就問過了。

## 1. 先讀私有擴充

照 [私有擴充](${CLAUDE_PLUGIN_ROOT}/references/private-extension.md) 的三步讀這支 skill 的補充（skill 名 `to-tickets`）：

1. 用 Bash 跑這一條，整條逐字照抄，不加引號、不接 `||`／`&&`、不改寫成 `echo`、`test` 或其他寫法：`printenv GITHUB_WORKFLOW_PRIVATE_DIR`
   - `printenv` 退出碼 1 且沒有輸出＝未設定；其他情況（被權限擋、工具錯誤、沒跑成）→ 停下告訴擁有者，不當成未設定。
2. 未設定 → 回報「私有擴充：未設定」，照本體做。**不讀任何私有檔。**
3. **有值才讀私有檔**：用 Read 讀 `<值>/to-tickets.md`。
   - 讀到 → 回報「私有擴充：已讀 to-tickets.md」，內容當補充規則，與本體一起遵守。
   - 讀不到 → 停下，告訴擁有者讀不到哪個路徑，不要照本體繼續。

## 2. 讀來源與現況

1. **讀 SPEC 全文與全部留言**：`gh issue view <SPEC 號> -R <owner/repo> --comments`。已經做的決定、尚未定義、刻意不做的事都要讀到；留言裡後來拍板的決定蓋過內文的舊寫法。
2. **讀 repo 設定** `docs/agents/github.md`：票開在哪個 repo、施工狀態記法。沒有這個檔＝還沒導入，先走 `setup`。整合分支的名稱**只從 SPEC 第 2 段「範圍」讀**（名字的唯一來源，見 [SPEC 範本](${CLAUDE_PLUGIN_ROOT}/skills/to-spec/references/spec-template.md) 第 2 段）。SPEC 沒寫、或第 3 節切出了 SPEC 沒列的整合分支 → 照範本的命名規則擬好名字，先寫進 SPEC 第 2 段再開票：這個對話是指揮台就自己改 SPEC 內文；不是就在 SPEC 留言列出名字，等指揮台寫進內文後才開票。不在票上自己取名。
3. **先查這件事是不是已經有分支做了**——`main` 上沒有，不等於沒人做過：做完在分支上等合併，與沒人做過，在 `main` 上長得一模一樣。

   ```bash
   git -C <clone> fetch origin && git -C <clone> branch -r
   git -C <clone> diff --stat origin/main...origin/<看起來相關的分支>
   ```

   有重疊 → 停下告訴擁有者是哪條分支、重疊哪些檔，不要照樣開票。
4. 只讀這批票會碰到的檔，取得錨點與數字。**每個數字標「量於哪顆 SHA、用哪條指令」**；沒有當場重量的不要寫，改寫成「去量，指令是 X」。

## 3. 切法

- **先整理再改**：需要先重構才好改的，重構排第一張（先讓改動變容易，再做容易的改動）。
- **縱切**：每張打通一條窄但完整的路徑（資料、介面、測試都走過），做完就能展示或驗證；不切成「只做某一層」的橫片。
- **一張一個對話做得完**。做不完的再切。
- **大範圍的機械改動**（改名、換型別，一次改會同時弄壞大量呼叫點）不硬切縱片，改走「先加 → 再搬 → 後刪」：先加新形式與舊的並存；再分批搬呼叫點，每批一張、被「先加」擋；最後刪舊形式，被每一批搬遷擋。
- **整合分支歸屬**：一個「一次上線的範圍」一條整合分支（分批切換每批一條；跨 repo 每個 repo 一條）。每張票寫明屬於哪一條，名字照抄 SPEC 第 2 段。一次上線的範圍不要切太大——出事要整批退。**跨整合分支的擋**＝要先上線前一批，在票上特別標出。

## 4. 不逐張給擁有者看切法，改由三個補位把關

1. **碰同一批檔的票合成一張**：兩張票要讀懂的是同一份 context（同一個模組、同一支腳本、同一條機制）→ 合成一張依序做完，不拆成兩張各派一軌。拆開的代價幾乎全在重建 context：第二軌從零重讀一樣的東西。界線：跨 repo、中間要等擁有者合併的兩步合不了，用 `blocked-by` 排先後。
   - **開票前把「每張票會動到哪些檔」列成一張表給擁有者看、問先後**（一列一張票、一欄列它的錨點檔）：兩張票會動到同一個檔時，擁有者決定要合成一張、設 `blocked-by`，還是照樣並行。照樣並行的撞檔交給合併時處理（以合併衝突現形，由合併的人解），不另做機械檢查。
2. **外審逐條驗擋的關係**：SPEC 的 `[外審]` 票，檢查清單要寫明「逐條驗每張票的 `blocked-by` 對不對、有沒有漏」。送審時附上每張票的 `blocked_by` 讀回結果（審查方只讀得到票文，讀不到原生關係）。
3. **「做完能展示什麼」必填**：空白或沒有這段，開票自檢（`ticket-check.sh` 格 9）判紅。

## 5. 每張票的內容

寫法細節與踩過的坑在 [ticket-writing.md](${CLAUDE_PLUGIN_ROOT}/skills/to-tickets/references/ticket-writing.md)，動筆前先 Read 它。

- **第一行**：`依 #<SPEC 號> 設計`（照 SPEC 拆出來的是計畫內的工作，不掛 `衍生`）。
- **屬於哪一條整合分支**（照抄 SPEC 第 2 段的名字）；跨整合分支的擋特別標出。
- **`## 做完能展示什麼`**：一兩句，做完之後拿什麼給人看。必填。
- **`## 錨點`**：SHA 固定連結（`https://github.com/<o>/<r>/blob/<40 碼 SHA>/<路徑>#L10-L20`，`.md` 加 `?plain=1`）。40 碼 SHA 一律 `git rev-parse <ref>` 取，**不准從短碼往後補**。錨點列出這張票會改、會讀的每一個檔——第 4 節那張「每張票會動到哪些檔」的表從這裡列。
  - **只有做完不改任何檔的票**（例：只做決定、只開下一批票、只在 repo 外操作）可以在錨點段寫一行 `- 無：<理由>`；**要讀程式碼的票照寫真錨點**，就算不改檔。沒有錨點段照樣判紅。細節見 ticket-writing.md 第二節。
- **`## 待辦`**：要做的事，一條一件。
- **`## 檢核`**：每一列分 `K`（機械）與 `H`（人工），不混在同一列。`K` 的指令與對照組放程式碼區塊、不放表格格子。測試還沒寫的票，開票時就把測試檔名與函式名訂死，寫明「開工前先跑一次，應該是紅的」。
- **`## 完成定義`**：只引用 `K`；`H` 另列。
- **開工前置不是檢核項**：沒過就不該開始做的，寫在票首或獨立的開工前置段；做完才驗得了的，才進檢核。
- **散文裡不寫「前置：#N」**：先後只放原生 `blocked-by`（第 6 節）。施工者看網頁的 Blocked by 欄或讀 `issues/<N>/dependencies/blocked_by`。
- 散文裡不寫行號，寫可重跑的定位指令；錨點連結綁 SHA，不會漂。
- 雙方要互相配合的票（一方先做、另一方配合）加 `## 與對方的配合` 段與一條留言檢查的 `K`（寫法見 ticket-writing.md）。
- 給擁有者看的地方講票用名稱、號碼做成連結；給機器的（`blocked-by`、指令參數）用號碼。

## 6. 擋的關係與標籤

- **開票時就逐對檢查**，不只設邏輯先後：同一份共用設定、或有語意上的先後 → 設 `blocked-by`；只改到同一個檔 → 照第 4 節那張表由擁有者決定；只共用部署線 → 不設；判斷不出來 → 設。判準表在 ticket-writing.md。
- **只設原生 `blocked-by`**：`gh issue edit <N> --add-blocked-by <M>`（跨 repo 走 API，見 `setup` 的指令表）。
- **每開一張施工票，就把它補設成被 SPEC 的 `[外審]` 票擋**（`--add-blocked-by <外審票號>`）。外審票是開 SPEC 時 `to-spec` 開的；外審票沒關，沒有人開得了工。
- **掛成 SPEC 的子票**（`--parent <SPEC 號>`）。
- **標籤**：照 [labels.md](${CLAUDE_PLUGIN_ROOT}/references/labels.md) 第七節的票種表，施工票掛類型、優先、驗證各一個。狀態與機器開票時不掛，由領票的人掛。
- 開票順序：被擋的放後面開，讓 `blocked-by` 指得到真的票號。

## 7. 開完先自檢，回 0 才算開完

在本機只對**這一批**的票號跑一次（repo 裡其他舊票的紅不算在這一批，也不擋這一批）：

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-check.sh <owner/repo> <這批票號…>
```

- 給了票號就只查那幾張；錨點段、SHA 存在、標籤格 1、2、6、做完能展示什麼（格 9）。退出碼 1 ＝還沒開完，照 NG 行修好再跑。各格意思見 [ticket-check.md](${CLAUDE_PLUGIN_ROOT}/references/ticket-check.md)。
- 本機這一次帶的是擁有者自己的權限：錨點指到別的私有 repo 的 SHA 也驗得到。repo 裝了開票自檢 workflow（`setup` 問過）時，Actions 在票開出時另跑一次、結果留言在票上；那是補網，不取代本機這一次——它的 token 只讀得到自己這個 repo。
- 不是 0 → 停下，不回報「開完了」。

## 8. 施工中冒出的新工作（指揮台做決定時處理）

- **施工者不開票、不改 SPEC 內文**：冒出的新工作在 SPEC **留言**，由指揮台寫進「尚未定義」段；指揮台在做決定時統一處理（要做的開票、不做的寫進「刻意不做的事」）。
- **不能等的當場開**：資安、個資、正式環境壞掉 → SPEC 留言標 🔴，指揮台當場開票。
- **併回原票的門檻**：同一個 repo、改動少於約 30 行、驗證等級不高於原票 → 在原票留言、併進原票的改動，不另開票。
- **其餘開成衍生票**（只限計畫外冒出的）：掛 `衍生`、直接掛 SPEC（不掛原票底下：SPEC 的進度、閘門只看直接子票）、第一行寫 `從 #<原票號> 衍生`、在原票留言連結、掛齊三組標籤。
- **衍生票排在它真正會影響的那一步**：不做會影響下一步才現在做；否則設成「真正受影響那張票」的 `blocked-by`，輪到時才做。方向不一定是原票擋它。
- 開完一樣跑第 7 節的 `ticket-check.sh`，只給這次新開的衍生票。衍生票會動到的檔和同一個 SPEC 底下還開著的施工票重疊時，在 SPEC 留言列出來，由指揮台決定要不要設 `blocked-by`。

## 9. 交回

回報這批票的名稱（號碼做成連結）、各自屬於哪條整合分支、擋的關係（讀回 `blocked_by`）、第 4 節那張「每張票會動到哪些檔」的表與擁有者的回答，以及第 7 節 `ticket-check.sh` 的退出碼與最後幾行輸出。下一步：外審票（`review`），外審關了才開工（`implement` 或 `implement-spec`）。

## 10. 界線

- 只開施工票、設擋、掛子票；不改 SPEC 內文（SPEC 內文只有指揮台改；這個對話就是指揮台時，只補第 2 段的整合分支名）、不施工。
- 不改別人的票；不對外送出任何訊息。
- 施工票開出來之後，內文只有指揮台改；唯一例外是外審票開著期間的那一軌外審。
