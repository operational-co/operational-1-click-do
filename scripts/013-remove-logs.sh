#!/bin/bash
if dpkg -l | grep -q droplet-agent; then
  apt-get purge -y droplet-agent
fi
rm -rf /opt/digitalocean
echo "✅ droplet-agent removed"

echo "🧹 Cleaning up log files..."

# Clear UFW and kernel logs
truncate -s 0 /var/log/kern.log || true
truncate -s 0 /var/log/ufw.log || true

# Optionally clear other common logs
truncate -s 0 /var/log/syslog || true
truncate -s 0 /var/log/auth.log || true

echo "✅ Log files cleared"