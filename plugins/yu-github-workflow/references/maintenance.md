# 維護規則

這個 plugin 放在一個公開 fork 的子資料夾裡。fork 的 `main` 是部署線：裝了這個 plugin 的每台機器都從 `main` 自動更新，合併進 `main` 就等於上線：下一個對話載入的 skill 與腳本就是新的。

## 版本號

- 施工分支不改 `.claude-plugin/plugin.json` 的 `version`。
- 開整合 PR（整合分支 → `main`）之前升一次，整批只升這一次。
- 自動更新靠版本號判斷有沒有新版；忘了升，合併後各機器不會更新。

## 部署面：開票自檢 workflow 也跟 `main`

- 各 repo 裝的開票自檢 workflow 用 `ref: main` 取這個 fork，每次開票都跑 `main` 當下的腳本，不經版本號、不等 autoUpdate。
- 裝在私有 repo 時，等於 fork `main` 的每一次推送都拿得到那支 workflow 的 token：`contents: read` 讀得到那個 repo 的原始碼，`issues: write` 改得了票。`persist-credentials: false` 只讓 checkout 不把憑證留在 git 設定裡，擋不到 env 裡的 `GH_TOKEN`。
- 所以推 fork `main` 之前的審查，同時保護所有裝了這支 workflow 的 repo。

## 跟上游

- 上游的檔案原封不動，當合併來源；這個 plugin 只放改寫過的 skill 與它們用到的腳本，全部在 `plugins/yu-github-workflow/` 底下。
- 跟上游用 `git fetch upstream` 再 `git merge upstream/main`，不 rebase、不 cherry-pick。
- 預期只有根目錄 `.claude-plugin/marketplace.json` 會衝突（fork 改成列出這個 plugin）。保留 fork 的 `plugins` 清單，其他欄位照上游。
- 其他檔也衝突，代表有人改了上游的檔；先查是誰改的，不要直接選一邊。
- upstream 遠端的推送網址要停用，避免誤推到上游。

## 整合 PR

- 驗證等級一律 `重驗證-外審`：`main` 是所有機器的部署線，合併即經 autoUpdate 上線。整段改動收齊後送換廠牌的外部審查（做不到時照 `review` 第 4 節的替代做法），通過、外審結論留在票上之後才開 PR。
- 一律用 merge commit 合併，不用 squash、不用 rebase merge。其他地方用 SHA 固定連結指到施工分支的 commit，squash 會讓那些 SHA 不在 `main` 的歷史裡。
- 公開 repo 的 PR 與 commit 訊息不寫私有 repo 的票號，所以不用 `Closes` 關私有票；合併後由指揮台逐張關。
- 合併只由擁有者按。按合併時，把 GitHub 預設的 merge commit 標題改成不含分支名的句子：預設標題帶來源分支名，合併後就留在公開歷史裡（分支命名規則見 `to-spec` 的 SPEC 範本第 2 段）。

## 外洩檢查

這是公開 repo，寫進來的檔與 commit 訊息只能有通用規則：不寫私有 repo 名、票號、人名、事件、本機路徑、內部識別字。作者信箱用 GitHub 的 noreply 信箱。

- **merge commit 訊息不帶分支名**：合施工分支、整合分支的 `git merge` 一律帶 `-m "<不含分支名、票號的英文訊息>"`（跟上游的 `git merge upstream/main` 預設訊息只有上游的分支名，不在此限）。git 預設的訊息是 `Merge branch '<分支>' into <分支>`，會把兩邊的分支名寫進公開歷史；分支名照規則不帶私有票號（SPEC 範本第 2 段），但取名漏了一次，預設訊息就會把票號留在公開歷史裡、事後改不掉，所以訊息一律自己寫。施工者合整合分支（`implement` 第 6 節）、合併子代理合進整合分支（`implement-spec` 第 5 節）都照這條。
- 推送前有本機 pre-push hook 掃描新增行、commit 訊息與作者信箱，命中就擋。不要用 `--no-verify` 繞過。
- 只有裝了這支 hook 的機器才推 fork。
- CI 端另有 `leak-scan` workflow（`.github/workflows/leak-scan.yml`），push 與 PR 都掃新增內容；關鍵詞清單放在 repo secret。它在推送**之後**才跑，命中時內容已經公開，只能事後偵測、補救；推送前擋下仍只靠本機 hook。
- 掃描的關鍵詞清單本身就是私有資料，不放在這個 repo。
- 測試夾具需要像票號的字串時，在執行時組出來（例如 `printf 'Closes #%s' 5`），不要直接寫進檔案。
