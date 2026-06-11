# AGENTS.md

This file provides guidance to AGENTS when working with code in this repository.

## Project Overview

Orchestration repo for automated Solidity smart contract synthesis. Docker Compose stack starts Redis + a main container with all tooling, enqueues a synthesis job via `populate_queue`, and processes it via `queue_controller` which spawns Claude Code with `mcp_synth` MCP tools.

## Submodules

| Path                | Purpose                                                                                                                  | Build                                                     |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------- |
| `hooks/`            | Rust CLI hooks (pre/post/stop) for Claude Code tool-use guards. Whitelist-based write protection + selective git revert. | `cargo build --manifest-path hooks/Cargo.toml`            |
| `git_diff_checker/` | Rust CLI + lib: detects LLM modification of original git-tracked lines, selectively reverts them.                        | `cargo build --manifest-path git_diff_checker/Cargo.toml` |
| `mcp-synthesizer/`  | Rust MCP server (`mcp_synth`) + queue controller + job enqueuer + stats. 5 binaries, edition 2024.                       | `cargo build --manifest-path mcp-synthesizer/Cargo.toml`  |
| `test2/`            | Foundry Solidity project (Auction.sol, symbolic tests with Halmos). Target for synthesis.                                | `forge build` (inside container)                          |

## Commands

### Docker build & run

```bash
# Full stack
docker compose up -d

# Rebuild app image from scratch
docker compose build --no-cache app

# Interactive debug
docker compose run --rm --entrypoint /bin/bash app

# View logs
docker compose logs -f app
```

### Local Rust build (submodules)

```bash
# git_diff_checker + hooks
cd git_diff_checker && just build   # or: cargo build --release

# mcp-synthesizer
cd mcp-synthesizer && just build    # or: cargo build --release
```

### Run tests

```bash
# git_diff_checker
cd git_diff_checker && cargo test -- --test-threads 1

# mcp-synthesizer (requires Redis)
cd mcp-synthesizer && just test     # starts Redis, runs tests, stops Redis
# or manually:
TEST_REDIS_URL=redis://localhost:6379/1 cargo test -- --test-threads 1
```

### Lint

```bash
cargo clippy                                        # git_diff_checker
cargo clippy --manifest-path hooks/Cargo.toml        # hooks
cargo clippy --manifest-path mcp-synthesizer/Cargo.toml  # mcp-synthesizer
cargo fmt                                           # formatting (mcp-synthesizer)
```

### Run single test

```bash
cargo test test_parse_hunk_header -- --test-threads 1
```

## Architecture

### Synthesis flow (docker compose up)

```
entrypoint.sh
  ├── Wait for Redis (redis-cli ping loop)
  ├── populate_queue      — Enqueue 1 API-mode job for test2
  │   ├── --api-url       → ANTHROPIC_BASE_URL
  │   ├── --api-model-name → ANTHROPIC_MODEL
  │   ├── --project test2, --prompt-file /workspace/test2/prompt.md
  │   └── writes HSET + ZADD to Redis
  └── queue_controller   — Process queue until empty
      ├── Health checks (Redis ping, claude binary, project dir)
      ├── load_job → reads HGETALL from Redis
      ├── setup_claude_settings → writes .claude/settings.local.json
      │   ├── mcpServers: mcp_synth (stdio transport)
      │   └── customModel: url + apiKey + modelName
      ├── spawn_claude → claude -p --mcp-config --dangerously-skip-permissions
      ├── Monitor completion (API mode: blocking wait)
      ├── Cleanup (restore settings, remove job from queue)
      └── Persist usage metrics + synthesis trial to Redis
```

### Guard system (hooks + git_diff_checker)

```
Agent modifies file
  → PreToolUse hook (directory whitelist, Bash command scan)
    → [denied] Block
    → [allowed] File written
  → PostToolUse hook (runs git_diff_checker --all)
    → [original lines modified] Selective revert + Block
    → [new lines only] Allow continue
```

This protects "Golden Commit" lines from LLM agents. Pre-hook whitelist default: `src/`. Hooks are Rust binaries compiled from the `hooks/` submodule.

### mcp-synthesizer binaries

| Binary             | Path                                 | Purpose                                               |
| ------------------ | ------------------------------------ | ----------------------------------------------------- |
| `mcp_synth`        | `src/bin/mcp_synth.rs`               | MCP server (stdio), exposes forge/halmos as MCP tools |
| `queue_controller` | `src/bin/queue_controller.rs`        | Orchestrator: queue → Claude Code → cleanup           |
| `populate_queue`   | `src/bin/populate_queue.rs`          | Batch enqueue synthesis jobs into Redis               |
| `stats_export`     | `src/bin/stats_export.rs`            | Statistical analysis of synthesis experiments         |
| `migrate`          | `src/bin/migrate_sqlite_to_redis.rs` | SQLite-to-Redis data migration                        |

### Database (Redis)

Two execution modes for synthesis jobs:

- **API mode**: Uses `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` for external model endpoint. No Slurm dependency.
- **Cluster mode**: Submits Slurm job on remote cluster for model serving, establishes SSH tunnel, monitors job health. `queue_controller --models-path` etc.

Redis stores projects, test runs, synthesis trials, and queue state under `cluster_runs` sorted set and `{model}:{job_id}` hashes. Tests use DB 1 (`FLUSHDB` per module). Real runs use DB 0.

### Key patterns

- **Strict Clippy in git_diff_checker**: `unwrap_used` deny, `expect_used` deny, `question_mark` deny, `map_flatten` deny, `single_match` deny. Use explicit `match` for all `Result` handling.
- **mcp-synthesizer**: Edition 2024, musl target for static linking. Never delete TODO comments.
- **Ruby Docker compose:** `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` are required env vars. `ANTHROPIC_MODEL` defaults to `qwen3-solidity-27B-Q6_K.gguf`.
