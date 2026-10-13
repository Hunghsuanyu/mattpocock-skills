# 在別人的 repo 上協作

分流時用到的指令與跨人協作準則。總則（三種票的權限）在 [SKILL.md](${CLAUDE_PLUGIN_ROOT}/skills/triage/SKILL.md) 第 2 節。

為什麼別人的票只留言：票的內文是開票人對工作的定義；`gh issue edit --body-file` 是整份覆蓋、不留痕跡。

## 送建議（agent suggestions）

想請對方改標籤、類型、欄位、指派人或關票 → 送「建議」，不要只留言。建議出現在票頂端的「Agent suggestions」面板，對方逐條按接受或拒絕；接受的那筆在時間軸上永久帶著理由與信心。**內文不在範圍內，改內文仍只留言。**

送法（以標籤為例；`suggest:true` 是建議，不帶就是直接套用）：

```bash
gh api graphql -f query='mutation($id:ID!,$l:ID!){addLabelsToLabelable(input:{labelableId:$id,labels:[{labelId:$l,suggest:true,confidence:MEDIUM,rationale:"<280 字內的理由>"}]}){clientMutationId}}' -f id=<issue node id> -f l=<label node id>
```

回讀：`issue(number:N){ pendingSuggestions{ ... on PendingLabelSuggestion{ label{name} rationale } } }`；對方用 `has:suggestions` 可以搜出待審的票。

已實測（免費方案、未開 Copilot、以 repo owner 身分送出，各附對照組）：

- 建議在按接受之前不生效；逐條接受、拒絕都成立。⬛ 對照：同一次呼叫不帶 `suggest` 的標籤直接套用。
- **信心門檻對 API 也有效**（repo 預設門檻 Cautious）：不帶 `suggest`、只帶 `confidence` → HIGH 直接生效，MEDIUM／LOW 自動留成建議。⬛ 對照：不帶 `confidence` → 直接生效（不帶信心的既有腳本行為不變）。⇒ 照實標信心，沒把握的自動進對方的審核面板；對方把門檻調成別的等級，結果會跟著變。

限制：

- ⚠️ **拒絕不留紀錄**（時間軸只有接受的那筆）。
- ⚠️ **不是防線**：有寫入權的人一樣能直接改（官方說法：approvals are a workflow convenience, not a security control）。
- ⚠️ **未實測：在同仁 repo 只有 write 權限時，送出的是否仍是「建議」。** 第一次在同仁 repo 用之前先測，並先讓對方知道票上會出現這個面板。

## 跨人協作準則

- **我方是輔助、不主導**：同仁主導的專案，我方只提供接上共用系統所需的東西。強度只標在共用介面的硬規則，對方內部設計一律「參考」；不要求對方建我方標籤。
- **給同仁讀的計畫與規格，在組織 repo 放一份副本，票連副本**：組織 owner 的權限不涵蓋個人 repo，同仁點個人 repo 的連結只會看到 404。副本開頭註明「凍結副本、以票為準」；行號位移要逐行驗過再改連結。
- **對接規則分三種強度**（規則寫在對方 repo 以外的正本裡時）：🔒 強制＝不能改，有意見開 issue；🔧 可調整＝對方自己決定做法，**在票上留言說明即可、不必等核准**；💡 參考＝不要求照做。
- **參照另一個系統的程式當範例**：票上寫到檔案與行號，用 SHA 固定連結，並標明是「照著做」還是「反例、不要照做」。

## 動手前看作者、事後查內文被誰改過

- 看作者：`gh issue view <票號> -R <owner>/<repo> --json author --jq .author.login`。
- ⚠️ **沒有機械強制點**：免費方案擋不住有寫入權的人改別人的票，只能靠動手前看作者。
- 事後查內文被誰改過（GraphQL `userContentEdits`；未實測，第一次用先對自己的票試一次）：

  ```bash
  gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){userContentEdits(first:20){nodes{editedAt editor{login}}}}}}' -f o=<owner> -f r=<repo> -F n=<票號>
  ```
