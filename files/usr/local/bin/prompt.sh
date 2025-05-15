#!/bin/bash
set -e

if [ ! -t 0 ]; then
  echo "⛔ prompt.sh requires an interactive terminal. Aborting."
  exit 1
fi

# Load MySQL password from digitalocean password file
source /root/.digitalocean_password

REPO_DIR="/operational.co"
APP_DIR="$REPO_DIR/app"
ENV_FILE="$REPO_DIR/backend/.env"
FRONTEND_ENV_FILE="$APP_DIR/.env"
MYIP=$(hostname -I | awk '{print $1}')

echo "------------------------"
echo ""
echo "🚀 Welcome to Operational.co setup!"
echo "This script will set up your instance, including VAPID keys, domains, SSL certs, Nginx, and PM2"
echo "👉 Make sure your domain(s) A record point to: $MYIP"
echo ""
echo "------------------------"

# Ask for email and both domains
while true; do
  read -rp "📧 Enter your admin email address: " EMAIL
  [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && break
  echo "❌ Invalid email format. Try again."
done

read -rp "🌐 Enter your FRONTEND domain (e.g. app.example.com): " FRONTEND_DOMAIN
read -rp "🔧 Enter your BACKEND domain (e.g. api.example.com): " BACKEND_DOMAIN

# Generate VAPID keys
echo "🔐 Generating VAPID keys..."
VAPID_JSON=$(web-push generate-vapid-keys --json)
VAPID_PUBLIC_KEY=$(echo "$VAPID_JSON" | jq -r '.publicKey')
VAPID_PRIVATE_KEY=$(echo "$VAPID_JSON" | jq -r '.privateKey')

# Generate secret
SECRET=$(openssl rand -hex 32)

# Write backend .env
mkdir -p "$REPO_DIR"
echo "📝 Writing backend .env..."
cat > "$ENV_FILE" <<EOF
DATABASE_URL="mysql://operational:${operational_mysql_pass}@localhost:5999/operational"
SECRET=$SECRET
VAPID_EMAIL=mailto:$EMAIL
VAPID_PUBLIC_KEY=$VAPID_PUBLIC_KEY
VAPID_PRIVATE_KEY=$VAPID_PRIVATE_KEY
ADMIN_EMAIL=$EMAIL
NODE_ENV=production
APP_URL=https://$FRONTEND_DOMAIN
EOF

# Write frontend .env
echo "📝 Writing frontend .env..."
cat > "$FRONTEND_ENV_FILE" <<EOF
VITE_API_URL=https://$BACKEND_DOMAIN
VITE_PUSH_SERVER_KEY=$VAPID_PUBLIC_KEY
EOF

# Temporary frontend Nginx config for certbot
echo "🌐 Setting up temporary Nginx config for certbot..."
cat > /etc/nginx/sites-available/default <<EOF
server {
  listen 80;
  server_name $FRONTEND_DOMAIN $BACKEND_DOMAIN;

  root /var/www/html;
  index index.html;

  location / {
    try_files \$uri \$uri/ =404;
  }
}
EOF

systemctl reload nginx

# Certbot for frontend domain
CERT1="/etc/letsencrypt/live/$FRONTEND_DOMAIN/fullchain.pem"
CERT2="/etc/letsencrypt/live/$BACKEND_DOMAIN/fullchain.pem"

echo "🔒 Checking/issuing Let's Encrypt certificates..."

if [ ! -f "$CERT1" ]; then
  echo "🔐 Requesting certificate for $FRONTEND_DOMAIN..."
  if ! certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$FRONTEND_DOMAIN"; then
    echo ""
    echo "❌ Failed to issue SSL certificate for $FRONTEND_DOMAIN"
    echo "👉 Please ensure the A record for this domain points to $MYIP"
    echo "🕒 You may need to wait for DNS propagation (~5–10 minutes)"
    echo "📦 After it's ready, re-run the setup with:"
    echo "   sudo /usr/local/bin/prompt.sh"
    exit 1
  fi
else
  echo "✅ Cert already exists for $FRONTEND_DOMAIN"
fi

if [ ! -f "$CERT2" ]; then
  echo "🔐 Requesting certificate for $BACKEND_DOMAIN..."
  if ! certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$BACKEND_DOMAIN"; then
    echo ""
    echo "❌ Failed to issue SSL certificate for $BACKEND_DOMAIN"
    echo "👉 Please ensure the A record for this domain points to $MYIP"
    echo "🕒 You may need to wait for DNS propagation (~5–10 minutes)"
    echo "📦 After it's ready, re-run the setup with:"
    echo "   sudo /usr/local/bin/prompt.sh"
    exit 1
  fi
else
  echo "✅ Cert already exists for $BACKEND_DOMAIN"
fi

# Final Nginx config
echo "🔧 Updating Nginx with full frontend/backend SSL config..."
cat > /etc/nginx/sites-available/default <<EOF
server {
  listen 443 ssl;
  server_name $FRONTEND_DOMAIN;

  ssl_certificate /etc/letsencrypt/live/$FRONTEND_DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$FRONTEND_DOMAIN/privkey.pem;

  root $REPO_DIR/app/dist;
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  error_page 404 /index.html;
  location = /index.html {
    root $REPO_DIR/app/dist;
    internal;
  }
}

server {
  listen 443 ssl;
  server_name $BACKEND_DOMAIN;

  ssl_certificate /etc/letsencrypt/live/$BACKEND_DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$BACKEND_DOMAIN/privkey.pem;

  location / {
    proxy_pass http://localhost:2000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
    client_max_body_size 10M;
  }
}
EOF

systemctl reload nginx
echo "✅ Nginx fully configured for frontend and backend domains"

# Build frontend
echo "🏗 Building frontend..."
cd "$APP_DIR"
npm install
npm run build

# Install backend
echo "📦 Installing backend..."
cd "$REPO_DIR/backend"
npm install
npm run build
npx prisma generate

# MySQL check
echo "🛠 Ensuring MySQL is running..."
if systemctl is-active --quiet mysql; then
  echo "✅ MySQL is running"
else
  echo "🔄 Starting MySQL..."
  systemctl start mysql
fi

# Start PM2
echo "🚀 Starting backend via PM2..."
pm2 start index.js --name operational-backend -f

echo ""
echo "🎉 Setup complete!"
echo "🌍 Frontend: https://$FRONTEND_DOMAIN"
echo "🛠 Backend:  https://$BACKEND_DOMAIN"