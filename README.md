# `recalldory`

A persistent memory system for AI coding assistants, written in [Inko](https://inko-lang.org/).

Named after **Dory**, the blue tang from *Finding Nemo* known for her short-term memory loss. Irony aside, `recalldory` helps AI assistants remember context across sessions—something Dory could only dream of. Just keep swimming, just keep recalling.

## Features

- **Memory Storage**: Store and retrieve coding knowledge, patterns, and discoveries
- **Full-Text Search**: FTS5-powered search with BM25 ranking
- **Memory Decay**: Automatic strength decay for unused memories
- **Anti-Pattern Detection**: Flag harmful patterns based on feedback
- **Import/Export**: JSON-based backup and restore

## Commands

```
recalldory add <content> [--tags <tags>] [--scope <scope>] [--pin]
recalldory recall <query> [--scope <scope>] [--top <n>]
recalldory list [--scope <scope>] [--status <status>] [--limit <n>]
recalldory forget <id>
recalldory pin <id>
recalldory unpin <id>
recalldory feedback <id> <helpful|harmful>
recalldory maintain [--dry-run]
recalldory stats [--verbose]
recalldory export
recalldory import <file>
recalldory agents-md [--path <path>]
```

## Building

```bash
inko build
```

## Data Storage

Memories are stored in `.recalldory/memory.db` (SQLite with FTS5).
