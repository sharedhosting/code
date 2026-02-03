#!/bin/bash
set -e

APP_NAME="shadowsocks-rust"
App_dir="/opt/$APP_NAME"
mkdir -p "$App_dir"

# Copy script to app directory so it can be referenced by systemd services
cp "$0" "$App_dir/$APP_NAME.sh"
chmod +x "$App_dir/$APP_NAME.sh"

SYSTEMD_SERVICE="/etc/systemd/system/${APP_NAME}.service"
SYSTEMD_UPGRADE_SERVICE="/etc/systemd/system/${APP_NAME}-upgrade.service"
SYSTEMD_UPGRADE_TIMER="/etc/systemd/system/${APP_NAME}-upgrade.timer"
SYSTEMD_RESTART_SERVICE="/etc/systemd/system/${APP_NAME}-restart.service"
SYSTEMD_RESTART_TIMER="/etc/systemd/system/${APP_NAME}-restart.timer"

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
    # Use the previously determined ARCH variable
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
    
    # Create default config if it doesn't exist
    if [ ! -f "$App_dir/config.json" ]; then
        cat > "$App_dir/config.json" <<EOF
{
    "server": "::",
    "server_port": 20443,
    "password": "A9cF9aFFbB11c72c49fC10bDF0f75eeD",
    "method": "aes-128-gcm",
    "mode": "tcp_only"
}
EOF
    fi

    cat > "$App_dir/${APP_NAME}.service" <<EOF
[Unit]
Description=${APP_NAME} Server
After=network.target

[Service]
Type=simple
ExecStart=$App_dir/ssserver -c $App_dir/config.json
Restart=always
RestartSec=3
User=nobody
Group=nogroup
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF

    ln -sf "$App_dir/${APP_NAME}.service" "$SYSTEMD_SERVICE"

    cat > "$App_dir/${APP_NAME}-upgrade.service" <<EOF
[Unit]
Description=Upgrade ${APP_NAME}

[Service]
Type=oneshot
ExecStart=/bin/bash -c '$App_dir/$APP_NAME.sh -up'
RemainAfterExit=yes
EOF

    ln -sf "$App_dir/${APP_NAME}-upgrade.service" "$SYSTEMD_UPGRADE_SERVICE"

    cat > "$App_dir/${APP_NAME}-restart.service" <<EOF
[Unit]
Description=Restart ${APP_NAME}

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'systemctl restart $APP_NAME'
RemainAfterExit=yes
EOF

    ln -sf "$App_dir/${APP_NAME}-restart.service" "$SYSTEMD_RESTART_SERVICE"

    cat > "$App_dir/${APP_NAME}-upgrade.timer" <<EOF
[Unit]
Description=Monthly upgrade for ${APP_NAME}

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    ln -sf "$App_dir/${APP_NAME}-upgrade.timer" "$SYSTEMD_UPGRADE_TIMER"

    cat > "$App_dir/${APP_NAME}-restart.timer" <<EOF
[Unit]
Description=Weekly restart of ${APP_NAME}

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    ln -sf "$App_dir/${APP_NAME}-restart.timer" "$SYSTEMD_RESTART_TIMER"

    systemctl daemon-reload
    systemctl enable --now ${APP_NAME}.service
    systemctl enable --now ${APP_NAME}-upgrade.timer
    systemctl enable --now ${APP_NAME}-restart.timer
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
    systemctl stop $APP_NAME
    install -m 755 /tmp/ssserver "$App_dir/ssserver"
    systemctl start $APP_NAME
}

update_conf_from_url() {
    url="$1"
    curl -L "$url" -o "$App_dir/config.json"
    systemctl restart $APP_NAME
}

update_conf_from_file() {
    conf_file="$1"
    cp "$conf_file" "$App_dir/config.json"
    systemctl restart $APP_NAME
}

case "$1" in
    -up)
        upgrade_ss
        ;;
    -http://*|-https://*)
        update_conf_from_url "${1#-}"
        ;;
    -config)
        if [ -n "$2" ]; then
            if [[ "$2" == http://* || "$2" == https://* ]]; then
                update_conf_from_url "$2"
            else
                update_conf_from_file "$2"
            fi
        else
            echo "Error: No configuration file specified with -config"
            exit 1
        fi
        ;;
    *)
        install_ss
        ;;
esac
