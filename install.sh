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

# Убираем начальный и конечный слэш, чтобы был формат "secret/admin"
ADMIN_ROUTE=$(echo "$ADMIN_PATH" | sed 's|^/||; s|/$||')

# Установка Docker, если нет
if ! command -v docker &> /dev/null; then
    echo "📦 Устанавливаю Docker..."
    apt update
    apt install -y docker.io
    systemctl enable --now docker
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
sed -i "s|@app.route('/djufbsjrlhddyg/admin')|@app.route('/$ADMIN_ROUTE')|" "$DEPLOY_DIR/app.html"
sed -i "s|@app.route('/djufbsjrlhddyg/admin')|@app.route('/$ADMIN_ROUTE')|" "$DEPLOY_DIR/app.py"

# Обновляем admin.html — меняем ссылку в JavaScript
sed -i "s|/djufbsjrlhddyg/admin|/$ADMIN_ROUTE|g" "$DEPLOY_DIR/templates/admin.html"

# Права
chown -R $(logname):$(logname) "$DEPLOY_DIR"

# Запуск
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

echo ""
echo "✅ Установка завершена!"
echo "   Админка: https://твой-домен/$ADMIN_ROUTE"
echo "   Подписка: https://твой-домен/group1"
