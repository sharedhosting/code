#!/bin/bash
set -e

App_dir="/opt/shadowsocks"
mkdir -p "$App_dir"

SYSTEMD_SERVICE="/etc/systemd/system/shadowsocks.service"
SYSTEMD_UPGRADE_SERVICE="/etc/systemd/system/shadowsocks-upgrade.service"
SYSTEMD_UPGRADE_TIMER="/etc/systemd/system/shadowsocks-upgrade.timer"
SYSTEMD_RESTART_TIMER="/etc/systemd/system/shadowsocks-restart.timer"

check_system() {
    echo "Checking system..."

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l|armhf) ARCH="armv7" ;;
        *)
            echo "Unsupported CPU architecture: $ARCH"
            exit 1
            ;;
    esac

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VER=$VERSION_ID
    else
        echo "Cannot detect OS version"
        exit 1
    fi

    case "$OS_NAME" in
        debian|ubuntu) ;;
        *)
            echo "Unsupported OS: $OS_NAME"
            exit 1
            ;;
    esac

    if [ "$OS_NAME" = "debian" ] && [ "${OS_VER%%.*}" -lt 10 ]; then
        echo "Debian version too low"
        exit 1
    fi

    if [ "$OS_NAME" = "ubuntu" ] && [ "${OS_VER%%.*}" -lt 20 ]; then
        echo "Ubuntu version too low"
        exit 1
    fi
}

install_tools() {
    apt update && apt install -y curl unzip jq
}

get_local_version() {
    if [ -x "$App_dir/ssserver" ]; then
        "$App_dir/ssserver" -V 2>/dev/null | awk '{print $2}'
    else
        echo "none"
    fi
}

get_latest_version() {
    curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest \
        | jq -r '.tag_name'
}

download_latest() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l|armhf) ARCH="armv7" ;;
    esac

    URL=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest \
        | jq -r ".assets[] | select(.name | test(\"$ARCH-unknown-linux-gnu.tar.xz$\")) | .browser_download_url")

    curl -L "$URL" -o /tmp/ssr.tar.xz
    tar -xf /tmp/ssr.tar.xz -C /tmp
}

install_ss() {
    check_system
    install_tools
    download_latest

    install -m 755 /tmp/ssserver "$App_dir/ssserver"

    cat > "$App_dir/config.json" <<EOF
{
    "server": "::",
    "server_port": 20443,
    "password": "A9cF9aFFbB11c72c49fC10bDF0f75eeD",
    "method": "aes-128-gcm",
    "mode": "tcp_only"
}
EOF

    cat > "$App_dir/shadowsocks.service" <<EOF
[Unit]
Description=Shadowsocks-Rust Server
After=network.target

[Service]
ExecStart=$App_dir/ssserver -c $App_dir/config.json
Restart=on-failure
User=nobody
Group=nogroup
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF

    ln -sf "$App_dir/shadowsocks.service" "$SYSTEMD_SERVICE"

    cat > "$App_dir/shadowsocks-upgrade.service" <<EOF
[Unit]
Description=Upgrade Shadowsocks-Rust

[Service]
Type=oneshot
ExecStart=$App_dir/shadowsocks-rust.sh -up
EOF

    ln -sf "$App_dir/shadowsocks-upgrade.service" "$SYSTEMD_UPGRADE_SERVICE"

    cat > "$SYSTEMD_UPGRADE_TIMER" <<EOF
[Unit]
Description=Monthly upgrade for Shadowsocks-Rust

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    cat > "$SYSTEMD_RESTART_TIMER" <<EOF
[Unit]
Description=Weekly restart of Shadowsocks service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now shadowsocks
    systemctl enable --now shadowsocks-upgrade.timer
    systemctl enable --now shadowsocks-restart.timer
}

upgrade_ss() {
    check_system

    local_version=$(get_local_version)
    latest_version=$(get_latest_version)

    if [ "$local_version" = "$latest_version" ]; then
        echo "Already latest version"
        return
    fi

    download_latest
    systemctl stop shadowsocks
    install -m 755 /tmp/ssserver "$App_dir/ssserver"
    systemctl start shadowsocks
}

update_conf_from_url() {
    url="$1"
    curl -L "$url" -o "$App_dir/config.json"
    systemctl restart shadowsocks
}

case "$1" in
    -up)
        upgrade_ss
        ;;
    -http://*|-https://*)
        update_conf_from_url "${1#-}"
        ;;
    *)
        install_ss
        ;;
esac
