---
name: setup
description: "Onboard a repo into the GitHub issue workflow: ask four questions (plus, for organization-owned repos, whether to install the issue self-check workflow), write docs/agents/github.md and a pointer line in CLAUDE.md, create the missing labels with gh label create, and turn on delete-branch-on-merge. Run once per repo, and again when the way the repo works changes."
disable-model-invocation: true
---

# 設定：把一個 repo 導入這套流程

產出三樣東西：該 repo 的 `docs/agents/github.md`（其他 skill 讀它）、`CLAUDE.md` 裡指過去的一行、標籤與 repo 設定。照下面的順序做，**不給草稿看**；做完一次告知結果。

## 0. 先讀私有擴充

照 [私有擴充](${CLAUDE_PLUGIN_ROOT}/references/private-extension.md) 的三步讀這支 skill 的補充（skill 名 `setup`）：

1. 用 Bash 跑這一條，整條逐字照抄：`printenv GITHUB_WORKFLOW_PRIVATE_DIR`
   - `printenv` 退出碼 1 且沒有輸出＝未設定；其他情況（被權限擋、工具錯誤、沒跑成）→ 停下告訴擁有者，不當成未設定。
2. 未設定 → 回報「私有擴充：未設定」，照本體做。後面寫「照私有擴充」的步驟一律跳過，並在結果裡列出跳過了哪幾步。
3. 有值才讀私有檔：用 Read 讀 `<值>/setup.md`。
   - 讀到 → 回報「私有擴充：已讀 setup.md」，內容當補充規則，與本體一起遵守。
   - 讀不到 → 停下，告訴擁有者讀不到哪個路徑，不要照本體繼續。

## 1. 先看現況

先讀、不動手：

- `git remote -v`：有沒有 remote、是哪個 `<owner>/<repo>`。**沒有 remote → 第 5、6 步跳過**，結果裡明說跳過了。
- 根目錄的 `CLAUDE.md`、`AGENTS.md`：有沒有已經指到 `docs/agents/github.md` 的那一行。
- `docs/agents/`：有沒有這支 skill 以前寫的 `github.md`，或其他工具留下的舊設定檔。
- `.github/workflows/`：有沒有部署類的 workflow（供第 2 步的部署線對照）。

## 2. 只問四題

只問這四題，一次問完；使用者叫用時已經給了答案的，直接採用、不再問：

1. **要不要進 Project**（要的話是哪一個 Project）→ 決定「施工狀態記法」：不進＝`labels`，進＝`project`。
2. **誰按合併**：擁有者，或指定的 GitHub 帳號。
3. **部署線**：不部署／合併即部署／推 main 即部署／手動，四選一。
4. **特殊禁忌**：這個 repo 有什麼不能做的（例如某條 workflow 的例外）；沒有就是「無」。

開票自檢 workflow 另成一段、另問一次（下面「第 5 題」）。

其他欄位不問，照 [repo 設定範本](${CLAUDE_PLUGIN_ROOT}/skills/setup/references/repo-config-template.md)「值從哪來」那欄取值。部署線的回答與第 1 步看到的 workflow 對不上（例如答「不部署」卻有部署 workflow）→ 照答案寫，在結果裡並列兩者請擁有者確認，不自己改答案。

### 第 5 題：開票自檢 workflow（只對 org 擁有的 repo）

用 `gh api repos/<owner>/<repo> --jq .owner.type` 看擁有者：

- **不是 `Organization`（個人帳號的 repo），或沒有 remote** → 這一段整段跳過、不問，設定寫 `開票自檢 workflow: 不裝`。
- **是 `Organization`** → 只問一題，推薦答案放第一個：

  > 要不要裝開票自檢 workflow？（推薦：**裝**）

  一句說明：票開出時由 Actions 跑一次 `ticket-check.sh`、結果留言在票上，補上「開票的人忘了在本機跑」的那一次；代價是每開一張票吃一次 Actions 額度（每個 job 進位 1 分鐘），額度用完時它不跑、也不報紅。
- **repo 設定裡這一欄已經有答案（`裝` 或 `不裝`）→ 這一段整段跳過、不問**，沿用原答案。要改答案就重跑 `setup`、叫用時直接給新答案（叫用時給的答案優先於設定裡的舊答案），不另開別的路。
- 答案寫進設定的 `開票自檢 workflow` 欄位（`裝` 或 `不裝`）；答「裝」才裝（第 6 步，裝之前還要過那一步的帳號檢查）。

## 3. 兩層設定：票開在哪個 repo

- 預設票開在本 repo。
- 使用者在回答裡講明（或私有擴充指定）這個 repo 的票開在別的 repo → 這是程式 repo：
  - 專案層的事（施工狀態記法、Project、機器標籤、等待擁有者的標籤、只檢查誰開的票）寫在**放票的那個 repo** 的設定裡；本 repo 的設定在這些欄位只寫 `見 <owner>/<repo>`。
  - 本 repo 自己的事（誰按合併、部署線、特殊禁忌）照答案寫。
  - 放票的 repo 還沒有 `docs/agents/github.md` → 在結果裡提醒先對它跑一次 `setup`，不替它寫。

## 4. 寫 repo 設定

