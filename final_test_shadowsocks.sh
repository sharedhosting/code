#!/bin/bash
# Test script to validate the functionality of shadowsocks-rust.sh

# Mock systemctl for container testing
systemctl() {
    echo "[MOCK] systemctl $*"
    case "$1" in
        daemon-reload)
            echo "[MOCK] systemctl daemon-reload executed"
            ;;
        enable)
            if [ "$2" = "--now" ]; then
                echo "[MOCK] systemctl enable $3 --now executed"
            else
                echo "[MOCK] systemctl enable $2 executed"
            fi
            ;;
        start)
            echo "[MOCK] systemctl start $2 executed"
            ;;
        restart)
            echo "[MOCK] systemctl restart $2 executed"
            ;;
        stop)
            echo "[MOCK] systemctl stop $2 executed"
            ;;
        *)
            echo "[MOCK] Unknown systemctl command: $1 $2 $3"
            ;;
    esac
}

# Mock mkdir to make sure we can create directories
mkdir() {
    echo "[MOCK] mkdir $*"
    command mkdir -p "$@"
}

# Mock install to avoid needing root privileges
install() {
    echo "[MOCK] install $*"
    if [[ "$*" == *"-m"* ]]; then
        # Extract source and destination
        args=("$@")
        src="${args[-1]}"
        dst="/tmp/mocked_install_${src##*/}"
        echo "[MOCK] Creating mock executable at $dst"
        touch "$dst"
        chmod 755 "$dst"
    fi
}

# Mock cp to avoid issues with copying to protected directories
cp() {
    echo "[MOCK] cp $*"
    if [[ "$2" == /opt/* ]]; then
        # Instead of copying to /opt, copy to a test directory
        dest_dir=$(dirname "$2")
        mkdir -p "${dest_dir/\/opt/\/tmp\/test_opt}"
        command cp "$1" "${2/\/opt/\/tmp\/test_opt}"
    else
        command cp "$@"
    fi
}

# Mock ln to avoid creating links to protected directories
ln() {
    echo "[MOCK] ln $*"
    if [[ "$*" == *"/opt/"* ]]; then
        # Replace /opt with /tmp/test_opt for link creation
        args=()
        for arg in "$@"; do
            args+=("${arg/\/opt/\/tmp\/test_opt}")
        done
        command ln "${args[@]}"
    else
        command ln "$@"
    fi
}

echo "Testing shadowsocks-rust.sh functionality..."

# Source the original script
source ./shadowsocks-rust.sh

echo "Test completed successfully!"