---
name: plugin-smoke
description: Smoke test for this plugin. Use when the user says "plugin 實測" or asks whether this plugin is installed and loaded.
---

照 [私有擴充](${CLAUDE_PLUGIN_ROOT}/references/private-extension.md) 的三步讀這支 skill 的補充（skill 名 `plugin-smoke`）：

1. 用 Bash 跑這一條，逐字照抄：`printenv GITHUB_WORKFLOW_PRIVATE_DIR`
2. 輸出是空的 → 狀態是 `未設定`。
3. 有值 → 用 Read 讀 `<值>/plugin-smoke.md`。
   - 讀到 → 狀態是 `已讀 plugin-smoke.md`。
   - 讀不到 → 停下，只回「私有擴充：讀不到 <你讀的路徑>，請擁有者確認」，不要回下面的兩行。

狀態是 `未設定` 或 `已讀 plugin-smoke.md` 時，只回下面兩行，其他什麼都不要說：

```
plugin 實測 OK
私有擴充：<狀態>
```
