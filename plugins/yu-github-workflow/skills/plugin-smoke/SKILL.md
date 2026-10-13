---
name: plugin-smoke
description: Smoke test for this plugin. Use when the user says "plugin 實測" or asks whether this plugin is installed and loaded.
---

先照 [私有擴充](${CLAUDE_PLUGIN_ROOT}/references/private-extension.md) 的規則讀這支 skill 的補充：用 Bash 跑下面這段，不要改寫、不要自己判斷環境變數有沒有設。

```bash
if [ -z "${GITHUB_WORKFLOW_PRIVATE_DIR:-}" ]; then echo "STATE=unset"
elif [ ! -d "$GITHUB_WORKFLOW_PRIVATE_DIR" ]; then echo "STATE=missing-dir"
elif [ -f "$GITHUB_WORKFLOW_PRIVATE_DIR/plugin-smoke.md" ]; then echo "STATE=read"; cat "$GITHUB_WORKFLOW_PRIVATE_DIR/plugin-smoke.md"
else echo "STATE=no-file"; fi
```

然後只回下面兩行，其他什麼都不要說：

```
plugin 實測 OK
私有擴充：<狀態>
```

`<狀態>` 依 `STATE=` 那一行填：

| STATE | 填 |
|---|---|
| `unset` | `未設定` |
| `read` | `已讀 plugin-smoke.md` |
| `no-file` | `已設定，沒有 plugin-smoke.md` |
| `missing-dir` | `目錄不存在` |
| 指令沒跑成或沒有 `STATE=` 行 | `沒量到` |
