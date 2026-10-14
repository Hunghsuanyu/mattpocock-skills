---
name: pr
description: "開 PR、寫 PR 內文。內文是摘要（最小的圖）、證據（一句結論＋連結）、合併風險（Door 與 Blast Radius 由開 PR 的人看實際改動判斷，下面接 scripts/pr-risk.sh 列出的逐票事實與連票）；開 PR 一律經 scripts/pr-open.sh（公開 repo 開前開後各掃一次）。Use only when the GitHub workflow entry skill routes here, or when the user runs /pr."
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

## 3. 內文：三段自己寫，逐票事實與連票貼 `pr-risk.sh` 的輸出

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

<pr-risk.sh 的整份輸出：逐票事實 …… ## 連票 ……>
```

`## 合併風險` 標題、Door、Blast Radius 由你寫；`pr-risk.sh` 的輸出原樣接在後面（它不印這個標題）。

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

**逐票事實跑腳本帶出**：

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/pr-risk.sh" <owner/repo> <整合分支裡全部的票號…>
```

- 它讀每張票的驗證標籤、內文與留言（只讀），不判門，只列事實：每張票的驗證標籤、`重驗證-外審` 的外審結論（有／無／不通過，附留言連結）、有沒有合併後的步驟，以及「連票」段。驗證標籤的判準是 [labels.md](${CLAUDE_PLUGIN_ROOT}/references/labels.md) 第一節③；外審結論是總驗收的 session 留在每張外審票上的那則（`review` 第 3.6 節）。
- **退出碼 2＝有票讀不到**，什麼都沒印——**不可以當成沒有風險**，修好讀取再跑。
- **退出碼 3＝有票不齊**：有票沒掛驗證標籤，或 `重驗證-外審` 的票外審結論缺席、不是通過 → **先補齊，不開 PR**。退出碼 0 才往下走。
- **退出碼 64＝參數錯**。
- **公開 repo 的 PR**：只寫 `## 合併風險` 標題與 Door、Blast Radius；`pr-risk.sh` 的輸出（逐票事實、外審結論連結、`## 連票` 段）含私有 repo 名與票號，不貼，改由指揮台貼在私有 SPEC 的留言。Door 的理由與 Blast Radius 一樣不寫私有 repo 名與票號。

## 4. 連票：`Closes`／`Refs`

- **私有 repo 的整合 PR**：內文列出全部票，就是第 3 節貼進去的 `pr-risk.sh` 輸出裡的 `## 連票` 段，不另寫一份。它照票上有沒有「合併後／部署後」的步驟決定：有 → `Refs`（合併時不關票，擁有者的步驟做完後由指揮台關）；沒有 → `Closes`。
- **`Closes` 不可以包在反引號裡**：包了會變成程式碼片段，GitHub 不登記、合併時票安靜地不關。細節與驗法見 [closes-keyword.md](${CLAUDE_PLUGIN_ROOT}/skills/pr/references/closes-keyword.md)。
- 跨 repo 寫 `Closes <owner>/<repo>#<票號>`。
- **公開 repo 的 PR 不得提到私有 repo 名與票號**：不寫 `Closes`／`Refs`。合併後由指揮台逐張關票。

## 5. 開 PR：一律經 `pr-open.sh`

先把標題與內文各寫成一個檔（`<<'EOF'` 有引號的 heredoc），然後：

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/pr-open.sh" <owner/repo> <base> <head> <標題檔> <內文檔>
```

- 它先讀 repo 可見度：私有 → 不掃、直接開；**公開，或讀不到可見度** → 開之前掃一次標題＋內文，開完讀回再掃一次。
- 掃描器：**內建檢查一律跑**，擋票號的各種寫法：`owner/repo`＋井號＋數字、短名＋井號＋數字、裸的「井號＋數字」、全形井號＋數字、`GH-<數字>`（不分大小寫）、`github.com/<owner>/<repo>/(issues|pull)/<數字>` 網址；公開上游的票號也會被擋，照樣不寫。有私有擴充時，內建檢查過了再跑那個目錄裡的 `pr-scan.sh`——**私有掃描只加不取代**，兩個都過才開（有私有擴充卻沒有這個檔 → 不開）。介面見 [私有擴充](${CLAUDE_PLUGIN_ROOT}/references/private-extension.md)。
- 退出碼：`0` 開好了，印 PR 網址；`1` 沒開，或開了但讀回失敗、讀回沒過——印出的網址交擁有者處理；`64` 參數錯。
- **不要直接跑 `gh pr create`**，也不要為了過掃描去改掃描器；沒過就改內文。

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
