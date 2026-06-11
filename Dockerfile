# Stage 1: Build Rust projects (hooks, git_diff_checker, mcp-synthesizer)
FROM rust:1.85-alpine3.21 AS rust-builder

RUN apk add --no-cache \
    alpine-sdk~=1 \
    pkgconfig~=2 \
    openssl-dev~=3 \
    openssl-libs-static~=3 \
    musl-dev~=1.2 \
    git~=2

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
FROM alpine:3.23.4

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++~=14 \
    git~=2 \
    nodejs~=22 \
    npm~=10 \
    python3~=3.12 \
    py3-pip~=24 \
    curl~=8 \
    bash~=5 \
    redis~=7

# Install Foundry via foundryup
RUN curl -L https://foundry.paradigm.xyz | bash && \
    foundryup && \
    cp ~/.foundry/bin/forge /usr/local/bin/forge && \
    cp ~/.foundry/bin/cast /usr/local/bin/cast && \
    cp ~/.foundry/bin/anvil /usr/local/bin/anvil && \
    cp ~/.foundry/bin/chisel /usr/local/bin/chisel

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

# Set up Python virtual environment for Halmos
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Upgrade pip and install Halmos
RUN pip install --no-cache-dir --upgrade pip setuptools==61.0 wheel==0.42.0 && \
    pip install --no-cache-dir halmos==0.1.0

# Install Claude CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# Ensure Claude CLI is on PATH
ENV PATH="/root/.claude/bin:$PATH"

# Verify installations
RUN forge --version && \
    halmos --help && \
    claude --version 2>/dev/null || true

WORKDIR /workspace

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
