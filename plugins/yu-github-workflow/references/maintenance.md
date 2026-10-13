# 維護規則

這個 plugin 放在一個公開 fork 的子資料夾裡。fork 的 `main` 是部署線：裝了這個 plugin 的每台機器都從 `main` 自動更新，合併進 `main` 就等於上線，hook 會在下一個對話開始執行。

## 版本號

- 施工分支不改 `.claude-plugin/plugin.json` 的 `version`。
- 開整合 PR（整合分支 → `main`）之前升一次，整批只升這一次。
- 自動更新靠版本號判斷有沒有新版；忘了升，合併後各機器不會更新。

## 跟上游

- 上游的檔案原封不動，當合併來源；這個 plugin 只放改寫過的 skill 與 hook，全部在 `plugins/yu-github-workflow/` 底下。
- 跟上游用 `git fetch upstream` 再 `git merge upstream/main`，不 rebase、不 cherry-pick。
- 預期只有根目錄 `.claude-plugin/marketplace.json` 會衝突（fork 改成列出這個 plugin）。保留 fork 的 `plugins` 清單，其他欄位照上游。
- 其他檔也衝突，代表有人改了上游的檔；先查是誰改的，不要直接選一邊。
- upstream 遠端的推送網址要停用，避免誤推到上游。

## 整合 PR

- 驗證等級一律 `重驗證-外審`：`main` 是所有機器的部署線，hook 會在每個對話執行。整段改動收齊後送換廠牌的外部審查，通過才開 PR。
- 一律用 merge commit 合併，不用 squash、不用 rebase merge。其他地方用 SHA 固定連結指到施工分支的 commit，squash 會讓那些 SHA 不在 `main` 的歷史裡。
- 公開 repo 的 PR 與 commit 訊息不寫私有 repo 的票號，所以不用 `Closes` 關私有票；合併後由開票的人逐張關。
- 合併只由擁有者按。

## 外洩檢查

這是公開 repo，寫進來的檔與 commit 訊息只能有通用規則：不寫私有 repo 名、票號、人名、事件、本機路徑、內部識別字。作者信箱用 GitHub 的 noreply 信箱。

- 推送前有本機 pre-push hook 掃描新增行、commit 訊息與作者信箱，命中就擋。不要用 `--no-verify` 繞過。
- 只有裝了這支 hook 的機器才推 fork。CI 端的同一道掃描上線前，這是唯一一道防線。
- 掃描的關鍵詞清單本身就是私有資料，不放在這個 repo。
- 測試夾具需要像票號的字串時，在執行時組出來（例如 `printf 'Closes #%s' 5`），不要直接寫進檔案。
