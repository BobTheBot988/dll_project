# DLL Project — Docker Compose Synthesis Stack

Automated Solidity smart contract synthesis using Foundry, Halmos, and `mcp-synthesizer`. Docker Compose starts Redis + a main container with all tooling, then runs Claude Code against the `test2` Foundry project.

## Architecture

```
docker-compose.yml
├── redis:7-alpine     — telemetry store for mcp-synthesizer
└── app                — main container (built from Dockerfile)
    ├── Foundry (forge, cast, anvil, chisel)
    ├── Halmos (symbolic verification)
    ├── git_diff_checker + hooks (pre/post tool guards)
    ├── mcp-synthesizer (mcp_synth, queue_controller, ...)
    ├── Claude CLI
    └── /workspace/test2 (volume-mounted from host ./test2)
```

**Synthesis flow:**
1. `populate_queue` enqueues 1 API-mode synthesis job for `test2` into Redis
2. `queue_controller` picks up the job, injects `mcpServers` config pointing to `mcp_synth`, spawns Claude Code with the prompt, monitors completion, verifies results, cleans up, and persists telemetry to Redis

## Prerequisites

- Docker (with Compose v2 plugin)
- An API provider exposing an Anthropic-compatible endpoint (Claude API, local LLM serving OpenAI-compatible API, etc.)

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_BASE_URL` | Yes | — | API endpoint URL (Anthropic-compatible) |
| `ANTHROPIC_AUTH_TOKEN` | Yes | — | API authentication token |
| `ANTHROPIC_MODEL` | No | `qwen3-solidity-27B-Q6_K.gguf` | Model name to use |

Both Claude CLI and `mcp_synth` auto-discover these variables.

## Quick Start

```bash
export ANTHROPIC_BASE_URL="https://api.example.com/anthropic"
export ANTHROPIC_AUTH_TOKEN="sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

docker compose up
```

This starts Redis, builds the `app` image, and runs synthesis on `test2`.

## Usage

### Background run

```bash
docker compose up -d
docker compose logs -f app
```

### One-shot run with env vars inline

```bash
docker compose run --rm \
  -e ANTHROPIC_BASE_URL="https://api.example.com/anthropic" \
  -e ANTHROPIC_AUTH_TOKEN="sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" \
  app
```

### Interactive debugging

```bash
docker compose run --rm --entrypoint /bin/bash app
```

Then run synthesis manually:

```bash
cd /workspace/test2
populate_queue --api-url "$ANTHROPIC_BASE_URL" --api-model-name "$ANTHROPIC_MODEL" --seed 42 --project test2 --prompt-file prompt.md --iterations 1
queue_controller --models-path /tmp --project-root /workspace --api-key "$ANTHROPIC_AUTH_TOKEN"
```

### Stop

```bash
docker compose down
```

Add `-v` to also remove Redis data volume.

## Services

### Redis (`dll-redis`)

- Port `6379` (exposed to host)
- Persistence via named volume `redis-data`
- Health check: `redis-cli ping`

### App (`dll-synthesis`)

- Build context: repository root
- Mounts `./test2` at `/workspace/test2` — edits on host are visible inside
- Depends on Redis (waits for healthy signal)
- Entrypoint: configure Claude Code, then run synthesis

## Customization

### Different model

```bash
export ANTHROPIC_MODEL="claude-sonnet-4-20250514"
docker compose up
```

### Any Anthropic-compatible provider

Any provider serving the Anthropic (or OpenAI) API format works. Examples:

- Local LLM (llama.cpp, vLLM, etc.)
- Anthropic Claude API
- Compatible third-party endpoints

## Synthesis Prompt

The synthesis uses `test2/prompt.md` as the job prompt (sent to Claude Code via `populate_queue`). The `queue_controller` also reads it as an optional system prompt appended to the Claude invocation. Edit this file to change the synthesis behavior.

## Verification

```bash
# Check service status
docker compose ps

# View synthesis progress
docker compose logs app

# Check Redis connectivity
docker compose exec app redis-cli -h redis ping

# Verify tooling inside container
docker compose exec app forge --version
docker compose exec app halmos --help
docker compose exec app mcp_synth --help
docker compose exec app claude --version

# Check synthesis telemetry in Redis
docker compose exec redis redis-cli KEYS '*'
```

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|-------------|-----|
| `ANTHROPIC_BASE_URL: error` | Env var not set | Export both `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` |
| Redis connection refused | Redis not ready yet | Entrypoint retries automatically; check `docker compose logs redis` |
| Build fails on Rust crates | Network or deps | Run `docker compose build --no-cache app` for clean rebuild |
| `forge: not found` | Foundryup failed | Check `docker compose logs app` for foundryup output |
| Port 6379 conflict on host | Local Redis running | Change ports in `docker-compose.yml` (e.g., `"6380:6379"`) |
| Synthesis hangs | Model endpoint unreachable | Verify `ANTHROPIC_BASE_URL` is reachable from container |
