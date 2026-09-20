# Queued follow-up error audit

Examined on 18 September 2026, against Codex Desktop 26.908.9136.0.

## Finding

The exact message, “App-server queued follow-up no longer exists”, was found in the installed Desktop composer code. That code checks an existing message ID against its queued items and local messages. If either lookup fails, it throws before sending `thread/queue/update`. Local Desktop logs contain this composer error. This identifies the immediate failure condition, not why that item disappeared.

CTC source sends initialization, the initialized notification, and `account/rateLimits/read` only. It does not connect to Desktop's RPC transport or call thread/queue methods. The official [app-server documentation](https://learn.chatgpt.com/docs/app-server) describes the rate-limit read method separately from task operations.

## Side-effect check and hardening

The CLI creates SQLite databases at startup even when only a quota read is requested. A synthetic queue item in an isolated test profile survived a helper start/read/exit. No real queued messages were edited for this test.

From 6.3.0, CTC supplies a separate `sqlite_home` and `CODEX_SQLITE_HOME`, scoped by a hash of the profile path under the CTC data directory. A real CLI test verified that its queue database was created there while the synthetic source-profile queue remained intact. Codex still handles authentication from the selected profile; CTC does not copy credentials. Helper cleanup closes stdin first and only terminates the specific child it started if that child does not exit.

There is no evidence from this audit that CTC caused the reported incident. The historical root cause is not proven. Do not claim that a private-format integration can never affect another version of Codex.

## If it recurs

Preserve the draft text and timestamp. When the task is idle, refresh or reopen its view. If the queued item is gone, let the user decide whether to send the text as a new message. Do not modify queue databases, recreate queued IDs, or send duplicate messages as a test. See RECOVERY.md for the full repair checklist.
