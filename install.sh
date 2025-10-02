#!/bin/bash
set -e

# Check dependencies
if ! command -v gcc >/dev/null || ! dpkg -l | grep -q libc6-dev; then
    echo "Installing gcc and libc6-dev..."
    sudo apt update && sudo apt install -y build-essential || { echo "Failed to install dependencies"; exit 1; }
fi

# Compile hook.c if hook.so doesn't exist
if [ ! -f hook.so ]; then
    echo "Compiling hook.c..."
    gcc -shared -fPIC -o hook.so hook.c -ldl || { echo "Compilation failed"; exit 1; }
fi

# Copy hook.so
sudo mkdir -p /usr/local/lib || { echo "Failed to create /usr/local/lib"; exit 1; }
sudo cp hook.so /usr/local/lib/hook.so || { echo "Failed to copy hook.so"; exit 1; }
sudo chown root:syslog /usr/local/lib/hook.so
sudo chmod 644 /usr/local/lib/hook.so

# Edit rsyslog.service non-interactively
SERVICE_FILE="/etc/systemd/system/rsyslog.service"
if [ ! -f "$SERVICE_FILE" ]; then
    echo "Creating $SERVICE_FILE from default..."
    sudo mkdir -p /etc/systemd/system
    sudo cp /lib/systemd/system/rsyslog.service "$SERVICE_FILE" || { echo "Failed to copy rsyslog.service"; exit 1; }
fi
# Backup service file
sudo cp "$SERVICE_FILE" "${SERVICE_FILE}.bak" || { echo "Failed to backup rsyslog.service"; exit 1; }
# Ensure [Service] section exists
if ! grep -q '^\[Service\]' "$SERVICE_FILE"; then
    echo "Adding [Service] section to $SERVICE_FILE..."
    echo -e "\n[Service]" | sudo tee -a "$SERVICE_FILE" > /dev/null
fi
# Add Environment and NoNewPrivileges lines only if missing
if ! grep -q 'Environment="LD_PRELOAD=/usr/local/lib/hook.so"' "$SERVICE_FILE"; then
    sudo sed -i '/\[Service\]/a Environment="LD_PRELOAD=/usr/local/lib/hook.so"' "$SERVICE_FILE" || { echo "Failed to add LD_PRELOAD"; exit 1; }
fi
if ! grep -q 'Environment="NOOPER_USERNAME=example_user"' "$SERVICE_FILE"; then
    sudo sed -i '/\[Service\]/a Environment="NOOPER_USERNAME=example_user"' "$SERVICE_FILE" || { echo "Failed to add NOOPER_USERNAME"; exit 1; }
fi
if ! grep -q 'NoNewPrivileges=no' "$SERVICE_FILE"; then
    sudo sed -i '/\[Service\]/a NoNewPrivileges=no' "$SERVICE_FILE" || { echo "Failed to add NoNewPrivileges"; exit 1; }
fi

# Edit AppArmor
APPARMOR_FILE="/etc/apparmor.d/usr.sbin.rsyslogd"
if [ -f "$APPARMOR_FILE" ] && sudo aa-status | grep -q rsyslog; then
    echo "Configuring AppArmor..."
    sudo cp "$APPARMOR_FILE" "${APPARMOR_FILE}.bak" || { echo "Failed to backup AppArmor file"; exit 1; }
    if ! grep -q '/usr/local/lib/hook.so mr,' "$APPARMOR_FILE"; then
        sudo sed -i '/\/usr\/sbin\/rsyslogd/a \ \ \/usr\/local\/lib\/hook.so mr,' "$APPARMOR_FILE" || { echo "Failed to edit AppArmor"; exit 1; }
        sudo apparmor_parser -r "$APPARMOR_FILE" || { echo "AppArmor reload failed"; exit 1; }
    fi
fi

# Restart rsyslog
sudo systemctl daemon-reload || { echo "Failed to reload systemd"; exit 1; }
sudo systemctl restart rsyslog || { echo "Failed to restart rsyslog"; exit 1; }

echo "Installation complete."
