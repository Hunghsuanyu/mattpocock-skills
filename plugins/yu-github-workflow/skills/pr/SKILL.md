---
name: pr
description: "開 PR、寫 PR 內文。內文是摘要（最小的圖）、證據（一句結論＋連結）、合併風險（Door 與 Blast Radius 由開 PR 的人看實際改動判斷）與連票（Closes／Refs 由開 PR 的人照票判斷）；公開 repo 開 PR 前，標題與內文先遮掉內部名稱與票號。Use only when the GitHub workflow entry skill routes here, or when the user runs /pr."
metadata:
  credits:
    skill: show-me
    author: Dex Horthy
    organisation: Humanlayer
    url: "https://github.com/humanlayer/skills/blob/main/plugins/show-me/skills/show-me/SKILL.md"
---

# PR：一次上線的範圍收齊才開一個

## 1. 先讀私有擴充

照 [私有擴充](${CLAUDE_PLUGIN_ROOT}/references/private-extension.md) 的三步讀這支 skill 的補充（skill 名 `pr`）：

1. 用 Bash 跑這一條，逐字照抄：`printenv GITHUB_WORKFLOW_PRIVATE_DIR`
   - `printenv` 退出碼 1 且沒有輸出＝未設定；其他情況（被權限擋、工具錯誤、沒跑成）→ 停下告訴擁有者，不當成未設定。
2. 輸出是空的（變數沒設）→ 回報「私有擴充：未設定」，照本體做。
3. 有值 → 用 Read 讀 `<值>/pr.md`。
   - 讀到 → 回報「私有擴充：已讀 pr.md」，內容當成補充規則，與本體一起遵守。
   - 讀不到 → 停下告訴擁有者讀不到哪個路徑，**不要照本體繼續**。

補充只能加、不能推翻本體；兩者衝突時把兩句並列給擁有者決定。

## 2. 什麼時候開

- **只有整合分支收齊之後才開**，一次上線的範圍開一個 PR（整合分支 → 預設分支）。每張票不各開 PR，也不提早開草稿 PR。
- 總驗收（`review` 改動模式）通過、每張 `重驗證-外審` 票都留了通過的結論之後才開：同一個 repo 的 PR 會用分支裡的 workflow 跑、拿得到 secret，改到 workflow 的分支要先驗過才能觸發。
- 合併只有擁有者按。**公開 repo 的 PR 按合併時，把 GitHub 預設的 merge commit 標題改成不含分支名的句子**：預設標題帶來源分支名，合併後就留在公開歷史裡（分支命名規則見 [SPEC 範本](${CLAUDE_PLUGIN_ROOT}/skills/to-spec/references/spec-template.md) 第 2 段）。
- 開之前讀 repo 設定 `docs/agents/github.md` 的「特殊禁忌」：不是 `無` → 讀它底下的「特殊禁忌」段，這個 PR 碰到的照著做。

## 3. 內文：每一段都自己寫

不要前言，文字盡量少。私有 repo 的 PR 共四段：

```markdown
## 摘要

<最小的圖>

## 證據

<一句結論>：<連結>

## 合併風險

**Door：** <one-way 或 two-way>——<一句理由>

**Blast Radius：** <一個詞>

<可選：合併後可能的連帶影響>

## 連票

<每張票一行：Closes 或 Refs（第 4 節）>
```

公開 repo 的 PR 共三段：摘要、證據、`## 合併風險`（只留 Door 與 Blast Radius，見下面「合併風險」）。

### 摘要

挑**最小**、能把重點講清楚的一種圖，放在它要支撐的那一兩句話旁邊；只留回答這個 PR「改了什麼」需要的呼叫、檔案、狀態、邊界：

- 邏輯或演算法 → 虛擬碼
- 執行時的呼叫順序 → 呼叫樹
- 介面結構 → 元件樹（含要緊的狀態與模組邊界）
- 檔案分工或大範圍重構 → 淺的檔案樹
- 元件之間的互動、資料流 → Mermaid
- 重點在「改了哪裡」、周圍的形狀本來就在 → `diff` 形狀（對元件樹、檔案樹、呼叫樹或控制流畫前後差異）
- 大部分是新的、或省略上下文會看不出歸屬與順序 → 整段貼出來

通常一種就夠，最多幾種，不要全用。

### 證據

**一句結論＋連結**，不重貼輸出。改動前後的對照最好（畫面類的改動用截圖；其次是測試紅→綠、指令輸出）。

- **私有 repo**：連到票上那則證據留言。
- **公開 repo**：**只連公開的 commit 與 Actions run**。私有票上的證據留言，改由指揮台在私有 SPEC 留言連到這個 PR——只從私有連向公開，不反過來。

