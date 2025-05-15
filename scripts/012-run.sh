#!/bin/bash
set -e

cd /operational.co

# Load NVM and use Node 20
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm use 20

# Build frontend
npm run build

# Move to web root
echo "📦 Moving build to /var/www/html..."
rm -rf /var/www/html/*
cp -r dist/* /var/www/html/

# Start MySQL
echo "🧩 Starting MySQL..."
systemctl start mysql

if systemctl is-active --quiet mysql; then
  echo "✅ MySQL started successfully"
else
  echo "❌ Failed to start MySQL"
fi
