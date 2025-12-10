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

# Спрашиваем домен
read -p "🌐 Введите ваш домен (например: test.romfakerule.net.ru): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "❌ Домен не может быть пустым"
  exit 1
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

# Установка Nginx и Certbot
echo "🔧 Устанавливаю Nginx и Certbot..."
apt install -y nginx certbot python3-certbot-nginx

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

# Обновляем admin.html — меняем ссылку в JavaScript
sed -i "s|/djufbsjrlhddyg/admin|/$ADMIN_ROUTE|g" "$DEPLOY_DIR/templates/admin.html"

# Обновляем config.yaml — ставим базовый URL
sed -i "s|base_url: \"http://localhost:8080\"|base_url: \"https://$DOMAIN\"|" "$DEPLOY_DIR/config.yaml"

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

# Получение SSL-сертификата
echo "🔐 Получаю SSL-сертификат от Let's Encrypt..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@$DOMAIN

echo ""
echo "✅ Установка завершена!"
echo "   Админка: https://$DOMAIN/$ADMIN_ROUTE"
echo "   Подписка: https://$DOMAIN/group1"
echo ""
echo "💡 Чтобы изменить настройки — отредактируй файлы в /opt/vless-combiner/"
echo "   и перезапусти контейнер: docker restart vless-combiner"
