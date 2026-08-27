---
name: feedback-explicit-commands
description: "User wants exact copy-pasteable commands for anything requiring their own action, not descriptions"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 4d5fc693-0e17-4e1e-bce2-dc9c3fcf855e
  modified: 2026-08-27T09:52:39.127Z
---

When a step needs the user to run something themselves (sudo, chsh, anything I can't execute directly), give the complete, exact, copy-pasteable command — not a description of what to run or a partial fragment.

**Why:** Said explicitly: "If you want me to run any command explicitly give the whole command." Came up after several sudo-gated steps (installing the Performance plugin's privileged helper, the linuwu-sense kernel-module swap) where a full command was clearly what was needed to move forward without back-and-forth.

**How to apply:** For any Bash-tool-blocked action (needs a password, needs physical/manual confirmation), end the explanation with a single fenced command block containing the whole thing — prefer a small script file + one `sudo bash <path>` invocation over a long inline one-liner when the action has multiple steps, so it's still one thing to paste but stays reviewable.
