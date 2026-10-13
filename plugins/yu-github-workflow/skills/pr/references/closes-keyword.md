# `Closes` 包在反引號裡 ⇒ GitHub 不登記，而且沒有任何錯誤訊息

PR 內文把 `Closes <票>` 寫在反引號裡（變成程式碼片段），GitHub 不會把它當成關票關鍵字：`closingIssuesReferences` 是空的，PR 合併時**票不會關**，而 PR 頁面看起來跟寫對了一樣。拿掉反引號才成立。

## 跟「內文走 `--body-file`」是兩件事

| | 防的是什麼 | 症狀 |
|---|---|---|
| 內文走 `--body-file` | 反引號在 `--body "…"` 裡被 shell 當成命令替換執行 | 內文變成指令輸出，看得見 |
| 本條 | 反引號在 markdown 裡把關鍵字變成程式碼片段 | 票安靜地不關，看不見 |

走了 `--body-file` 不代表這一條安全：那條解決的是 shell，這條是 markdown。

## 驗法：開完回查，不看頁面外觀

```bash
gh pr view <PR 號> -R <owner>/<repo> --json closingIssuesReferences --jq '[.closingIssuesReferences[].number]'
```

- 空陣列＝沒登記成功。
- 對照組：拿一個已知有登記的 PR 跑同一條，確認它回得出號碼——沒有對照，空陣列也可能是指令本身寫錯。
- 關鍵字只在**合併進預設分支**時生效；合進其他分支不會關票。

## 跨 repo 與跨可見性

- 跨 repo 寫 `Closes <owner>/<repo>#<票號>`，登記與合併時自動關票都成立，跨 owner、跨可見性（公開 PR 關私有票）也成立。
- **代價**：公開 PR 的內文會出現私有 repo 的名字與票號（只有名字與號碼，沒有內容）。所以公開 repo 的 PR 不寫私有票，改由指揮台在私有那邊連過來、合併後逐張關票（見 `pr` 本體第 4 節）。
- 從票上用 `gh issue develop` 開的分支，本身就連到那張票：這條分支開的 PR 一合併就關票，內文寫 `Refs` 也擋不住。一張票要多個 PR、或合併後還有步驟時，不要這樣開分支。
