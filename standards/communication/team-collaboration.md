# Team Collaboration Protocol

Shared playbook for any cs-* agent joining a multi-agent team. Agents opt in by declaring `team_capable: true` in their YAML frontmatter.

## What this protocol governs

When an agent is spawned inside a team (via `TeamCreate` + `Agent` with `team_name` and `name`), it must follow the rules in this document for discovery, task coordination, messaging, and lifecycle. The agent's domain expertise is unchanged — only the coordination layer is added.

## 1. Team discovery

On first turn inside a team, read the team config to learn the roster:

```
~/.claude/teams/{team-name}/config.json
```

The `members` array contains each teammate's:

- `name` — human-readable identifier used for all messaging and task assignment
- `agentId` — UUID, reference only, never used for communication
- `agentType` — role/type

**Always address teammates by `name`, never by `agentId`.**

## 2. Shared task list (primary coordination channel)

Teams share a single task list at `~/.claude/tasks/{team-name}/`. This is the source of truth for who is doing what. Status updates go through the task list, not through messages.

**Pulling work:**

1. Call `TaskList` to see all tasks.
2. Filter for `status: pending`, no `owner`, empty `blockedBy`.
3. Prefer the lowest task ID — earlier tasks often set up context for later ones.
4. Claim via `TaskUpdate` with `owner: <your-name>` and `status: in_progress`.
5. Call `TaskGet` for full description before starting.

**Completing work:**

1. Verify the work is actually done (tests pass, implementation complete, no unresolved errors).
2. Call `TaskUpdate` with `status: completed`.
3. Call `TaskList` again to find the next available task or newly unblocked work.

**Creating work:**

- If you discover new work mid-task, call `TaskCreate` to add it to the shared list.
- Use `addBlockedBy` / `addBlocks` to express dependencies.

**Never mark a task completed if tests fail, the implementation is partial, or you hit an unresolved error.** Keep it `in_progress` and send a message explaining the blocker.

## 3. Messaging (SendMessage)

Your plain text output is **not** visible to other agents. The only way to communicate is `SendMessage`.

**Direct message:**

```json
{"to": "researcher", "summary": "5-10 word preview", "message": "plain text body"}
```

**Broadcast** (use sparingly — cost scales linearly with team size):

```json
{"to": "*", "summary": "...", "message": "..."}
```

**Rules:**

- Refer to teammates by `name`, never UUID.
- Don't send JSON status blobs like `{"type": "task_completed"}` — that's what `TaskUpdate` is for.
- When relaying a teammate's message to the user, don't quote it — it's already rendered.
- Messages arrive automatically as new conversation turns. No inbox polling.

**Legacy protocol responses** (only respond, never originate unless the user asks):

- `shutdown_request` → reply with `shutdown_response` echoing `request_id`, `approve: true/false`. Approving terminates your process.
- `plan_approval_request` → reply with `plan_approval_response` echoing `request_id`, `approve: true/false`, optional `feedback`.

## 4. Lifecycle

**Idle is normal.** After each turn, teammates automatically go idle. Idle does not mean done or unavailable — it means waiting for input. A DM wakes an idle teammate.

**Between tasks:**

1. Mark the current task completed via `TaskUpdate`.
2. `TaskList` for the next available task.
3. If none available and none blocked on you, go idle cleanly (end your turn).

**When the team lead requests shutdown:**

1. Finish or hand off any in-progress work.
2. Respond with `shutdown_response`, `approve: true`.
3. Your process will be terminated.

## 5. Anti-patterns

Do not:

- Use terminal tools (`ls ~/.claude/teams/...`) to peek at teammate activity. Send a message instead.
- Originate `shutdown_request` unless explicitly asked.
- Send structured JSON status messages (`{"type": "idle", ...}`, `{"type": "task_completed", ...}`). Use `TaskUpdate` for status, plain text for everything else.
- Spam broadcasts. Use `*` only when every teammate genuinely needs the message.
- Assume a teammate is gone because they're idle. Idle = waiting, not dead.
- Mark tasks completed prematurely. If you're blocked, say so via message and leave the task `in_progress`.
- Reference teammates by `agentId` / UUID. Always by `name`.

## 6. Quick reference

| Need | Tool |
|---|---|
| Discover roster | `Read ~/.claude/teams/{team}/config.json` |
| Find work | `TaskList` → filter pending + unowned + unblocked |
| Claim work | `TaskUpdate` with `owner`, `status: in_progress` |
| Get full details | `TaskGet` |
| Add new work | `TaskCreate` |
| Express dependency | `TaskUpdate` with `addBlockedBy` / `addBlocks` |
| Finish work | `TaskUpdate` with `status: completed` |
| Talk to one teammate | `SendMessage` with `to: <name>` |
| Talk to everyone | `SendMessage` with `to: "*"` (sparingly) |
| Respond to shutdown | `SendMessage` with `shutdown_response` |

---

**Applies to:** any agent with `team_capable: true` in frontmatter.
**Owner:** `agents/CLAUDE.md` documents the convention; this file is the implementation.
