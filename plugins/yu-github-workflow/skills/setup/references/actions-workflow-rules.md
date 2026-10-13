# GitHub Actions workflow 規範

寫或改任何 workflow 都照這六條，不分 repo、不分方案。某個 repo 有例外，寫進它的 repo 設定「特殊禁忌」，不改這份。

## 六條

1. **每個 job 都有 `timeout-minutes`**。預設是 360 分鐘，一次卡住就吃掉大量額度。數值取近期最長實測 × 約 3，**下限 5 分鐘**（小守門只跑十幾秒，× 3 只有 1 分鐘，會把網路抖動變成紅叉）；註解寫依據。
2. **`concurrency`**：`pull_request` 觸發的以 PR 為單位 `cancel-in-progress: true`；push 進 main 的不取消；**部署類排隊、不取消**（`cancel-in-progress: false`，否則兩次合併靠太近會兩個部署同時跑、互相覆蓋）。
3. **`paths` 過濾**：`pull_request`／`push` 觸發的檢查只在相關檔變動時跑。刻意每次都跑的，在 `on:` 附近寫**獨立一行** `# paths: 刻意不過濾——<理由>`：只認整行（行尾註解不算）、一定要有理由、不可以是沒填的 `<…>` 佔位符。公開 repo 免這條（不計額度）。
4. **不做**：部署改手動（分鐘不變、失去合併即上線）、`[skip ci]`（會連部署一起跳過）、沒有要裝的相依時為了省分鐘加快取。
5. **測試只在 PR 跑，合併進 main 不重跑**：測試類 workflow 不收 `push` 到 main；部署 workflow 裡含的測試照跑（例如「紅燈不部署」）。
   - 前提：**有「main 必須走 PR」的 repo 都開「合併前必須跟上 main」**（repo 層 ruleset），合併進去的就是 PR 上測過的那一份。
   - 這條 ruleset 要綁一支**每張 PR 都跑、沒有 `paths` 過濾**的 check：不綁 check 的「跟上 main」設定會被接受、卻不生效；有 `paths` 過濾的 check 設成必要，沒改到那些檔的 PR 會永遠等不到它。驗行為，不驗設定值。
   - 沒有「必須走 PR」、直推 main 就發布的 repo，保留合併後測試，寫進它的「特殊禁忌」。
   - 沒有「必須走 PR」的不部署 repo 也拿掉 `push` 到 main 的測試，代價是落後 main 的合併結果沒人測。
   - 判斷「合併即部署」時，部署路徑要列**全集**：workflow、Pages、外部服務接在 main 上的建置觸發（例如雲端平台的 Git 整合）。漏一條就會把部署 repo 當成不部署 repo。
6. **同一個 workflow 裡只跑幾秒的檢查，寫成同一個 job 的多個步驟**，不要拆成多個 job：每個 job 無條件進位 1 分鐘。

## 為什麼這樣省

- Actions **每個 job 無條件進位到 1 分鐘計費**。錢通常是被「次數 × 進位」吃掉，不是單次跑太久：只跑 5 秒的小守門也算 1 分鐘。
- 額度用完時，job 是 **not started**（steps 是 0），不是紅燈；要看 annotation 才知道。
- 查組織用量：`gh api /organizations/<org>/settings/billing/usage`（舊端點 `/orgs/<org>/settings/billing/actions` 回 410）。

## 強制點

- 有私有擴充就照它跑每日稽核（稽核腳本與它的位置在私有擴充，不在這個 plugin）。
- 沒有私有擴充的，寫或改 workflow 時逐條對照這六條。
