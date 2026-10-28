# Reviews

`risk: high` 任務的審查紀錄，一個任務一個檔：`<任務 id>.md`。流程見 `harness/LOOP.md` §10，清單見 `harness/VERIFY.md` §4。

```text
fingerprint: <python3 harness/harness.py fingerprint 的輸出>
verdict: approve | changes
reviewer: codex | claude-subagent
---
逐項清單的結論、發現的問題
```

Review 之後程式碼又改過，指紋不同，這份 review 就自動失效。
