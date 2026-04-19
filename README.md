# `recalldory`

A persistent memory system for AI coding assistants, written in [Inko](https://inko-lang.org/).

Named after **Dory**, the blue tang from *Finding Nemo* known for her short-term memory loss. Irony aside, `recalldory` helps AI assistants remember context across sessions—something Dory could only dream of. Just keep swimming, just keep recalling.

## Mental Model

**You curate, recalldory persists.**

Adding memories is always manual — you decide what's worth remembering. Retrieval is automatic after context compaction via hooks; otherwise manual via `recall`. This explicit curation avoids the noise of LLM-generated "important" memories.

## Workflow

```mermaid
sequenceDiagram
    participant You
    participant Claude
    participant Recalldory
    participant DB as .recalldory/recalldory.db

    Note over You,DB: Session 1: Learning
    You->>Claude: Work on a task
    You->>Recalldory: add "important discovery"
    Recalldory->>DB: Store memory
    Claude->>Claude: Context fills up...
    Claude->>Claude: Compact context
    Claude->>Recalldory: hook post-compact
    Recalldory->>DB: List recent memories
    DB-->>Recalldory: Memories
    Recalldory-->>Claude: Inject as context

    Note over You,DB: Session 2: Recalling
    You->>Claude: New session starts
    Claude->>Claude: Context compacts
    Claude->>Recalldory: hook post-compact
    Recalldory->>DB: List recent memories
    DB-->>Recalldory: Memories (including "important discovery")
    Recalldory-->>Claude: Inject as context
    Claude-->>You: Remembers previous session
```

## Installation

### Pre-built binaries

Download the latest release for your platform from the [Releases page](https://github.com/jhult/recalldory/releases).

| Binary | Platform |
|--------|----------|
| `recalldory-amd64-linux-gnu` | Linux x86_64 (glibc) |
| `recalldory-arm64-linux-gnu` | Linux ARM64 (glibc) |
| `recalldory-amd64-linux-musl` | Linux x86_64 (musl/Alpine) |
| `recalldory-arm64-linux-musl` | Linux ARM64 (musl/Alpine) |
| `recalldory-amd64-mac-native` | macOS x86_64 |
| `recalldory-arm64-mac-native` | macOS Apple Silicon |

[SQLite](https://www.sqlite.org/) is statically linked into all binaries. [Apple does not guarantee binary compatibility at the kernel syscall level](https://developer.apple.com/library/archive/qa/1118/_index.html), so macOS builds still dynamically link system libraries (libSystem, Security, CoreFoundation), but SQLite is embedded via `-force_load`.

### Build from source

```bash
# Requires [Inko commit abca5b6](https://github.com/inko-lang/inko/commit/abca5b6beae2914602a1a353efc899e2cb3ad877) and Zig
scripts/build-sqlite.sh arm64-mac-native  # or your target triple
inko build --release \
  --linker-arg "-L$PWD/lib" \
  --linker-arg "-force_load" \
  --linker-arg "$PWD/lib/libsqlite3.a" \
  src/recalldory.inko
```

### Setup

```bash
# Install the post-compact hook (auto-injects memories after context compaction)
recalldory hook install
```

## Commands

### Core Operations

| Command | Description |
|---------|-------------|
| `add <content> [--tags T] [--scope S] [--pin]` | Store a memory (optionally pin it) |
| `recall <query> [--scope S] [--top N]` | Full-text search with BM25 ranking |
| `list [--scope S] [--status S] [--limit N] [--older-than N]` | List memories by scope/status |
| `update <id> [content] [--content C] [--tags T]` | Correct a memory in place |
| `forget <id>` | Delete a memory |
| `feedback <id> helpful\|harmful` | Flag memory quality |

### Memory Lifecycle

| Command | Description |
|---------|-------------|
| `pin <id>` | Protect from decay/deletion (for important memories) |
| `unpin <id>` | Remove pin protection |
| `history <id>` | Show edit history for a memory |
| `maintain [--dry-run]` | Run decay, anti-pattern promotion, and pruning |

### Data Management

| Command | Description |
|---------|-------------|
| `contradictions [--resolve <id>]` | Detect potential contradictions between memories |
| `export` | Full JSON backup of all memories |
| `import <file>` | Restore from JSON backup |
| `agents-md [--path P]` | Generate AGENTS.md from pinned + anti-pattern memories |
| `stats` | Show memory statistics |

### Hooks

| Command | Description |
|---------|-------------|
| `hook install` | Install post-compact hook into `$HOME/.claude/settings.json` |
| `hook post-compact` | Run by hook to inject memories (usually automatic) |

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Manual add only | LLM-generated "important" memories are noisy; explicit curation is reliable |
| No automatic extraction | Avoids memory bloat from trivial observations |
| `update` preserves history | Old versions are superseded, not destroyed — corrections are traceable |
| Decay for ranking, not deletion | Rare edge cases ("avoid v2.3 bug") shouldn't be lost to time |
| 3+ harmful marks → anti-pattern | Requires consensus before treating as "never do this" |
| Pinning exempts from all decay | Important memories stay forever |
| SQLite + [FTS5](https://www.sqlite.org/fts5.html) | Simple, fast, no external dependencies |
| Scope (project/global) | Keep project-specific knowledge separate from universal patterns |

## Data Storage

Memories are stored in [SQLite](https://www.sqlite.org/) databases with [FTS5](https://www.sqlite.org/fts5.html).

| Scope | Default Path | Override |
|-------|-------------|----------|
| Project | `./.recalldory/recalldory.db` | `RECALLDORY_DB_PATH` |
| Global | `$HOME/.recalldory/recalldory.db` (Unix) or `$USERPROFILE/.recalldory/recalldory.db` (Windows) | `RECALLDORY_GLOBAL_DB_PATH` |

`recall` and `list` search both databases and merge results. `add` writes to the project database by default; use `--scope global` to write to the global database. ID-based commands (`forget`, `pin`, `unpin`, `feedback`) try the project database first, falling back to global. `stats`, `maintain`, and `rebuild-fts` operate on both databases.

If a legacy `memory.db` exists, it is automatically renamed to `recalldory.db` on first access.

## For AI Agents

### Claude Code

A Claude Code skill is included at `.claude/skills/recalldory/` and is loaded automatically when working in any project that contains it. Copy it to `~/.claude/skills/recalldory/` for global availability.

### Other AI Assistants

**Primary command**: `recalldory recall "<query>"` — Returns JSON with matching memories.

**Key behaviors**:
- Adding memories is the *user's* decision. Never auto-add.
- Use `recall` to find relevant context before starting work.
- If the user asks you to remember something, use `recalldory add "<content>"`.
- Memories are project-scoped by default; use `--scope global` for cross-project knowledge.

**Ready-to-paste for CLAUDE.md**:
```markdown
## Recalldory Memory

This project uses recalldory for persistent memory across sessions.

- Check memories before starting: `recalldory recall "<topic>"`
- User explicitly adds memories — do not auto-add observations
- Hook auto-injects memories after context compaction
```

## Similar Projects

The following projects also provide persistent memory for AI agents (listed alphabetically):

- **[AgentKits-Memory](https://github.com/aitytech/agentkits-memory)** - Persistent memory system for AI coding assistants via MCP, compatible with Claude Code, Cursor, Copilot, Windsurf, and Cline.
- **[CASS Memory System](https://github.com/Dicklesworthstone/cass_memory_system)** - Procedural memory for AI coding agents that transforms scattered session history into persistent, cross-agent memory.
- **[claude-engram](https://github.com/mlapeter/claude-engram)** - Brain-inspired persistent memory for Claude.ai featuring salience scoring, forgetting curves, and sleep consolidation modeled on hippocampal memory.
- **[claude-mem](https://github.com/thedotmack/claude-mem)** - Fully automatic memory for Claude Code via lifecycle hooks with 3-layer progressive disclosure search and web viewer UI.
- **[Double](https://github.com/ossa-ma/double)** - A local memory system for AI agents.
- **[Engram](https://codeberg.org/GhostFrame/engram)** (GhostFrame) - Cognitive layer for AI agents with FSRS-6 spaced repetition, personality extraction, and reasoning with contradiction detection.
- **[Engram](https://github.com/Gentleman-Programming/engram)** (Gentleman-Programming) - Agent-agnostic Go binary with SQLite + FTS5 providing persistent memory via MCP server, HTTP API, CLI, and TUI.
- **[Lavra](https://github.com/roberto-mello/lavra)** - A plugin with compound engineering workflows and memory for AI coding agents.
- **[MnemoCore](https://github.com/RobinALG87/MnemoCore-Persistent-Cognitive-Ai-Memory)** - A persistent cognitive AI memory system.
- **[Mnemoria](https://github.com/one-bit/mnemoria)** - Git-friendly memory storage for AI agents with hybrid semantic + full-text search and append-only binary format.
- **[Smriti-MCP](https://github.com/tejzpr/Smriti-MCP)** - Graph-based memory for LLMs with EcphoryRAG-inspired multi-stage retrieval combining cue extraction, graph traversal, and vector similarity.
- **[Smriti](https://github.com/zero8dotdev/smriti)** (zero8dotdev) - Shared memory for AI engineering teams with git-based team knowledge sharing across Claude Code, Cursor, and Codex.
- **[true-mem](https://github.com/rizal72/true-mem)** - Persistent memory plugin for OpenCode with cognitive psychology-based memory management.
- **[YantrikDB](https://github.com/yantrikos/yantrikdb-server)** - Cognitive memory engine with forgetting, consolidation, contradiction detection, and multi-signal relevance scoring (HNSW vector + graph + temporal + decay + KV). Embedded-first Rust library with Python/MCP bindings.

Note: [deepseek-ai/Engram](https://github.com/deepseek-ai/Engram) is a research project on conditional memory via scalable lookup for LLMs (ML architecture), rather than a persistent memory storage system.

## Why Not...?

Some AI memory systems include features inspired by cognitive science. Here's why `recalldory` doesn't:

**[FSRS-6](https://github.com/open-spaced-repetition/fsrs4anki) / [Spaced Repetition](https://en.wikipedia.org/wiki/Spaced_repetition)** — These algorithms model *human* [forgetting curves](https://en.wikipedia.org/wiki/Forgetting_curve) (biological memory decay). AI retrieval is binary: context is either in the prompt window or it isn't. There's no evidence spaced repetition improves AI memory retrieval.

**[Sleep Consolidation](https://en.wikipedia.org/wiki/Memory_consolidation)** — The metaphor is lovely, but what's actually useful is just database hygiene: deduplication and merging. `recalldory` does this via SimHash near-duplicate detection during `add` operations.

**Complex [Salience](https://en.wikipedia.org/wiki/Salience_(neuroscience)) Scoring** — LLM-generated importance scores are noisy and self-reinforcing. Simple access frequency + explicit feedback (helpful/harmful) is more robust and deterministic.

**[Graph-Based Memory](https://en.wikipedia.org/wiki/Knowledge_graph) / Multi-Hop Association** — Theoretically interesting, but no benchmarks show it outperforms good similarity search. Entity extraction is noisy, and the implementation complexity is high for unclear payoff.

**Aggressive Decay-Based Deletion** — Decay is useful for *ranking* retrieval results, but dangerous for *deletion*. It can lose rare-but-critical edge cases (e.g., "don't use library X v2.3, it has a critical bug"). `recalldory` uses decay for ranking only — deletion requires explicit harmful feedback (3+ marks).

**Contradiction Detection** — Coding context rarely has true logical contradictions. Instead, you have updates ("we migrated to Postgres"), context-dependent rules, and preference drift. These create false positives. `recalldory` includes this feature but it's optional and low-priority. See [paraconsistent logic](https://en.wikipedia.org/wiki/Paraconsistent_logic) for how formal systems handle contradictions.

**What actually works**: Simple strength scoring, deduplication, scope separation, FTS + strength-based ranking, and explicit user feedback. Good database design beats cognitive science metaphors.

## Relationship to Claude Code's Built-In Memory

Claude Code has its own memory system: `CLAUDE.md` files for manual instructions, and an auto-memory system where the AI proactively saves notes to `~/.claude/projects/<project>/memory/` based on what it judges worth remembering. These are complementary, not competing:

| | Claude Code Memory | Recalldory |
|---|---|---|
| **Curated by** | AI (automatic) | User (explicit) |
| **Injected** | Session start, always | Post-compact hook |
| **Best for** | Working preferences, feedback, communication style | Project-specific technical discoveries, gotchas, decisions |

The gray zone is project-level facts (e.g. "this project uses X library"), which could end up in both. In practice: let Claude Code memory handle *how to work with you*; use `recalldory` for *what you've learned about the project*. The explicit curation model is the key difference — Claude Code's AI decides what to save, which can be noisy. `recalldory` only saves what you explicitly ask it to remember.
