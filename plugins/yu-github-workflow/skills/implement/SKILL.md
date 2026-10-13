---
name: implement
description: "Implement exactly one issue-tracker ticket on a branch cut from its integration branch, then hand it off for separate verification. Use when the user runs /implement with a ticket, or when a parallel-implementation conductor tells a subagent to build one ticket."
---

# 實作：一張票做到底

施工者一次只做一張票：從整合分支開分支、照票做完、交件，合併與驗證都由別人做。

## 1. 先讀私有擴充

照 [私有擴充](${CLAUDE_PLUGIN_ROOT}/references/private-extension.md) 的三步讀這支 skill 的補充（skill 名 `implement`）：

1. 用 Bash 跑這一條，整條逐字照抄，不加引號、不接 `||`／`&&`、不改寫成 `echo`、`test` 或其他寫法：`printenv GITHUB_WORKFLOW_PRIVATE_DIR`
   - `printenv` 退出碼 1 且沒有輸出＝未設定；其他情況（被權限擋、工具錯誤、沒跑成）→ 停下告訴擁有者，不當成未設定。
2. 未設定 → 回報「私有擴充：未設定」，照本體做。**不讀任何私有檔。**
3. **有值才讀私有檔**：用 Read 讀 `<值>/implement.md`。
   - 讀到 → 回報「私有擴充：已讀 implement.md」，內容當補充規則，與本體一起遵守。
   - 讀不到 → 停下，告訴擁有者讀不到哪個路徑，不要照本體繼續。

## 2. 沒有票號就問，什麼都不做

- 使用者沒有給票號或票的網址 → **除了第 1 節那一條 `printenv`（有值時加上讀那一個私有檔）之外，不用任何工具**：不讀其他檔、不搜尋、不查 issue 清單、不看或開分支。直接問：「要做哪一張票？」
  - 使用者同時問了一般問題（例如開工前要讀什麼），照本檔與讀到的私有擴充回答，再問票號。
- 票號不清楚（只講名稱、對到多張、repo 不明）→ 問，不要猜。
- 施工中發現這張票一個對話做不完 → 停下回報，請開票的人重切；不要邊做邊拆票。

## 3. 開工

1. **先說出票名**：`gh issue view <票號> -R <owner>/<repo>` 讀票，第一句話報出票名。
2. **說出要從哪條整合分支開**：整合分支寫在票上或它的 SPEC 上。說明「會從整合分支 `<名>` 開分支，不從 main 開」。票與 SPEC 都沒寫整合分支 → 問，不要退回從預設分支開。
3. **掛狀態與機器**：照 repo 設定（`docs/agents/github.md` 的「施工狀態記法」「機器標籤名」），標籤的意思以 [labels.md](${CLAUDE_PLUGIN_ROOT}/references/labels.md) 為準。
   - 記法是狀態標籤：`gh issue edit <票號> -R <owner>/<repo> --add-label <施工中標籤> --add-label <這台的機器標籤>`。
   - 記法是 Project Status：把票的 Status 改成進行中，再掛機器標籤，不掛狀態標籤。
   - 只改狀態與標籤，**不動票的內文**。
4. **從整合分支開分支，一張票一個工作樹**：
   ```bash
   git -C <repo> fetch origin
   git -C <repo> worktree add -b <分支> <工作樹路徑> origin/<整合分支>
   ```
   不用 `gh issue develop` 開（理由見 [read-narrow.md](${CLAUDE_PLUGIN_ROOT}/skills/implement/references/read-narrow.md)「從票開分支」）。

## 4. 讀窄、搜寬

- **讀窄**：只讀票上錨點指到的檔（錨點是 SHA 固定連結）；不為了「了解全貌」整個 repo 讀過。
- **搜寬**：要找引用或同形狀的地方時，搜尋範圍是整個 repo，用 `git grep` 對指定 ref 搜。
- 暫存檔一律放自己的子目錄（以票號與角色命名），不在共用暫存目錄的頂層寫通用檔名；工具與副本放在受測樹外面。
- 指令與坑見 [read-narrow.md](${CLAUDE_PLUGIN_ROOT}/skills/implement/references/read-narrow.md)。

## 5. 寫程式與跑測試

- 照 TDD 寫：有 TDD 類 skill 就用 Skill 工具叫它，在事先講好的接縫上寫測試。
- **測試頻率**：型別檢查與單一測試檔隨時跑；**全套只在這張票做完時跑一次**。
- **資源限制**：
  - 本機同時跑測試最多 2 個（整個機器算，不是每個施工者各 2 個）；輪不到就先讀碼、改碼。
  - 突變只跑票上列出的那幾發；票上沒列就不跑；禁止全量突變。
- **不做施工者自我審查**：不叫 code review 類 skill 審自己的改動。驗證一律另外派人。

## 6. 交件

1. 把整合分支最新的 tip 合進自己的分支：`git fetch origin && git merge origin/<整合分支>`。
2. **在本機跑這個 repo 的 CI 同一套指令**（照 CI workflow 檔裡實際跑的那幾條），把輸出留下來貼在回報。不能在本機跑的那一段，明說哪一段沒跑、為什麼。
3. commit，`git push origin <分支>`（只推自己這一條）。
4. 在票上留言（內文走 `--body-file`）：
   - 改了哪些檔、為什麼；
   - 分支與 HEAD 的完整 SHA（`git rev-parse HEAD` 取，不從短碼補）；
   - 可重跑的驗證指令與實際輸出、第 2 點的本機 CI 輸出；
   - 範圍外的發現（只記下，不改）。
   - 最後一行署名：`— 🔧 施工｜<機器>｜<執行者>｜分支 <分支>`。執行者：自己是對話本身寫 `session <session id 前 8 碼>`；是被派出的子代理寫 `<派它的 session 前 8 碼>／施工子代理`。格式以 labels.md 的署名段為準；「不驗自己的票」就是比對執行者欄。
5. 換狀態：施工中 → 待驗證（狀態標籤記法：`--add-label <待驗證標籤> --remove-label <施工中標籤>`；Project Status 記法改 Status）。換手給另一台時，機器標籤跟著換成接手的那一台。
6. **不開 PR**。合進整合分支由另派的合併者做；整合分支收齊後才開一個 PR。

## 7. 界線

- 不合併進 main（預設分支）、不自己合進整合分支、不部署、不發任何訊息（聊天、郵件、推播都算）。
- 不改票的內文；只在票上留言。
- **施工者不開票**：冒出的新工作記到 SPEC 的「尚未定義」段，並在 SPEC 留言通知開票的人；資安、個資、正式環境壞掉這類不能等的，在 SPEC 留言標 🔴 立刻報。
- 範圍外的發現只回報，不順手改。
- 界線外的判斷（票上寫法與實際不符、要不要多做一件事）攤出來問，不要自己決定。
