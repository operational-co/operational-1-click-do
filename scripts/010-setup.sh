#!/bin/bash
set -e

### Swap ###
if swapon --show | grep -q '/swapfile'; then
  echo "✅ Swap file already exists and is active"
else
  echo "🧠 Creating 4GB swap space..."
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "✅ Swap file created and activated"
fi


### Repos and packages ###
apt install -y software-properties-common
add-apt-repository -y universe
apt update

echo "🔄 Installing packages..."
DEBIAN_FRONTEND=noninteractive apt install -y \
  nginx \
  python3-certbot-nginx \
  mysql-server \
  git \
  fail2ban \
  certbot \
  ufw \
  jq

### NVM + Node ###
echo "🔧 Installing NVM and Node.js v20.x..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm install 20
nvm use 20
nvm alias default 20
node -v && echo "✅ Node.js installed"

### Nginx Config ###
if ! command -v nginx >/dev/null; then
  echo "⚙️  Configuring Nginx..."

  cat > /etc/nginx/sites-available/default <<EOF
server {
  listen 80 default_server;
  server_name _;

  root /var/www/html;
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  error_page 404 /index.html;
  location = /index.html {
    root /var/www/html;
    internal;
  }

  client_max_body_size 10M;
}

server {
  listen 4337;
  server_name _;

  location / {
    proxy_pass http://localhost:2000/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
    client_max_body_size 10M;
  }
}
EOF

  if nginx -t; then
    systemctl restart nginx
    echo "✅ Nginx configured"
  else
    echo "❌ Nginx configuration test failed"
  fi

else
  echo "ℹ️ Nginx already installed — skipping reconfiguration"
fi


### MySQL Config ###
echo "🛠 Configuring MySQL..."

# Generate random passwords
ROOT_MYSQL_PASS=$(openssl rand -hex 24)
OPS_MYSQL_PASS=$(openssl rand -hex 24)

# Save the passwords for later use
cat > /root/.digitalocean_password <<EOM
root_mysql_pass="${ROOT_MYSQL_PASS}"
operational_mysql_pass="${OPS_MYSQL_PASS}"
EOM

# Update MySQL settings
cat >> /etc/mysql/mysql.conf.d/mysqld.cnf <<EOF

# Custom Config
port = 5999
innodb_buffer_pool_size = 64M
EOF

systemctl restart mysql

# Wait for MySQL to come online
while ! mysqladmin ping -h127.0.0.1 -P 5999 --silent; do
  echo "⏳ Waiting for MySQL..."
  sleep 1
done

# Set root password, create operational user and DB
echo "📦 Creating MySQL database and users..."
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOT_MYSQL_PASS}';
CREATE DATABASE IF NOT EXISTS operational;
CREATE USER IF NOT EXISTS 'operational'@'localhost' IDENTIFIED BY '${OPS_MYSQL_PASS}';
CREATE USER IF NOT EXISTS 'operational'@'127.0.0.1' IDENTIFIED BY '${OPS_MYSQL_PASS}';
GRANT ALL PRIVILEGES ON operational.* TO 'operational'@'localhost';
GRANT ALL PRIVILEGES ON operational.* TO 'operational'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

# Restrict root access to localhost only
sed -i 's/^bind-address\s*=.*/bind-address = 127.0.0.1/' /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql

echo "✅ MySQL configured and secured"

### Fail2Ban Config ###
echo "🛡 Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ssh
maxretry = 10

[nginx-http-auth]
enabled = true

[mysqld-auth]
enabled = true
EOF

systemctl enable fail2ban
systemctl restart fail2ban
echo "✅ Fail2Ban configured and restarted"

### Git ###
echo "✅ Git is available at: $(which git)"

### PM2 ###
echo "🔧 Installing PM2..."
source "$NVM_DIR/nvm.sh"
nvm use 20
npm install -g pm2
command -v pm2 && echo "✅ PM2 installed"

### web-push ###
echo "📦 Installing web-push..."
npm install -g web-push
command -v web-push && echo "✅ web-push installed"

### UFW ###
echo "🛡 Configuring UFW..."
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 5999/tcp  # MySQL
ufw --force enable
echo "✅ UFW enabled with allowed ports: 22, 80, 2000, 5999"

### Enable motd file ###
if [ -f /etc/update-motd.d/99-one-click ]; then
  chmod 0755 /etc/update-motd.d/99-one-click
  echo "✅ MOTD script made executable"
else
  echo "ℹ️ No MOTD file found at /etc/update-motd.d/99-one-click — skipping"
fi

### Enable startup file ###
if [ -f /usr/local/bin/prompt.sh ]; then
  chmod +x /usr/local/bin/prompt.sh
  echo "✅ startup script made executable"
else
  echo "ℹ️ No startup file found at /usr/local/bin/prompt.sh — skipping"
fi

### Enable onboot file ###
if [ -f /var/lib/cloud/scripts/per-instance/001_onboot ]; then
  chmod +x /var/lib/cloud/scripts/per-instance/001_onboot
  echo "✅ onboot script made executable"
else
  echo "ℹ️ No onboot file found at /var/lib/cloud/scripts/per-instance/001_onboot — skipping"
fi

echo "🚀 Cloning operational.co and building frontend..."

if [ -d "/operational.co" ]; then
  echo "📁 /operational.co already exists — skipping clone"
else
  git clone --branch v0.1.8 --depth 1 https://github.com/operational-co/operational.co /operational.co
  echo "✅ Repo cloned to /operational.co"
fi

echo "📝 Creating empty .env files..."

touch /operational.co/app/.env
touch /operational.co/backend/.env

echo "✅ Empty .env files created at:"
echo "   - /operational.co/app/.env"
echo "   - /operational.co/backend/.env"

echo "📦 Installing backend dependencies..."
cd /operational.co/backend
npm install

cd /operational.co/app
npm install

echo "🎉 010.setup.sh ran successfully"