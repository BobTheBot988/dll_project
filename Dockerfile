# Stage 1: Build Rust projects (hooks, git_diff_checker, mcp-synthesizer)
FROM rust:slim-trixie AS rust-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
  pkg-config \
  libssl-dev \
  libclang-dev \
  git \
  make \
  cmake \ 
  g++ \
  curl \
  perl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy all Rust project sources
COPY hooks /build/hooks
COPY git_diff_checker /build/git_diff_checker
COPY mcp-synthesizer /build/mcp-synthesizer

# Step 1: Build git_diff_checker (no internal path deps)
RUN cargo build --release --manifest-path /build/git_diff_checker/Cargo.toml

# Step 2: Patch hooks/post/Cargo.toml to use local git_diff_checker path instead of git URL
RUN sed -i 's|git_diff_checker = { git = "https://github.com/BobTheBot988/git_diff_checker.git" }|git_diff_checker = { path = "/build/git_diff_checker" }|' /build/hooks/post/Cargo.toml

# Step 3: Build hooks workspace
RUN cargo build --release --manifest-path /build/hooks/Cargo.toml

# Step 4: Build mcp-synthesizer
RUN cargo build --release --manifest-path /build/mcp-synthesizer/Cargo.toml

# Stage 2: Final runtime image
FROM debian:trixie-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  git \
  nodejs \
  npm \
  python3 \
  python3-pip \
  cmake \
  make \
  curl \
  bash \
  redis-server \
  clang \
  g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Foundry binaries
RUN curl -L https://github.com/foundry-rs/foundry/releases/download/v1.7.1/foundry_v1.7.1_linux_amd64.tar.gz -o /tmp/foundry.tar.gz && \
  tar -xzf /tmp/foundry.tar.gz -C /usr/local/bin/ && \
  rm /tmp/foundry.tar.gz

# Copy Rust binaries from stage 1
COPY --from=rust-builder /build/git_diff_checker/target/release/git_diff_checker /usr/local/bin/git_diff_checker
COPY --from=rust-builder /build/hooks/target/release/pre_hook /usr/local/bin/pre_hook
COPY --from=rust-builder /build/hooks/target/release/post_hook /usr/local/bin/post_hook
COPY --from=rust-builder /build/hooks/target/release/stop_hook /usr/local/bin/stop_hook
COPY --from=rust-builder /build/mcp-synthesizer/target/release/mcp_synth /usr/local/bin/mcp_synth
COPY --from=rust-builder /build/mcp-synthesizer/target/release/populate_queue /usr/local/bin/populate_queue
COPY --from=rust-builder /build/mcp-synthesizer/target/release/queue_controller /usr/local/bin/queue_controller
COPY --from=rust-builder /build/mcp-synthesizer/target/release/stats_export /usr/local/bin/stats_export
COPY --from=rust-builder /build/mcp-synthesizer/target/release/migrate /usr/local/bin/migrate

# Create agent user and add to all groups
RUN useradd -m -s /bin/bash agent && \
  for g in $(getent group | cut -d: -f1); do \
  usermod -aG "$g" agent 2>/dev/null || true; \
  done

# Agent creates own workspace directory (ensures ownership)
USER agent
RUN mkdir -p /home/agent/workspace/test2

COPY test2/ /home/agent/workspace/test2

# Install uv package manager and Halmos via uv tool (as agent)
USER agent
WORKDIR /home/agent
RUN curl -LsSf https://astral.sh/uv/install.sh -o /tmp/uv.sh && \
  sh /tmp/uv.sh && \
  . $HOME/.local/bin/env && \
  uv tool install --python 3.12 halmos==0.3.3 && \
  rm /tmp/uv.sh

# Install Claude CLI (as agent)
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh && \
  bash /tmp/claude-install.sh && \
  rm /tmp/claude-install.sh

# Set PATH for agent
ENV PATH="/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin"

# Verify installations
RUN forge --version && \
  halmos --help && \
  claude --version 2>/dev/null || true

# Switch back to root for system-level operations
USER root

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown agent: --recursive /home/agent/workspace 

# Switch to agent as default user
USER agent
RUN chmod u+wrx --recursive /home/agent/workspace 
ENTRYPOINT ["/entrypoint.sh"]
# ENTRYPOINT ["/bin/bash"]
