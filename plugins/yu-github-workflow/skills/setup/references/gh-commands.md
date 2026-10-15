# GitHub 指令表

這套流程用到的 `gh` 指令與實測過的坑。各 repo 不抄這份，要用時來這裡查。`<o>/<r>` 是 owner／repo，`<N>`、`<M>` 是票號。

標「未實測」的先測再用、附對照組；寫著「不能用」的限制也會變，要用之前重跑一次。

## 採用的功能

| 功能 | 怎麼用 | 指令 | 實測與坑 |
|---|---|---|---|
| **原生相依** | 前置票 | 同 repo：`gh issue edit <N> -R <o>/<r> --add-blocked-by <M>`；拿掉用 `--remove-blocked-by`。<br>🔴 **跨 repo 要走 API**：`gh api -X POST repos/<o>/<r>/issues/<N>/dependencies/blocked_by -F issue_id=<全域 id>`（id 用 `gh api repos/<o>/<r>/issues/<M> --jq .id` 取，**不是票號**） | `gh issue edit` 吃不了 `owner/repo#N`，回 `invalid issue format`；走 API 成功，回讀 `/dependencies/blocked_by` 看得到跨 repo 的前置。⬛ 對照：同 repo 用 `gh issue edit` 成功 ⇒ 失敗的原因是跨 repo，不是指令壞了 |
| **查可開工的票** | 取代手寫佇列表 | `gh api "repos/<o>/<r>/issues?state=open&per_page=100" --paginate --jq '.[]\|select(.issue_dependencies_summary.blocked_by==0)\|"#\(.number) \(.title)"'` | `blocked_by` 只算**開著**的前置（被已關的票擋回 `0`；⬛ 被開著的票擋回 `1`），跨 repo 的開著前置也算進去。🔴 **`issue_dependencies_summary` 是非同步的**：掛上前置後立刻讀回 `0`、拆除後立刻仍讀回舊值；`/dependencies/blocked_by` 清單端點當下就正確 ⇒ 設完相依要驗，改讀清單端點，或隔一次再讀 summary。⬛ `total_blocked_by` 算**全部**前置、含已關的，拿它查可開工會把做完的前置也當成擋著。`--paginate` 別漏（不加只看得到最近 100 張） |
| **查某票被誰擋** | — | `gh api repos/<o>/<r>/issues/<N>/dependencies/blocked_by --jq '[.[]\|"\(.number):\(.state)"]'` | 回 `["3:closed"]` 這個形狀 |
| **子票＝總表** | SPEC 當父票 | 同 repo：`gh issue edit <SPEC> -R <o>/<r> --add-sub-issue <N>`。<br>🔴 **跨 repo 要走 API**：`gh api -X POST repos/<o>/<r>/issues/<SPEC>/sub_issues -F sub_issue_id=<全域 id>`。<br>進度 `gh api repos/<o>/<r>/issues/<SPEC> --jq .sub_issues_summary`；列子票 `… /sub_issues --jq '[.[]\|"\(.repository.name)#\(.number)"]'` | `--add-sub-issue` 同樣吃不了 `owner/repo#N`；走 API 成功，一張 SPEC 掛得了多個 repo 的票 |
| **開票時直接掛成子票** | `to-spec`、`to-tickets`、`wayfinder` 開子票用 | `gh issue create -R <o>/<r> --parent <SPEC 號> --title … --body-file …`（`--parent` 也收票的網址） | 出處：GitHub CLI 手冊 [`gh issue create`](https://cli.github.com/manual/gh_issue_create) 的 `--parent <number>`：「Add the new issue as a sub-issue of the specified parent number or URL」。**未實測**：舊版 `gh` 沒有這個旗標，先跑 `gh issue create --help` 確認有；開完用上一列的「列子票」讀回，確認掛上了（⬛ 對照：讀一張沒掛子票的票回空陣列）。跨 repo 給網址行不行也未實測，不行就照上一列走 API |
| **標籤** | 清單與判準見 [標籤規則](${CLAUDE_PLUGIN_ROOT}/references/labels.md)；新 repo 建標籤照標籤規則第八節用 `gh label create` 建缺的 | 掛：`gh issue edit <N> --add-label <名>`；換：`--add-label <新> --remove-label <舊>`。🔴 **數票要走 API**：`gh api "repos/<o>/<r>/issues?state=all&labels=<urlencode 後的標籤>" --paginate` | ⚠️ `gh issue list --label` 走搜尋索引，**標籤改名後會暫時回 0**（實測：實際幾十張的標籤讀成 0） |
| **Project** | 用 `project` 記法的 repo 換狀態 | 讀 ID：`env -u GH_TOKEN gh project list --owner <o> --format json --jq '.projects[]\|{number,title,id}'`；`env -u GH_TOKEN gh project field-list <號碼> --owner <o> --format json --jq '.fields[]\|select(.name=="Status")\|{id,options:[.options[]\|"\(.name)=\(.id)"]}'`。<br>換狀態：`env -u GH_TOKEN gh project item-edit --project-id <Project ID> --id <item id> --field-id <Status 欄位 ID> --single-select-option-id <選項 id>`（item id 從票查 `projectItems`）。網頁上直接拖也可以 | 🔴 **環境變數裡的 `GH_TOKEN` 沒有 project 權限時**，回 `missing required scopes [read:project]`；`env -u GH_TOKEN` 改用 keyring 登入就讀得到（讀 ID 那兩條實測：⬛ 帶 `GH_TOKEN` 回缺 scope、拿掉後回出 ID）。換狀態那條**未實測** |
| **從票開分支** | 分支出現在票的 Development 欄 | `gh issue develop <N> -R <o>/<r> --name <分支> --base <整合分支>`；查 `--list` | 🔴 **這條連結本身就會關票**：從這條分支開的 PR 一合併就關票，PR 內文寫 `Refs` 也擋不住（實測：四個 PR 都只寫 `Refs`，`closingIssuesReferences` 卻四個都是那張票，第一個合併就關票）⇒ **一張票要多個 PR 才做完時不要用它**，改用一般 `git switch -c`／`git worktree add -b`，靠 `Refs` 連結；開 PR 後用 `gh pr view <N> --json closingIssuesReferences` 核對。⚠️ `--branch-repo`（開在別的 repo）**未實測** |
| **PR 連票** | 合併時自動關票 | PR 內文 `Closes <票>`／`Refs <票>`；跨 repo 寫 `Closes <o>/<r>` 加票號 | 只在**合併進預設分支**時生效。跨 repo、跨 owner、公開 PR 連私有票都建得起來，合併後約兩秒關票（實測）。⚠️ 代價：公開 PR 的內文會出現私有 repo 的**名字與票號**（只有名字號碼、沒有內容），公開 repo 要不要這樣寫照開 PR 那支 skill 的規則 |
| **合併後自動刪分支** | 不留舊分支 | 開：`gh api -X PATCH repos/<o>/<r> -F delete_branch_on_merge=true`；讀回：`gh api repos/<o>/<r> --jq .delete_branch_on_merge` | 清單會漂，**用指令量、不要抄結果**。⚠️ **只有 write 權限時，開 repo 的 `settings/pages` 回 404**，長得跟「搬壞了」一樣；設定要用 owner／admin 身分走 API 讀 |

## 查不到的東西與搬家後的必做

- 🔴 **`gh … --jq` 不吃 `--arg`**：`gh api … --jq --arg R "$R" '…'` 回 `accepts 1 arg(s), received 4`，迴圈照跑、收到空資料 ⇒ 下游印「0 問題」＝假綠。要帶變數就在 shell 端加（例：`… | sed "s|^{|{\"r\":\"$R\",|"`），並看「檢查了幾張」是不是 0。
- **GitHub App 安裝了哪些 repo，gh 查不到**：`gh api user/installations/<id>/repositories` 用 gh 的 OAuth token 回 **403**，補 `read:user` scope 也一樣；`repos/<o>/<r>/installation` 要 app JWT，回 401；設定頁要 sudo（passkey），代理人不能代驗。⇒ **外部審查工具這類 App 的 repo 清單，由擁有者在設定頁目視**，不要叫擁有者補 scope。查得到的只有安裝本身：`gh api orgs/<org>/installations --jq '.installations[]|{id,app_slug,repository_selection}'`。
- 🔴 **repo 換 owner 後，舊 owner 發的 fine-grained PAT 會靜默讀不到它**，而只在 push／PR 觸發的跨 repo 守門不會自己跑，就一直不知道。⇒ **納入舊 repo 或搬家之後，把每一支跨 repo 守門 `gh run rerun` 一次，看 log 的判定碼，不看綠燈。** 找法：在每個相關 repo 對 `.github/workflows` 跑 `git grep -l` 找讀別的 repo 用的 token 名稱。

## 不採用與理由

| 功能 | 不用的理由 | 什麼情況再考慮 |
|---|---|---|
| **Projects（狀態記法不是 `project` 的 repo）** | Project 的 Auto-add 規則條數有方案上限（例如 Team 方案每個 Project 5 條）；repo 一多，**漏加的票不會出現在總表、也不會報錯** | 要用時以 repo 為單位整個加進去，照 `setup` 第 5 步「進 Project 的 repo」做 |
| **Milestones** | 跟 SPEC 子票做同一件事，並存＝兩處記同一份分組 | — |
| **Issue 類型** | 查詢與篩選都不用它，只多一個欄位（已經設了的留著無害，不再要求） | — |
| **Issue／PR 範本** | 票都用 `gh issue create --body-file` 開，範本只在網頁開票時帶出；組織共用範本又要求公開 repo | 開始有人在網頁上開票 |
| **Actions 自動化** | 唯一候選是「加進 Projects」與自動重算排程類欄位；票都在同一個 repo 時 Auto-add 已涵蓋，其餘手動跑 | 手動跑的欄位常過期到影響派工 |
| **Environment 分支限制** | 私有 repo 的設定**會被接受**，但**是否真的擋得住未實測**（設必要審核者回 422） | 實驗驗過才寫進來 |

**私有 repo 不能用：**

- **GitHub 程式碼搜尋**：私有 repo 搜已知字串全部 `total=0 incomplete=true`（⬛ 公開 repo 命中）；每分鐘有限額，連打約 8 次就 403。改用 `git grep`。
- **issue 搜尋條件** `is:blocked`、`is:blocking`、`blocked-by:N`、`blocking:N`：回 0；`has:blocked-by` 回全部。改用上面的 `issue_dependencies_summary`。
