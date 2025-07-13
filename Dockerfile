# Multi-stage Dockerfile for znvme
FROM ubuntu:22.04 AS builder

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    xz-utils \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy the Zig version file
COPY .zigversion /tmp/.zigversion

# Install Zig based on the version in .zigversion
RUN ZIG_VERSION=$(cat /tmp/.zigversion | tr -d '\n') && \
    curl -k -L "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz && \
    cd /tmp && \
    tar -xf zig.tar.xz && \
    mv zig-x86_64-linux-${ZIG_VERSION} /usr/local/zig && \
    ln -s /usr/local/zig/zig /usr/local/bin/zig && \
    rm -rf /tmp/zig.tar.xz

# Verify Zig installation
RUN zig version

# Set working directory
WORKDIR /app

# Copy source code
COPY . .

# Pre-fetch dependencies (try with timeout)
RUN timeout 30 zig build --fetch-deps || echo "Dependency fetch timed out, proceeding with local build"

# Build the application
RUN zig build

# Runtime stage
FROM ubuntu:22.04

# Install runtime dependencies for VFIO and NVMe access
RUN apt-get update && apt-get install -y \
    nvme-cli \
    && rm -rf /var/lib/apt/lists/*

# Copy the built application from builder stage
COPY --from=builder /app/zig-out/bin/znvme /usr/local/bin/znvme

# Set up a non-root user for better security
RUN useradd -r -s /bin/false znvme

# The application requires privileged access for VFIO
# This should be run with appropriate Docker capabilities
ENTRYPOINT ["/usr/local/bin/znvme"]