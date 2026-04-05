---
name: recalldory
description: >-
  Manages persistent memory across AI coding sessions using the recalldory CLI.
  USE WHEN: user says "remember this", "add to memory", "what do you remember",
  "recall", "forget this", "pin this", or "recalldory"; or when starting work
  that may have stored context from a prior session.
---

# recalldory — Persistent Memory Skill

> **You curate, recalldory persists.**
> Adding memories is ALWAYS the user's decision — never auto-add.

## Critical Rules

| Rule | Why |
|------|-----|
| **NEVER auto-add memories** | Explicit curation avoids noise; only add when user asks |
| **Always `recall` before starting work** | Relevant context may already be stored |
| **All output is JSON** | Parse `--json` output; do not screen-scrape |
| **Project scope is default** | Use `--global` only for cross-project knowledge |

## When to Use recalldory

- **Before starting work**: `recall` to surface relevant stored context
- **User says "remember this"**: `add` with the user's content
- **User says "forget that"**: `forget` the relevant memory ID
- **User asks "what do you remember"**: `list` or `recall` with broad query
- **User rates a memory**: `feedback` with `helpful` or `harmful`

## Core Commands

### Recall (Search)

```bash
# BM25 full-text search — use before starting any significant task
recalldory recall "<query>"

# Narrow to scope
recalldory recall "<query>" --scope project
recalldory recall "<query>" --scope global

# Limit results
recalldory recall "<query>" --top 5
```

### Add (Store)

```bash
# Basic add
recalldory add "the important thing to remember"

# With tags (comma-separated)
recalldory add "content" --tags "tag1,tag2"

# With explicit scope (default is project)
recalldory add "content" --scope project
recalldory add "content" --scope global    # cross-project knowledge

# Pin immediately (protects from decay/deletion)
recalldory add "critical constraint" --pin
```

### List

```bash
# List all memories
recalldory list

# Filter by scope
recalldory list --scope project
recalldory list --scope global

# Filter by status
recalldory list --status active
recalldory list --status pinned

# Limit output
recalldory list --limit 20
```

### Forget (Delete)

```bash
recalldory forget <id>
```

### Feedback (Quality Signal)

```bash
recalldory feedback <id> helpful   # Memory was useful
recalldory feedback <id> harmful   # Memory was wrong/misleading
```

Note: 3+ harmful marks triggers anti-pattern promotion (memory flagged as "never do this").

### Pin / Unpin

```bash
recalldory pin <id>     # Protect from decay and auto-deletion
recalldory unpin <id>   # Remove pin protection
```

Pinned memories are permanent until explicitly deleted with `forget`.

### Stats

```bash
recalldory stats        # Show memory count, decay stats, anti-patterns
```

## Memory Scopes

| Scope | Storage | Use For |
|-------|---------|---------|
| `project` (default) | `.recalldory/memory.db` | Project-specific context |
| `global` | `~/.recalldory/memory.db` | Cross-project knowledge, universal patterns |

## Standard Workflow

```bash
# 1. At session start or before starting a task — search for relevant context
recalldory recall "topic you're about to work on"

# 2. If user says "remember this" or "add this to memory"
recalldory add "the thing they want remembered"
# Ask: should this be pinned? global?

# 3. If memory was helpful
recalldory feedback <id> helpful

# 4. If memory was wrong or caused issues
recalldory feedback <id> harmful

# 5. If user asks to see stored memories
recalldory list --scope project
recalldory recall "broad topic"
```

## Memory Lifecycle

```
add → active → decay (based on time + feedback) → pruning candidate
                ↑                                        ↓
              feedback helpful                   3x harmful → anti-pattern
                ↑
              pin → permanent (exempt from all decay)
```

## Maintenance (user/cron, not agent-initiated)

```bash
recalldory maintain --dry-run   # Preview what would be pruned
recalldory maintain             # Run decay, anti-pattern promotion, pruning
```

## Hooks

```bash
recalldory hook install         # Install post-compact hook (run once during setup)
recalldory hook post-compact    # Injected automatically after context compaction
```

The post-compact hook automatically surfaces recent memories when context compacts — this is the primary automatic injection path.

## Anti-Patterns

- Auto-adding memories without user request
- Adding low-signal observations ("the build ran successfully")
- Forgetting to `recall` before starting new work
- Using `global` scope for project-specific knowledge
- Adding duplicate memories (recalldory uses SimHash deduplication, but avoid anyway)
