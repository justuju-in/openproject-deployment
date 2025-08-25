#!/bin/bash
set -euo pipefail

# ------------------ CONFIG ------------------
DOMAIN="work.justuju.in"
CERT_EMAIL="devs@justuju.in"   # Email for Let's Encrypt
DATA_DIR="/var/lib/openproject"

# ------------------ INSTALL DOCKER ------------------
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER

# ------------------ CREATE PROJECT DIRECTORY AND INSTALL THE OPENPROJECT------------------
sudo mkdir -p "$DATA_DIR"/{pgdata,assets}
sudo chown -R "$(whoami)":"$(whoami)" "$DATA_DIR"/{pgdata,assests}
sudo docker run -d -p 127.0.0.1:8080:80 --name openproject \
  -e OPENPROJECT_HOST__NAME=$DOMAIN \
  -e OPENPROJECT_SECRET_KEY_BASE=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64) \
  -e OPENPROJECT_HTTPS=true \
  -e OPENPROJECT_DEFAULT__LANGUAGE=en \
  -v /var/lib/openproject/pgdata:/var/openproject/pgdata \
  -v /var/lib/openproject/assets:/var/openproject/assets \
  openproject/openproject:16

# ------------------ INSTALL AND CONFIGURE NGINX (EXTERNAL) ------------------
sudo apt install -y nginx certbot python3-certbot-nginx
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }                                         
}  
EOF

sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# ------------------ OBTAIN SSL CERTIFICATE ------------------
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $CERT_EMAIL
sudo certbot renew --dry-run --non-interactive

#-------------------START THE OPENPROJECT------------------
sudo docker start openproject