---
name: triage
description: "Triage a ticket that was not planned by us (opened or reported by a colleague or an outsider): read it in full, check whether it is already done, verify the claim, recommend and wait for the owner, and draft the reply in the fixed two-part format. Comments are drafts until the owner explicitly says to send. Use when the user runs /triage with a ticket or pasted ticket text."
disable-model-invocation: true
---

# 分流：處理不是我方規劃開的票

這支只處理**不是我方規劃開的票**：同仁開的、同仁回報的 bug、外來的請求。我方自己規劃的票（SPEC 拆出來的施工票）不經過這支。

## 1. 先讀私有擴充

照 [私有擴充](${CLAUDE_PLUGIN_ROOT}/references/private-extension.md) 的三步讀這支 skill 的補充（skill 名 `triage`）：

1. 用 Bash 跑這一條，整條逐字照抄，不加引號、不接 `||`／`&&`、不改寫成 `echo`、`test` 或其他寫法：`printenv GITHUB_WORKFLOW_PRIVATE_DIR`
   - `printenv` 退出碼 1 且沒有輸出＝未設定；其他情況（被權限擋、工具錯誤、沒跑成）→ 停下告訴擁有者，不當成未設定。
2. 未設定 → 回報「私有擴充：未設定」，照本體做。**不讀任何私有檔。**
3. **有值才讀私有檔**：用 Read 讀 `<值>/triage.md`。
   - 讀到 → 回報「私有擴充：已讀 triage.md」，內容當補充規則，與本體一起遵守。
   - 讀不到 → 停下，告訴擁有者讀不到哪個路徑，不要照本體繼續。

## 2. 動手前先看作者與 repo

- **先看作者**：`gh issue view <票號> -R <owner>/<repo> --json author --jq .author.login`。使用者只貼了票的文字、沒給票號 → 以使用者說的作者為準，說不清楚就問。
- **再看 repo 是誰主導的**：我方主導的 repo，標籤照 [labels.md](${CLAUDE_PLUGIN_ROOT}/references/labels.md)；同仁主導的 repo 不套我方標籤，也不要求對方建我方標籤。

三種票，我方能做的事不一樣：

| 票 | 我方能做什麼 |
|---|---|
| **別人開的票** | **只留言。** 不改內文、不改標籤、不關閉或重開、不掛成我方 SPEC 的子票、不對它加 `blocked-by`（後兩者也會改到對方的票） |
| **我方開在對方 repo 的票** | 只開少數說明票（規則、介面、範例、我方時程）；拆票、排序、改對方設計由對方決定。掛對方的狀態標籤。內文只有擁有者確認後才改；對方要修正一律留言 |
| **要擁有者處理的事** | 開在擁有者的 repo，用跨 repo 子票＋`blocked-by` 與對方 repo 的票串起來。只串我方開的票 |

- 對方那張票的答案在別處 → 在它上面留言連過去，關不關由開票人決定。
- 想請對方改標籤、類型、欄位、指派人或關票 → 送「建議」，不要只留言；內文不在建議的範圍內，改內文仍只留言。送法與限制見 [collaboration.md](${CLAUDE_PLUGIN_ROOT}/skills/triage/references/collaboration.md)。

## 3. 流程

1. **讀全文**：內文、留言、標籤、作者、日期。票上已有先前的分流筆記 → 接著做：先看對方回答了哪些待補的問題，報出更新後的狀況，**已經回答過的不重問**。
2. **先查有沒有做過**：用**概念**搜程式碼（領域名詞、行為），不只搜票上的字面；報出搜了哪裡。已經做好 → 指出在哪裡（檔案與 SHA 固定連結），建議關票。
3. **先驗證說法**：bug 先照對方的步驟重現；附了程式碼的，先 checkout 跑相關測試或指令。報出結果：已重現（附程式路徑）／重現不了／資訊不足以重現（資訊不足是要補資訊的強烈訊號）。
4. **給建議、等決定**：說出建議與理由，附上與這張票有關的程式現況，然後**停下等擁有者決定**。
   - 我方 repo 的票：類型、優先、驗證等級由擁有者定，這裡只提建議。
   - 同仁的票：照第 2 節只留言。
5. **要補資訊**：用下面的固定格式寫草稿。「還需要你提供的」每一條都是對方能直接回答的具體問題（哪個畫面、照什麼步驟、預期與實際各是什麼、錯誤訊息原文、發生時間），**不寫「請提供更多資訊」**。前面幾步已經確認的事全寫進「已經確認的」，不要讓已做的工作消失。
6. **結果**：
   - 不做 → 寫進 SPEC 的「刻意不做的事」再關（SPEC 內文由指揮台改，分流者在 SPEC 留言請它寫入）。
   - 已經做好 → 指出位置。
   - 關票原因用 GitHub 原生的，不用標籤；重複、不處理、資訊不足各怎麼做，照 [labels.md](${CLAUDE_PLUGIN_ROOT}/references/labels.md) 第四節「關票原因：不用標籤」。
   - 以上關票只用在我方的票；別人的票關不關由開票人決定，我方只留言說明。

### 補資訊的固定格式

```markdown
### 已經確認的

- <已經查過、重現過或排除的事，一條一件>

### 還需要你提供的

- @<對方帳號> <具體問題 1>
- @<對方帳號> <具體問題 2>

（AI 代回）
```

## 4. 留言紀律

- AI 代寫的留言，結尾一律標「（AI 代回）」。
- tag 對方用 GitHub 原生的 `@帳號`。
- **留言一律先寫成草稿給擁有者看，擁有者明說「發」才發。**「看起來可以」「已合併」都不算「發」。草稿寫成檔，發的時候走 `gh issue comment <票號> -R <owner>/<repo> --body-file <檔>`。
- 這和交接（`handoff`）不同：交接留言寫給接手的自己人，不必等「發」；分流的留言是對同仁或外部的人說話，一律等「發」。

## 5. 不採用的上游做法

上游的 5 種狀態標籤（待分流、待補資訊、可交給 agent、可交給人、不處理）與 `.out-of-scope/` 存檔資料夾都不採用：狀態與標籤照 [labels.md](${CLAUDE_PLUGIN_ROOT}/references/labels.md)，不做的事記在 SPEC 的「刻意不做的事」。

## 6. 界線

- 同仁的票只留言：不改內文、標籤、狀態，不掛子票、不加 `blocked-by`。
- 沒有擁有者明說「發」，不呼叫任何會寫入 GitHub 的指令（留言、改票、改標籤、關票都算）。
- 分流不施工、不開施工票；要做的事交指揮台開票。
- 界線外的判斷攤出來問擁有者，不要自己決定。
