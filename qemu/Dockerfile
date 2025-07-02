# Dockerfile for znvme QEMU test environment
# This provides a containerized environment for running QEMU with virtual NVMe devices
# for znvme development and testing

FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies in a more efficient way
RUN apt-get update && apt-get install -y --no-install-recommends \
    # QEMU and virtualization tools
    qemu-system-x86 \
    qemu-utils \
    # Development tools
    gdb \
    build-essential \
    git \
    curl \
    wget \
    ca-certificates \
    # Networking utilities
    openssh-client \
    netcat \
    # System utilities
    sudo \
    vim \
    # Clean up to reduce image size
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* /var/tmp/*

# Install Zig toolchain
RUN mkdir -p /opt/zig && \
    cd /opt/zig && \
    wget -q https://ziglang.org/download/0.14.1/zig-linux-x86_64-0.14.1.tar.xz && \
    tar -xf zig-linux-x86_64-0.14.1.tar.xz && \
    mv zig-linux-x86_64-0.14.1 current && \
    rm zig-linux-x86_64-0.14.1.tar.xz

# Add Zig to PATH
ENV PATH="/opt/zig/current:${PATH}"

# Create a non-root user for development
RUN useradd -m -s /bin/bash -G sudo znvme && \
    echo "znvme ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create working directories
RUN mkdir -p /workspace/znvme /workspace/qemu-data && \
    chown -R znvme:znvme /workspace

# Set environment variables for QEMU
ENV QEMU_NO_KVM=false
ENV QEMU_MEMORY=2G
ENV QEMU_CPUS=2
ENV QEMU_VNC=:1

# Expose ports
# 2222: SSH forwarding to guest
# 5901: VNC display
# 4321: QEMU monitor/serial console
EXPOSE 2222 5901 4321

# Switch to znvme user and set working directory
USER znvme
WORKDIR /workspace/znvme

# Copy znvme source code
COPY --chown=znvme:znvme . .

# Set working directory to qemu folder
WORKDIR /workspace/znvme/qemu

# Default command: show help
CMD ["./qemu-manager.sh", "help"]