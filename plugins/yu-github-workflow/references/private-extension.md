# 私有擴充

這個 plugin 是公開的，只放通用規則。各人自己的補充（內部頻道、私有腳本的位置、只適用自己環境的步驟）放在 plugin 以外的一個目錄，由一個環境變數指過來。plugin 本身不寫死任何本機路徑。

## 設定

| 項目 | 規則 |
|---|---|
| 環境變數 | `GITHUB_WORKFLOW_PRIVATE_DIR`，值是一個目錄的絕對路徑 |
| 檔名 | `<skill 名>.md`，一支 skill 一個檔；skill 名就是 `SKILL.md` frontmatter 的 `name` |
| 沒設變數 | 正常情形。每支 skill 照本體做，不提示、不報錯 |

## 每支 skill 開頭怎麼讀

1. 用 Bash 讀環境變數與檔案，不要憑印象判斷有沒有設。範本（把 `<skill 名>` 換成自己的名字）：

   ```bash
   if [ -z "${GITHUB_WORKFLOW_PRIVATE_DIR:-}" ]; then echo "STATE=unset"
   elif [ ! -d "$GITHUB_WORKFLOW_PRIVATE_DIR" ]; then echo "STATE=missing-dir"
   elif [ -f "$GITHUB_WORKFLOW_PRIVATE_DIR/<skill 名>.md" ]; then echo "STATE=read"; cat "$GITHUB_WORKFLOW_PRIVATE_DIR/<skill 名>.md"
   else echo "STATE=no-file"; fi
   ```

2. 依結果處理：

   | STATE | 處理 |
   |---|---|
   | `unset` | 照本體做 |
   | `no-file` | 照本體做（這支 skill 沒有補充） |
   | `read` | 檔案內容當成這支 skill 的補充規則，與本體一起遵守 |
   | `missing-dir` | 停下來告訴擁有者「變數指到的目錄不存在」。設了變數卻讀不到，多半是路徑寫錯，照本體做會讓補充規則靜默失效 |
   | 指令沒跑成、沒有 `STATE=` 行 | 回報「沒量到」，不要當成 `unset` |

## 補充只能加，不能推翻

- 補充可以加步驟、加檢查、指定自己環境的工具或頻道。
- 補充不能刪掉或放寬本體的任何一步。本體寫「必須」的，補充不能改成「可以不用」。
- 兩者衝突時停下來，把衝突的兩句並列給擁有者看，由擁有者決定；不要自己挑一邊。

## hook 的持久資料

hook 要留紀錄（例如 hook 帳本）時，寫到 `${CLAUDE_PLUGIN_DATA}/hook-ledger.log`。

- `${CLAUDE_PLUGIN_DATA}` 是官方給 plugin 的資料目錄（`~/.claude/plugins/data/<plugin id>/`），跨版本更新保留、解除安裝時刪除；hook 指令裡與 hook 的環境變數都拿得到。
- 不要寫在 `${CLAUDE_PLUGIN_ROOT}` 底下：那是安裝版本的目錄，每次更新會換。
- 用 `--plugin-dir` 載入的本機開發版，plugin id 與安裝版不同，資料目錄也是另一個；測試時寫的紀錄不會混進安裝版的帳本，讀帳本時要讀對目錄。

## skill 內文怎麼指到 plugin 自己的檔

`SKILL.md` 內文寫 `${CLAUDE_PLUGIN_ROOT}/<相對路徑>`，載入時會被換成這個 plugin 的絕對路徑（`${CLAUDE_PLUGIN_DATA}` 也一樣會被換掉）。其他環境變數（包括 `GITHUB_WORKFLOW_PRIVATE_DIR`）不會被替換，要在 Bash 裡讀。