### 合併風險

**Door 與 Blast Radius 由你看實際改動判斷**（`git diff origin/main...origin/<整合分支>`），不從標籤推：

- **Door**：寫 one-way 或 two-way，後面接一句理由。two-way 走得回頭：合併後出事，退回這個 PR 就恢復原狀；one-way 退不回：刪除資源、改寫歷史、正式資料搬移、已經對外送出、已經被別人讀走的東西，退回程式也收不回來。PR 越便宜退回，風險越低。
- **有票掛 `重驗證-自檢` 卻判 two-way**：理由要寫明為什麼退得回來（例：這次只改讀取端、正式資料沒動），不能只寫「two-way」。
- **Blast Radius**：一個詞，寫這次改動可能波及的範圍；把可能性都想過（例：版面、下游呼叫端、行動版、部署線）。需要時下面再加一兩句合併後可能的連帶影響。

**逐票看過再寫**：每張票的驗證標籤（判準是 [labels.md](${CLAUDE_PLUGIN_ROOT}/references/labels.md) 第一節③）；`重驗證-外審` 的票上有沒有總驗收留下的通過結論（`review` 第 3.6 節）——沒有就先補齊，不開 PR。

- **公開 repo 的 PR**：只寫 `## 合併風險` 標題與 Door、Blast Radius；逐票的事實與外審結論連結含私有 repo 名與票號，不寫進 PR，改由指揮台貼在私有 SPEC 的留言。Door 的理由與 Blast Radius 一樣不寫私有 repo 名與票號。

## 4. 連票：`Closes`／`Refs`

- **私有 repo 的整合 PR**：`## 連票` 段列出全部票，由你逐張讀票決定：票上有「合併後／部署後」的步驟 → `Refs`（合併時不關票，擁有者的步驟做完後由指揮台關）；沒有 → `Closes`。
- **`Closes` 不可以包在反引號裡**：包了會變成程式碼片段，GitHub 不登記、合併時票安靜地不關。細節與驗法見 [closes-keyword.md](${CLAUDE_PLUGIN_ROOT}/skills/pr/references/closes-keyword.md)。
- 跨 repo 寫 `Closes <owner>/<repo>#<票號>`。
- **公開 repo 的 PR 不得提到私有 repo 名與票號**：不寫 `Closes`／`Refs`。合併後由指揮台逐張關票。

## 5. 開 PR

先把標題與內文各寫成一個檔（`<<'EOF'` 有引號的 heredoc）。

- **公開 repo**：開之前把標題與內文讀一遍，**遮掉內部名稱與票號**——私有 repo 名、私有票號（各種寫法：`#數字`、`owner/repo#數字`、票的網址）、人名、本機路徑，連公開上游的票號也不寫。有私有擴充時，再把「標題＋換行＋內文」交給私有目錄的 `pr-scan.sh` 掃一次，沒過不開（介面見 [私有擴充](${CLAUDE_PLUGIN_ROOT}/references/private-extension.md)）。沒過就改內文，不改掃描器。設了私有擴充、目錄裡卻沒有 `pr-scan.sh` → 不開，告訴擁有者缺哪個檔（`<私有目錄>/pr-scan.sh`）。
- 然後開：

```bash
gh pr create -R <owner>/<repo> --base <base> --head <head> --title "$(cat <標題檔>)" --body-file <內文檔>
```

- repo 有在 PR 開啟／編輯時掃標題與內文的 CI 時，那是補網：漏了是公開之後才報紅，PR 的編輯紀錄仍看得到原文，所以開之前那一遍不能省。

## 6. 開完回查

私有 repo 寫了 `Closes` 的，回查有沒有登記成功，不看 PR 頁面的外觀：

```bash
gh pr view <PR 號> -R <owner>/<repo> --json closingIssuesReferences --jq '[.closingIssuesReferences[].number]'
```

空陣列＝沒登記。對照組：拿一個已知有登記的 PR 跑同一條，確認它回得出號碼。

## 7. 狀態與關票

- **開 PR 的人掛等待擁有者的標籤**（標籤名由 repo 設定給；判準見 labels.md 第一節④）。
- **合併後**：`Closes` 的票自動關。`Refs` 的票一律由**指揮台**關：擁有者的步驟做完、貼回實測，指揮台確認票上的 `K` 檢核與收尾項都做完就關，不請擁有者按。
- **關票後拿掉狀態標籤與機器標籤**，留類型、優先、驗證三組；有 `衍生` 的照留（labels.md 第一節④⑤、第二節）。由看到合併的那一方做。
- 不是做完的關票（重複、不處理、資訊不足）照 labels.md 第四節。
