---
name: recalldory
description: >-
  Manages persistent memory across AI coding sessions using the recalldory CLI.
  USE WHEN: user says "remember this", "add to memory", "what do you remember",
  "recall", "forget this", "pin this", "update memory", "memory history", or
  "recalldory"; or when starting work that may have stored context from a prior
  session. Recalldory searches both project and global databases automatically,
  so always recall before starting work to surface relevant stored context.
---

# recalldory — Persistent Memory Skill

> **You curate, recalldory persists.**
> Adding memories is ALWAYS the user's decision — never auto-add.

## How Dual Databases Work

Recalldory stores memories in two SQLite databases and searches them together:

| | Project DB | Global DB |
|---|---|---|
| **Default path** | `./.recalldory/recalldory.db` | `$HOME/.recalldory/recalldory.db` |
| **Override env var** | `RECALLDORY_DB_PATH` | `RECALLDORY_GLOBAL_DB_PATH` |
| **Contains** | Project-specific context | Cross-project knowledge |

**Read commands** (`recall`, `list`) search both databases and merge results — you don't need to specify which one to look in.

**Write commands** route based on `--scope`: `project` (default) writes to project DB, `global` writes to global DB.

**ID-based commands** (`forget`, `pin`, `unpin`, `feedback`, `update`, `history`) try the project database first, then fall back to global if the ID isn't found.

**Stats/maintenance** (`stats`, `maintain`, `rebuild-fts`) operate on both databases, combining results.

## Critical Rules

| Rule | Why |
|------|-----|
| **NEVER auto-add memories** | Explicit curation avoids noise; only add when user asks |
| **Always `recall` before starting work** | Both databases are searched automatically — relevant context may already be stored |
| **All output is JSON** | Parse output as JSON; don't screen-scrape |
| **Project scope is default for writes** | Use `--scope global` only for cross-project knowledge |
| **Prefer `update` over `forget`+`add`** | Update preserves history (old version marked superseded); forget+add destroys it |
| **`feedback harmful` is for flagging, not deleting** | Marks a memory as bad practice to keep visible as a warning; not a pre-deletion step |
| **Don't add low-signal observations** | "The build ran successfully" isn't worth storing |

## Core Commands

### Recall (Search) — use before starting any significant task

```bash
recalldory recall "<query>"           # Searches both databases
recalldory recall "<query>" --scope project  # Filter to project results
recalldory recall "<query>" --scope global   # Filter to global results
recalldory recall "<query>" --top 5          # Limit results
```

### Add (Store) — always recall first, then ask about scope and pinning

**Step 1: Recall first.** Always run `recall` before adding to check for similar content. This avoids duplicates and gives the user context about what's already stored.

**Step 2: Based on what recall finds:**
- **No similar memory found**: Add new, asking the user about scope and pinning:
  > "Should this be: (1) Project, (2) Project + Pinned, (3) Global, or (4) Global + Pinned?"
- **Similar memory found**: Show the user what exists and ask what they want:
  > "I found an existing memory (ID 4): 'Auth middleware requires the session cookie...' — should I (1) update this memory, (2) add a new one anyway, or (3) skip since it's already stored?"

```bash
recalldory add "content"                         # Project, not pinned (default)
recalldory add "content" --pin                    # Project, pinned
recalldory add "content" --scope global          # Global, not pinned
recalldory add "content" --scope global --pin    # Global, pinned
recalldory add "content" --tags "tag1,tag2"      # With tags
```

### Update — the proper way to correct a memory

When a memory needs correction, use `update` instead of `forget` + `add`. Update creates a new version and marks the old one as superseded, preserving history.

```bash
recalldory update <id> "corrected content"        # Update content
recalldory update <id> --tags "new,tags"         # Update tags
recalldory update <id> --scope global             # Change scope
```

### List

```bash
recalldory list                     # From both databases, merged
recalldory list --scope project     # Project only
recalldory list --scope global      # Global only
recalldory list --status pinned     # Pinned only
recalldory list --status active     # Active only
recalldory list --limit 20          # Limit output
recalldory list --older-than 30     # Not accessed in 30+ days
```

### Forget (Delete) — hard delete, use carefully

```bash
recalldory forget <id>              # Tries project DB, falls back to global
```

Use `forget` only when the memory is truly wrong or irrelevant. For corrections, prefer `update`.

Note: `feedback harmful` is for flagging a memory you want to keep but mark as bad practice — it's not needed if you're deleting the memory.

### Feedback (Quality Signal)

```bash
recalldory feedback <id> helpful   # Memory was useful
recalldory feedback <id> harmful   # Memory is bad practice — keep it but flag it
```

3+ harmful marks triggers anti-pattern promotion (flagged as "never do this"). Use `harmful` when the memory describes something to avoid but you want it visible as a warning, not when you want to delete it.

### Pin / Unpin

```bash
recalldory pin <id>     # Protect from decay and auto-deletion
recalldory unpin <id>   # Remove pin protection
```

Pinned memories are permanent until explicitly deleted with `forget`.

### History — show version chain for a memory

```bash
recalldory history <id>             # Tries project DB, falls back to global
```

### Contradictions

```bash
recalldory contradictions            # List detected contradictions
recalldory contradictions --resolve <id>  # Resolve a contradiction
```

## Memory Lifecycle

```
add → active → decay (based on time + feedback) → pruning candidate
                ↑                                        ↓
              feedback helpful                   3x harmful → anti-pattern
                ↑
              pin → permanent (exempt from all decay)

update → new version (old is superseded, history preserved)
```

## Maintenance Commands

```bash
recalldory maintain --dry-run   # Preview what would be pruned (both DBs)
recalldory maintain             # Run decay, anti-pattern promotion, pruning
recalldory stats                # Combined statistics from both DBs
recalldory rebuild-fts          # Rebuild FTS5 index on both DBs
```

## Hooks

```bash
recalldory hook register        # Register post-compact hook (one-time setup)
recalldory hook inject          # Inject memories into context (auto-called on compaction)
```

The hook automatically surfaces recent memories from both databases when context compacts, injecting them as additional context for continuity across sessions.