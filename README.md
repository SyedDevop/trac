# Trac (Task Tracker)

<!--toc:start-->
- [Editor integration](#editor-integration)
- [Requirements](#requirements)
- [Build](#build)
- [Quick start](#quick-start)
- [The spec](#the-spec)
- [Commands](#commands)
- [Credits](#credits)
<!--toc:end-->

A plain-text, file-based task tracker CLI written in Zig.

`trac` is a from-scratch Zig implementation of the **Tasks system** spec and CLI designed by [rexim](https://github.com/rexim) for his [**tatr**](https://github.com/tsoding/tatr) project. All credit for the original idea, the on-disk task layout, the HUID scheme, and the Task Query Language design goes to that project — `trac` follows the same spec (with a couple of intentional differences noted below) but is an independent codebase, not a fork.

> If you want the original C/nob.c reference implementation, or to read the spec in its original words, see [tsoding/tatr](https://github.com/tsoding/tatr) and its [README](https://github.com/tsoding/tatr/blob/main/README.md).

Tasks live as Markdown files on disk (`tasks/<HUID>/TASK.md`), so the whole database is just a directory tree you can commit to git, grep, and edit by hand — no server, no database, no lock-in.

## Editor integration

[**trac.nvim**](https://github.com/SyedDevop/trac.nvim) is a companion Neovim plugin for browsing, creating, and querying tasks from both `trac` and `tatr` databases without leaving the editor.

## Requirements

- Zig `0.16.0`

## Build

```sh
zig build
```

The binary is produced at `zig-out/bin/trac`.

Run directly via the build system:

```sh
zig build run -- <args>
```

Run the test suite:

```sh
zig build test --summary all --verbose
# or
make test
```

## Quick start

```sh
trac init                          # create a tasks/ directory in the cwd
trac new "Fix the login bug" -t bug,auth -p 10
trac ls                            # list open tasks
```

## The spec

This section documents the on-disk format `trac` reads and writes — the same format described in the [tatr README](https://github.com/tsoding/tatr/blob/main/README.md), which `trac` implements.

### Layout

Each project has a `tasks/` folder at some ancestor directory, containing one sub-folder per task:

```
project/
+-...
+-tasks/
| +-20260824-215300/
| | +-TASK.md
| +-20260830-000403-rexim/
| | +-TASK.md
| | +-screenshot.png
| +-...
+-...
```

`trac init` creates this `tasks/` folder. Every other command walks up from the current directory looking for the nearest `tasks/` folder, so `trac` can be run from anywhere inside a project.

### HUID

Each task sub-folder is named with a Task ID of the form `[0-9]{8}-[0-9]{6}` — an 8-digit date (`YYYYMMDD`) and a 6-digit time (`HHMMSS`), e.g. `20260918-170610`. The full format also allows an optional suffix: `[0-9]{8}-[0-9]{6}(-[a-zA-Z0-9\-]*)?`, e.g. `20260918-170610-login` — handy for slapping on a per-person or per-branch suffix (`trac new ... -s rexim`) to avoid collisions when working in parallel/across branches.

This is called an HUID (Human-Unique IDentifier): unique as long as you're not generating two at faster-than-one-per-second, "human speed". Because IDs are unique and timestamp-derived, tasks created in parallel branches merge cleanly under git.

### TASK.md

Every task folder has a mandatory `TASK.md`:

```markdown
# <title>

- STATUS: (OPEN|CLOSED)
- PRIORITY: <number>
- TAGS: <comma-and-whitespace-separated-list-of-tags>
[other properties]

[description]
```

- `STATUS` is either `OPEN` or `CLOSED`. Use `TAGS` instead of inventing more statuses.
- `PRIORITY` is only meaningful as a relative sort key, not an absolute value — don't overthink the number.
- `TAGS` is a comma/whitespace-separated list, e.g. `TAGS: foo,,, hello  world` defines 3 tags (`foo`, `hello`, `world`).
- Any other `- KEY: value` line is preserved as an extra property and left alone by `trac` during mass updates (e.g. `untag`).
- The folder may contain other files as attachments; link to them from the description.

### Differences from tatr's spec

- `trac` doesn't currently read an optional `tasks/tags` tag-description file (tatr supports one for documenting tag meanings).
- `trac graph` (cross-reference graph) is a stub / not implemented yet.
- Output formats (`--json`, `--debug`) and the exact CLI surface are `trac`-specific.

## Commands

| Command   | Description |
|-----------|-------------|
| `init`    | Create the `tasks/` directory in the current working directory if it doesn't exist yet |
| `new`     | Create a new task |
| `ls`      | List open tasks, or tasks matching a query |
| `id`      | Print the HUID of the task if you're inside a task directory |
| `find`    | Find the task with a given HUID |
| `ref`     | Find referers (grep matches) of a task's HUID across the project |
| `summary` | Print a summary of task counts and tags |
| `untag`   | Remove tags from all tasks matching a query |
| `graph`   | Generate a graph of tasks cross-referring to each other (not implemented yet) |

Run `trac --help` or `trac <command> --help` to see the full usage for any command.

### `trac new [OPTIONS] [TITLE...]`

Creates a new task. If no title is given, defaults to "New task".

| Flag | Description |
| ------ | ------------- |
| `-t, --tags <str>` | Comma/space-separated tags to add to the task |
| `-b, --body <str>` | Body/description of the task |
| `-p, --priority <num>` | Priority of the task (default `100`, lower is higher priority) |
| `-s, --suffix <str>` | Optional suffix appended to the generated HUID |

```sh
trac new "Refactor query parser" -t refactor,parser -p 20 -b "Split parsing into smaller functions"
```

### `trac ls [OPTIONS] [QUERY...]`

Lists tasks, sorted by priority descending by default, and filtered by an optional query (see TQL below).

| Flag | Description |
| ------ | ------------- |
| `-c, --closed` | List closed tasks instead of open ones |
| `-A, --all` | List all tasks, including closed ones |
| `-a, --ascending` | Sort ascending instead of descending |
| `-i, --id` | Sort by ID instead of priority |
| `-d, --debug` | Print the parsed query's tokens/opcodes instead of running it |
| `-j, --json` | Output results as a JSON array |

```sh
trac ls                       # all open tasks
trac ls --closed              # all closed tasks
trac ls :bug                  # open tasks tagged "bug"
trac ls 'priority lt 20'      # open tasks with priority < 20
trac ls --json 'tagged and not :wip'
```

### Task Query Language (TQL)

`ls` and `untag` accept the same **Task Query Language (TQL)** designed for tatr's `tatr ls` — a small boolean query language over tasks, kept shell-friendly (square brackets instead of parens, `lt`/`le`/`gt`/`ge`/`eq`/`ne` instead of `<`/`<=`/`>`/`>=`/`==`/`!=`) so nothing needs escaping.

#### Examples

```sh
trac ls :bug                        # everything tagged bug
trac ls :bug and not :ui            # tagged bug, but not ui
trac ls not tagged                  # everything untagged
trac ls :bug and priority lt 50     # bugs with priority < 50
trac ls 'not [tagged or :bug]'
trac ls '[priority ge 5 or :urgent] and not :done'
```

#### Grammar

```
<expr>            ::= <or>
<or>              ::= <and> *('or' <and>)
<and>             ::= <compare> *('and' <compare>)
<compare>         ::= <primary> *(<compare-op> <primary>)
<compare-op>      ::= 'lt' | 'le' | 'gt' | 'ge' | 'eq' | 'ne'
<primary>         ::= <tag>
                    | '[' <expr> ']'
                    | 'not' <primary>
                    | 'any'
                    | 'tagged'
                    | 'priority'
                    | <number>
                    | <huid>
<tag>             ::= ':' 1*<any-character-except-whitespaces-and-square-brackets>
<number>          ::= ['-'] 1*<digit>
<huid>            ::= 8<digit> '-' 6<digit> [ '-' [ <huid-suffix> ] ]
<huid-suffix>     ::= 'A'-'Z' | 'a'-'z' | '-' | <digit>
<digit>           ::= '0'-'9'
```

#### Reference

| Expression | Description |
| - | - |
| `<a> or <b>` | True when `<a>` or `<b>` or both are true. |
| `<a> and <b>` | True when both `<a>` and `<b>` are true. |
| `:<tag>` | True when a task's `TAGS` property contains `<tag>`. |
| `not <expr>` | True when `<expr>` is false. |
| `tagged` | True when a task has at least one tag. |
| `<huid>` | True when a task's ID equals `<huid>`. |
| `any` | Always true. |
| `priority` | Priority of the task, as an integer (for use with the comparisons below). |
| `<a> lt <b>` / `gt` / `le` / `ge` / `eq` / `ne` | Less than / greater than / less-or-equal / greater-or-equal / equal / not equal. |

### `trac find <HUID> [OPTIONS]`

Looks up a single task by its exact HUID.

### `trac id`

Prints the HUID of the task directory you're currently inside (searches
ancestor directories), or fails if you're not inside one.

### `trac ref [HUID]`

Greps the project (excluding `.git`) for references to a task's HUID — useful
for finding where a task is mentioned in code or other tasks. Defaults to the
  task you're currently inside if no HUID is given.

### `trac summary [OPTIONS]`

Prints total task count, untagged count, and a per-tag breakdown for open (or
`--closed`) tasks.

### `trac untag [OPTIONS] [QUERY]`

Removes one or more tags (`-t/--tags`) from every task matched by `QUERY`.

```sh
trac untag -t wip 'priority gt 50'
```

## Credits

- **Spec & original tool**: [tsoding/tatr](https://github.com/tsoding/tatr) by
  [rexim](https://github.com/rexim) — the Tasks system layout, HUID scheme,
  `TASK.md` format, and Task Query Language design that `trac` implements.