1. 照 [repo 設定範本](${CLAUDE_PLUGIN_ROOT}/skills/setup/references/repo-config-template.md) 寫 `docs/agents/github.md`：**範本的每個欄位都要出現**，用不到的寫範本規定的空值，不刪欄位。
2. 已經有 `docs/agents/github.md` → 就地更新：補齊缺的欄位、改這次答案變了的值，其他人手寫的段落不動。
3. 有其他工具留下的舊設定檔 → 把這個 repo 特有的事併進 `github.md`；舊檔不刪，列給擁有者決定。
4. 在 `CLAUDE.md` 加一行：`GitHub 工作流的 repo 設定見 docs/agents/github.md。` 已經有指到它的一行就不重複加。沒有 `CLAUDE.md`、有 `AGENTS.md` → 加在 `AGENTS.md`；兩個都沒有 → 新建 `CLAUDE.md`，只放這一行。

## 5. 建標籤（沒有 remote 就跳過）

- 票開在別的 repo → 本 repo 不建標籤，結果裡寫「標籤建在 `<放票的 repo>`」。
- 照 [標籤規則](${CLAUDE_PLUGIN_ROOT}/references/labels.md) 第八節一步一步做：讀 repo 現有的標籤、對標籤規則的表格（名字取自剛寫的設定：施工狀態記法、機器標籤名、等待擁有者的標籤名），用 `gh label create` 建這個 repo **缺的**標籤；已有相近名稱的先問擁有者沿用或新建；做完讀回。
- 不用 `gh label clone`、不設組織的預設標籤（理由見標籤規則第八節）。
- 預設英文標籤還有票在用的 → 列給擁有者決定，不自己刪。
- **納入舊 repo**：開著的票缺標籤的，列出清單給擁有者看過再決定要不要補掛；補掛照標籤規則第七節（只加標籤、不改標題與內文、不補機器、已關的票不動）。
- **進 Project 的 repo**（`project` 記法）多三件事：
  1. 在 Project 的 Auto-add 規則加一條指向這個 repo。這只能在網頁上設，請擁有者做；條數有上限，漏加的票不會出現在 Project、也不報錯（見 [指令表](${CLAUDE_PLUGIN_ROOT}/skills/setup/references/gh-commands.md)「不採用與理由」）。
  2. 私有擴充若列了「用 Project 記法的 repo 名單」，照它加上這個 repo。
  3. 開著的票還掛著狀態標籤的，先把狀態搬進 Status，再照標籤規則第八節刪 `施工中`、`待驗證`（還有票在用的保留並列出來）。
  - Project 的 ID、Status 欄位與選項的 ID 用指令表「Project」那列的指令讀出來，寫進設定。

## 6. repo 設定（沒有 remote 就跳過）

- 開「合併後自動刪分支」並**讀回確認**：指令見 [指令表](${CLAUDE_PLUGIN_ROOT}/skills/setup/references/gh-commands.md)「合併後自動刪分支」那列。讀回不是 `true` → 結果裡寫沒開成，不寫「已開」。
- 讓外部審查工具或其他 GitHub App 讀得到這個 repo 等私有步驟：照私有擴充。
- **開票自檢 workflow**（第 5 題答「裝」才做）：
  1. 先看設定裡「只檢查誰開的票」的值。值是空的、`未設定`、或以 `見 ` 開頭 → **不裝**，結果裡寫「開票自檢 workflow 沒裝：只檢查誰開的票是 `<值>`」，請擁有者補上帳號後重跑 `setup`。這種值裝上去，`if:` 永遠不成立，workflow 每次都 skip、不留言、Actions 顯示成功，看起來像已裝而且全過。
  2. 是帳號 → 先跑 `gh api users/<帳號> --jq .login` 讀回。讀不回（帳號不存在、沒問到）→ **不裝**，結果裡寫讀不回的帳號與錯誤訊息。
  3. 讀回成功才把 [範本](${CLAUDE_PLUGIN_ROOT}/skills/setup/references/ticket-check-workflow.yml) 複製成這個 repo 的 `.github/workflows/ticket-check.yml`，`<只檢查誰開的票>` 換成那個帳號，和 `docs/agents/github.md` 同一批提交。
  - 答「不裝」、repo 裡卻已經有這支 → 列給擁有者決定，不自己刪。限制寫在 [開票自檢](${CLAUDE_PLUGIN_ROOT}/references/ticket-check.md)「Actions 上跑」。
- 寫或改這個 repo 的 GitHub Actions workflow 時，照 [Actions 規範](${CLAUDE_PLUGIN_ROOT}/skills/setup/references/actions-workflow-rules.md)；這個 repo 的例外寫進設定的「特殊禁忌」。

## 7. 歸屬登記與新專案

- 帳號歸屬登記：照私有擴充。
- 新專案：從範本 repo 開（範本 repo 名稱在私有擴充）；舊 repo 納入時跳過這一步。

## 8. 結果

做完一次告知，列出：

- 寫了哪些檔（`docs/agents/github.md`、`CLAUDE.md` 那一行），每個欄位填了什麼值。
- 跳過了哪幾步、為什麼（沒有 remote、票開在別的 repo、私有擴充未設定）。
- 建了、改名、保留了哪些標籤（標籤規則第八節最後一步的讀回）；開票自檢 workflow 裝了沒（答「裝」卻沒裝的，寫第 6 步擋下的原因）；自動刪分支的讀回值。
- 要擁有者決定或動手的事（舊設定檔、保留的英文標籤、要補掛的票、Project 的 Auto-add）。

## 往後怎麼用這份設定

- **認領**用狀態（狀態標籤或 Project Status，依「施工狀態記法」）＋機器標籤＋留言署名，不用 assignee。
- **維護**：改了這個 repo 的運作方式（部署線、狀態記法、禁忌），在同一個 PR 改 `docs/agents/github.md`。
- GitHub 指令與實測過的坑見 [指令表](${CLAUDE_PLUGIN_ROOT}/skills/setup/references/gh-commands.md)，各 repo 不抄。
