#!/bin/bash
# Mock systemctl for testing in container
systemctl() {
    echo "[MOCK] systemctl $*"
}

# Mock other commands if needed
mkdir -p /opt/shadowsocks-rust

# Run the original script
bash shadowsocks-rust.sh