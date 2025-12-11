#!/bin/bash

set -e

echo "🚀 Устанавливаю VLESS Combiner от HOLLL-DZ..."

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Запусти от root (sudo)"
  exit 1
fi

# Спрашиваем путь к админке
read -p "🔐 Введите путь к админ-панели (например: admin): " ADMIN_PATH
if [[ -z "$ADMIN_PATH" ]]; then
  echo "❌ Путь не может быть пустым"
  exit 1
fi

# Спрашиваем адрес (домен или IP)
read -p "🌐 Введите ваш домен или IP-адрес сервера (по умолчанию: test.com.net): " SERVER_ADDR
SERVER_ADDR=${SERVER_ADDR:-test.com.net}

# Определяем, IP это или домен
if [[ $SERVER_ADDR =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IS_IP=true
    echo "📍 Распознан IP-адрес: $SERVER_ADDR"
else
    IS_IP=false
fi

# Спрашиваем про SSL, но отключаем его, если это IP
if $IS_IP; then
    USE_SSL=false
    echo "🔒 SSL недоступен для IP-адресов — отключаю Let's Encrypt."
else
    read -p "🔐 Установить SSL-сертификат Let's Encrypt? (y/n, по умолчанию: y): " SSL_CHOICE
    SSL_CHOICE=${SSL_CHOICE:-y}
    if [[ "$SSL_CHOICE" =~ ^[Yy]$ ]]; then
        USE_SSL=true
    else
        USE_SSL=false
    fi
fi

DOMAIN="$SERVER_ADDR"
ADMIN_ROUTE=$(echo "$ADMIN_PATH" | sed 's|^/||; s|/$||')

# Установка Docker, если нет
if ! command -v docker &> /dev/null; then
    echo "📦 Устанавливаю Docker..."
    apt update
    apt install -y docker.io
    systemctl enable --now docker
fi

# Установка Nginx
echo "🔧 Устанавливаю Nginx..."
apt install -y nginx

# Если нужен SSL — устанавливаем Certbot
if $USE_SSL; then
    echo "🔧 Устанавливаю Certbot для Let's Encrypt..."
    apt install -y certbot python3-certbot-nginx
fi

# Создание директории
DEPLOY_DIR="/opt/vless-combiner"
mkdir -p "$DEPLOY_DIR"

# Скачиваем файлы ТОЛЬКО ЕСЛИ ИХ НЕТ
if [ ! -f "$DEPLOY_DIR/app.py" ]; then
    echo "📥 Скачиваю файлы..."
    curl -s -o "$DEPLOY_DIR/app.py" https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/app.py
    mkdir -p "$DEPLOY_DIR/templates"
    curl -s -o "$DEPLOY_DIR/templates/admin.html" https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/templates/admin.html
    curl -s -o "$DEPLOY_DIR/templates/index.html" https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/templates/index.html
fi

# Создаём config.yaml, если его нет
CONFIG_FILE="$DEPLOY_DIR/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "📝 Создаю config.yaml..."
    if $USE_SSL; then
        BASE_URL="https://$DOMAIN"
    else
        BASE_URL="http://$DOMAIN:8080"
    fi
    cat > "$CONFIG_FILE" << YAML
base_url: "$BASE_URL"
admin_password: "admin123"
admin_route: "$ADMIN_ROUTE"
port: 8080
groups:
  group1:
    name: "Основные"
    urls:
      - "https://test1.com"
      - "https://test2.com"
YAML
else
    echo "⚠️ config.yaml уже существует — не перезаписываю"
fi

# Права
chown -R "$(logname):$(logname)" "$DEPLOY_DIR"

# Запуск контейнера
echo "🐳 Запускаю контейнер..."
docker stop vless-combiner 2>/dev/null || true
docker rm vless-combiner 2>/dev/null || true

docker run -d \
  --name vless-combiner \
  --restart=unless-stopped \
  -p 8080:8080 \
  -v "$DEPLOY_DIR/config.yaml:/app/config.yaml" \
  -v "$DEPLOY_DIR/app.py:/app/app.py" \
  -v "$DEPLOY_DIR/templates:/app/templates" \
  python:3.11-slim bash -c "
    pip install flask requests pyyaml &&
    python /app/app.py
  "

# Конфиг Nginx
echo "📝 Настраиваю Nginx..."
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
cat > "$NGINX_CONF" << NGINX_EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX_EOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t && systemctl reload nginx

# SSL
PROTOCOL="http"
if $USE_SSL; then
    echo "🔐 Получаю SSL-сертификат от Let's Encrypt..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@"$DOMAIN" || {
        echo "⚠️ Certbot не смог получить сертификат. Возможно, домен не указывает на этот сервер."
        PROTOCOL="http"
    }
    PROTOCOL="https"
fi

echo ""
echo "✅ Установка завершена!"

if $IS_IP; then
    echo "   Главная страница: http://$DOMAIN:8080"
    echo "   Админ-панель: http://$DOMAIN:8080/$ADMIN_ROUTE"
elif $USE_SSL; then
    echo "   Админ-панель: https://$DOMAIN/$ADMIN_ROUTE"
else
    echo "   Админ-панель: http://$DOMAIN:8080/$ADMIN_ROUTE"
fi

echo ""
echo "🔑 Пароль по умолчанию для админ-панели: admin123"
echo "❗ Рекомендуется сменить его в интерфейсе после первого входа."
echo ""
echo "💡 Файлы проекта: /opt/vless-combiner/"
echo "   Чтобы обновить — замени app.py и admin.html, затем:"
echo "   sudo docker restart vless-combiner"