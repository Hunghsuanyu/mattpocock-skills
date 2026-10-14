# 讀窄、搜寬：指令與坑

## 讀單一檔，不 clone

讀某個分支或 SHA 上的一個檔：

```bash
gh api "repos/<owner>/<repo>/contents/<path>?ref=<分支或SHA>" --jq .content | base64 -d
```

已經有 clone 時，`git -C <clone> show <ref>:<path>` 也可以，不必切換工作樹。

## 錨點用 SHA 固定連結

- 格式：`https://github.com/<owner>/<repo>/blob/<40 碼 SHA>/<path>#L10-L20`；`.md` 檔加 `?plain=1` 才能指到行。
- 行號綁在 SHA 上不會漂移。同 repo 的留言會展開成程式碼片段，跨 repo 只顯示網址。
- **40 碼 SHA 一律 `git rev-parse <短碼或 ref>` 取，不准從短碼往後補。** 補出來的 SHA 形狀完全合法、前幾碼也對，連結卻是 404，而且看起來跟正確的一樣。
- 票上的行號量於票上那顆 SHA，不是你的工作樹。開工先在那顆 SHA 上確認，對不上就回報。

## 搜尋用 git 內建 grep

```bash
git -C <clone> fetch origin
git -C <clone> grep -n -E "<pattern>" <ref>
```

- 任何分支或 SHA 都能搜，不用切換工作樹。
- 對照組：換一個已知會命中的 ref 或 pattern 跑同一條，確認它會回「有」，才相信「沒有」。

## worktree 隔離

- 一張票一個工作樹，從整合分支開：`git -C <repo> worktree add -b <分支> <路徑> origin/<整合分支>`。
- 子代理的 `isolation: worktree` 只隔離主要工作目錄那個 repo；要動其他 repo，自己對那個 repo `git worktree add`。
- 拆工作樹：`git -C <repo> worktree remove --force <路徑>`，拆完看 `git worktree list`。

## 從票開分支的坑

`gh issue develop <票號> --name <分支>` 會把分支連到票的 Development 欄，而**這條連結本身就會關票**：從這條分支開的 PR 一合併進預設分支，票就被關掉，PR 內文只寫 `Refs` 也擋不住。

- 一張票要多個 PR 才做完（尤其跨 repo），或這張票會經整合分支收齊後才合進預設分支時，不要用它開分支，改用一般的 `git worktree add -b`／`git switch -c`。
- 開 PR 之後用 `gh pr view <PR> --json closingIssuesReferences` 核對它會關哪些票。
