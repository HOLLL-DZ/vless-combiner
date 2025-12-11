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

# Получаем публичный IP
PUBLIC_IP=""
echo "🌐 Определяю публичный IP сервера..."
if command -v curl &> /dev/null; then
    PUBLIC_IP=$(timeout 5 curl -s https://api.ipify.org 2>/dev/null || echo "")
fi

if [ -z "$PUBLIC_IP" ]; then
    echo "⚠️ Не удалось определить IP. Использую заглушку."
    PUBLIC_IP="test.com.net"
else
    echo "✅ Обнаружен IP: $PUBLIC_IP"
fi

# Ввод домена или IP
read -p "🌐 Введите домен или IP (по умолчанию: $PUBLIC_IP): " SERVER_ADDR
SERVER_ADDR=${SERVER_ADDR:-$PUBLIC_IP}

# Определяем тип адреса
if [[ $SERVER_ADDR =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IS_IP=true
else
    IS_IP=false
fi

# SSL (недоступен для IP)
if $IS_IP; then
    USE_SSL=false
    echo "🔒 SSL отключён: используется IP-адрес."
else
    read -p "🔐 Установить Let's Encrypt? (y/n, по умолчанию: y): " SSL_CHOICE
    SSL_CHOICE=${SSL_CHOICE:-y}
    [[ "$SSL_CHOICE" =~ ^[Yy]$ ]] && USE_SSL=true || USE_SSL=false
fi

DOMAIN="$SERVER_ADDR"
ADMIN_ROUTE=$(echo "$ADMIN_PATH" | sed 's|^/||; s|/$||')

# Установка зависимостей
if ! command -v docker &> /dev/null; then
    echo "📦 Устанавливаю Docker..."
    apt update
    apt install -y docker.io
    systemctl enable --now docker
fi

echo "🔧 Устанавливаю Nginx..."
apt install -y nginx

if $USE_SSL; then
    echo "🔧 Устанавливаю Certbot..."
    apt install -y certbot python3-certbot-nginx
fi

# Директория проекта
DEPLOY_DIR="/opt/vless-combiner"
mkdir -p "$DEPLOY_DIR"

# Скачиваем файлы, если их нет
if [ ! -f "$DEPLOY_DIR/app.py" ]; then
    echo "📥 Скачиваю файлы..."
    curl -s -o "$DEPLOY_DIR/app.py" https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/app.py
    mkdir -p "$DEPLOY_DIR/templates"

    # Скачиваем ОРИГИНАЛЬНЫЕ шаблоны, затем ЗАМЕНЯЕМ их на адаптированные ниже
    # (мы их не используем — сразу создаём правильные)
fi

# === Создаём ПРАВИЛЬНЫЕ шаблоны здесь ===
cat > "$DEPLOY_DIR/templates/index.html" << 'INDEX_EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Vless-Combiner</title>
  <style>
    body { font-family: sans-serif; padding: 20px; background: #f5f5f5; }
    h2 { color: #333; }
    .group { margin-bottom: 30px; padding: 15px; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    a { color: #007bff; text-decoration: none; }
    a:hover { text-decoration: underline; }
    code { background: #eee; padding: 2px 6px; border-radius: 4px; }
  </style>
</head>
<body>
  <h1>Vless-Combiner</h1>
  {% for gid, data in groups.items() %}
  <div class="group">
    <h2>{{ data.name }}</h2>
    <p>
      <a href="/{{ gid }}/base64" target="_blank">Получить подписку (Base64)</a>
    </p>
    <p>
      URL: <code>{{ base_url }}/{{ gid }}</code>
    </p>
  </div>
  {% endfor %}
</body>
</html>
INDEX_EOF

# === Адаптированный admin.html с КОПИРОВАНИЕМ ===
cat > "$DEPLOY_DIR/templates/admin.html" << 'ADMIN_EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Vless-Combiner: Управление подписками</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <style>
        :root {
            --primary: #2c3e50;
            --secondary: #3498db;
            --success: #2ecc71;
            --danger: #e74c3c;
            --light: #f8f9fa;
            --dark: #34495e;
            --gray: #bdc3c7;
            --white: #ffffff;
            --shadow: 0 4px 12px rgba(0,0,0,0.08);
            --card-bg: #ffffff;
            --border: #dee2e6;
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: var(--light);
            color: var(--dark);
            line-height: 1.6;
            padding: 20px;
            max-width: 1200px;
            margin: 0 auto;
        }

        .header {
            display: flex;
            align-items: center;
            gap: 15px;
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 2px solid var(--secondary);
            position: relative;
        }

        .header i {
            font-size: 2rem;
            color: var(--primary);
        }

        .header h1 {
            font-size: 1.8rem;
            color: var(--primary);
            font-weight: 600;
        }

        .server-info {
            position: absolute;
            right: 0;
            top: 0;
            background: var(--card-bg);
            padding: 12px 16px;
            border-radius: 8px;
            box-shadow: var(--shadow);
            font-size: 13px;
            color: var(--dark);
            display: flex;
            align-items: center;
            gap: 10px;
            min-width: 200px;
        }

        .copy-ip-btn {
            background: var(--secondary);
            color: white;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 12px;
            cursor: pointer;
            transition: background 0.2s;
        }

        .copy-ip-btn:hover {
            background: #2980b9;
        }

        .actions { display: flex; gap: 10px; margin-bottom: 20px; }

        button, .btn {
            border: none !important;
            outline: none !important;
            background: var(--secondary) !important;
            color: white !important;
            padding: 8px 16px !important;
            border-radius: 6px !important;
            cursor: pointer !important;
            font-weight: 600 !important;
            transition: background 0.2s !important;
        }

        .btn-success { background: var(--success) !important; }
        .btn-danger { background: var(--danger) !important; }

        .group-card {
            background: var(--card-bg);
            border-radius: 12px;
            padding: 20px;
            box-shadow: var(--shadow);
            margin-bottom: 20px;
        }

        .subscription-link {
            background: var(--light);
            padding: 12px 15px;
            border-radius: 8px;
            margin: 15px 0;
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 14px;
            word-break: break-all;
            border: 1px solid var(--border);
        }

        .copy-btn {
            background: var(--secondary) !important;
            color: white !important;
            padding: 6px 12px !important;
            border-radius: 6px !important;
            font-size: 14px !important;
            margin-left: 10px !important;
            cursor: pointer !important;
        }

        .copy-btn:hover {
            background: #2980b9 !important;
        }
    </style>
</head>
<body>
    <div class="header">
        <i class="fas fa-wrench"></i>
        <h1>Vless-Combiner: Управление группами</h1>
        <div class="server-info">
            <i class="far fa-clock"></i>
            <span id="moscow-time">Загрузка...</span>
            <span>•</span>
            <i class="fas fa-globe-americas"></i>
            <span id="public-ip">Загрузка IP...</span>
            <button class="copy-ip-btn" onclick="copyIP()">Копировать</button>
        </div>
    </div>

    <div class="actions">
        <button class="btn btn-success" onclick="addGroup()">➕ Добавить группу</button>
        <button class="btn" onclick="saveConfig()">💾 Сохранить всё</button>
    </div>

    <div id="groups-container">
        {% for gid, data in groups.items() %}
        <div class="group-card" data-id="{{ gid }}">
            <div class="subscription-link">
                <i class="fas fa-link"></i>
                <span>Подписка: <span id="link-{{ gid }}">{{ base_url }}/{{ gid }}</span></span>
                <button class="copy-btn" onclick="copyLink('link-{{ gid }}')">
                    <i class="far fa-copy"></i> Копировать
                </button>
            </div>
        </div>
        {% endfor %}
    </div>

    <script>
        function copyLink(elementId) {
            const el = document.getElementById(elementId);
            if (!el) { alert('❌ Элемент не найден'); return; }
            const text = el.textContent.trim();
            if (!text) { alert('❌ Пустая ссылка'); return; }
            navigator.clipboard.writeText(text).then(() => {
                alert('✅ Скопировано: ' + text);
            }).catch(() => {
                alert('❌ Разрешите копирование или обновите страницу');
            });
        }
        function copyIP() {
            const ip = document.getElementById('public-ip').textContent;
            navigator.clipboard.writeText(ip).catch(() => alert('❌ Не удалось скопировать IP'));
        }
        function addGroup() {
            const container = document.getElementById('groups-container');
            const id = 'group' + (container.children.length + 1);
            const div = document.createElement('div');
            div.className = 'group-card';
            div.innerHTML = `
                <div class="subscription-link">
                    <i class="fas fa-link"></i>
                    <span>Подписка: <span id="link-${id}">{{ base_url }}/${id}</span></span>
                    <button class="copy-btn" onclick="copyLink('link-${id}')">
                        <i class="far fa-copy"></i> Копировать
                    </button>
                </div>
            `;
            container.appendChild(div);
        }
        function saveConfig() { alert('✅ Сохранение пока отключено (только для демо)'); }
        document.getElementById('public-ip').textContent = 'IP загрузится через JS';
        fetch('https://api.ipify.org?format=json').then(r=>r.json()).then(d=>{document.getElementById('public-ip').textContent=d.ip});
    </script>
</body>
</html>
ADMIN_EOF

# === config.yaml ===
CONFIG_FILE="$DEPLOY_DIR/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
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
fi

# Права
chown -R "$(logname):$(logname)" "$DEPLOY_DIR"

# Запуск контейнера
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

# Nginx
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
if $USE_SSL; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" || echo "⚠️ Certbot: ошибка (домен может не указывать на сервер)"
fi

echo ""
echo "✅ Установка завершена!"
if $IS_IP; then
    echo "   Админ-панель: http://$DOMAIN:8080/$ADMIN_ROUTE"
    echo "   Главная:        http://$DOMAIN:8080"
else
    if $USE_SSL; then
        echo "   Админ-панель: https://$DOMAIN/$ADMIN_ROUTE"
    else
        echo "   Админ-панель: http://$DOMAIN:8080/$ADMIN_ROUTE"
    fi
fi
echo ""
echo "🔑 Пароль: admin123 → смените его в панели!"
echo "📁 Файлы: /opt/vless-combiner/"