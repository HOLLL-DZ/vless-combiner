#!/bin/bash

set -e

echo "🚀 Устанавливаю VLESS Combiner от HOLLL-DZ..."

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Запусти от root (sudo)"
  exit 1
fi

# Спрашиваем путь к админке
read -p "🔐 Введите путь к админке (например: /secret/admin): " ADMIN_PATH
if [[ -z "$ADMIN_PATH" ]]; then
  echo "❌ Путь не может быть пустым"
  exit 1
fi

# Спрашиваем домен (по умолчанию test.com.net)
read -p "🌐 Введите ваш домен (по умолчанию: test.com.net): " DOMAIN
DOMAIN=${DOMAIN:-test.com.net}

# Спрашиваем, нужен ли SSL
read -p "🔐 Установить SSL-сертификат Let's Encrypt? (y/n, по умолчанию: y): " SSL_CHOICE
SSL_CHOICE=${SSL_CHOICE:-y}
USE_SSL=false
if [[ "$SSL_CHOICE" =~ ^[Yy]$ ]]; then
  USE_SSL=true
fi

# Убираем начальный и конечный слэш
ADMIN_ROUTE=$(echo "$ADMIN_PATH" | sed 's|^/||; s|/$||')

# Установка Docker, если нет
if ! command -v docker &> /dev/null; then
    echo "📦 Устанавливаю Docker..."
    apt update
    apt install -y docker.io
    systemctl enable --now docker
fi

# Установка Nginx (обязательно для прокси)
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

# Скачивание файлов
echo "📥 Скачиваю файлы..."
curl -s -o "$DEPLOY_DIR/app.py" https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/app.py
curl -s -o "$DEPLOY_DIR/config.yaml" https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/config.yaml
mkdir -p "$DEPLOY_DIR/templates"
curl -s -o "$DEPLOY_DIR/templates/admin.html" https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/templates/admin.html

# Обновляем app.py — заменяем маршрут админки
sed -i "s|@app.route('/djufbsjrlhddyg/admin')|@app.route('/$ADMIN_ROUTE')|" "$DEPLOY_DIR/app.py"

# Обновляем admin.html
sed -i "s|/djufbsjrlhddyg/admin|/$ADMIN_ROUTE|g" "$DEPLOY_DIR/templates/admin.html"

# Обновляем config.yaml — ставим базовый URL
if $USE_SSL; then
  BASE_URL="https://$DOMAIN"
else
  BASE_URL="http://$DOMAIN:8080"
fi
sed -i "s|base_url: \"http://localhost:8080\"|base_url: \"$BASE_URL\"|" "$DEPLOY_DIR/config.yaml"

# Права
chown -R $(logname):$(logname) "$DEPLOY_DIR"

# Запуск Flask-контейнера
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
nginx -t && systemctl reload nginx

# Получение SSL-сертификата (если нужно)
if $USE_SSL; then
    echo "🔐 Получаю SSL-сертификат от Let's Encrypt..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@$DOMAIN
    PROTOCOL="https"
else
    PROTOCOL="http"
fi

echo ""
echo "✅ Установка завершена!"
if $USE_SSL; then
  echo "   Админка: https://$DOMAIN/$ADMIN_ROUTE"
  echo "   Подписка: https://$DOMAIN/group1"
else
  echo "   Админка: http://$DOMAIN:8080/$ADMIN_ROUTE"
  echo "   Подписка: http://$DOMAIN:8080/group1"
fi
echo ""
echo "🔑 Пароль по умолчанию для админки: admin123"
echo "❗ Рекомендуется сменить его в интерфейсе после первого входа."
echo ""
echo "💡 Чтобы изменить настройки — отредактируй файлы в /opt/vless-combiner/"
echo "   и перезапусти контейнер: docker restart vless-combiner"
