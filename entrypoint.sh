#!/bin/bash
set -e

# Phase 0: If running as root (docker-compose override), clean up and drop to agent
if [ "$(id -u)" = "0" ]; then
  echo "=== DLL Synthesis Entrypoint (init) ==="
  echo "[INIT] Running as root — cleaning workspace..."
  rm -f /workspace/test2/*.jsonl 2>/dev/null || true
  chown -R agent:agent /workspace 2>/dev/null || true
  echo "[INIT] Dropping privileges to agent..."
  exec su -s /bin/bash -p agent -c "HOME=/home/agent exec /entrypoint.sh"
fi

echo "=== DLL Synthesis Entrypoint ==="

# Phase 1: Wait for Redis
echo "[1/4] Wait for Redis..."
until redis-cli -h redis ping 2>/dev/null | grep -q PONG; do
  sleep 1
done
echo "Redis ready."

# Phase 2: Validate environment
echo "[2/4] Validate configuration..."
: "${ANTHROPIC_BASE_URL:?Must set ANTHROPIC_BASE_URL}"
: "${ANTHROPIC_AUTH_TOKEN:?Must set ANTHROPIC_AUTH_TOKEN}"
MODEL="${ANTHROPIC_MODEL:-qwen3-solidity-27B-Q6_K.gguf}"

# Phase 3: Enqueue one synthesis job for test2
echo "[3/4] Enqueue test2 synthesis job..."
populate_queue \
  --api-url "$ANTHROPIC_BASE_URL" \
  --api-model-name "$MODEL" \
  --seed 42 \
  --project test2 \
  --prompt-file /home/agent/workspace/test2/prompt.md \
  --iterations 1 \
  --redis-url redis://redis:6379

# Phase 4: Process the queue
echo "[4/4] Run queue controller..."
echo "Queue controller handles: settings injection, MCP config, Claude invocation,"
echo "synthesis monitoring, cleanup, and telemetry persistence."
queue_controller \
  --models-path /tmp \
  --project-root /home/agent/workspace \
  --redis-url redis://redis:6379 \
  --api-key "$ANTHROPIC_AUTH_TOKEN"

echo "=== Synthesis complete ==="
