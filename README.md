# VLESS Combiner

<li>Простой объединитель подписок vless с разных серверов.</li>
<li>Обновляет подписки в приложении по запросу в реальном времени.</li>
<li>Имеет веб интерфейс с настройками и редактором.</li>
<img width="1283" height="919" alt="image" src="https://github.com/user-attachments/assets/e20547c4-03e5-4a84-97a0-c7abf4ba4a76" />


Установка:

```javascript
wget https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/install.sh   && chmod +x install.sh && sudo ./install.sh
```
<p>Скрипт автоматически:</p>
<ul>
  <li>Установит Docker, Nginx и Certbot</li>
  <li>Настроит HTTPS через Let's Encrypt</li>
  <li>Запустит приложение в контейнере Docker</li>
  <li>Настроит проксирование через Nginx</li>
</ul>
<p>После установки вы получите ссылку вида:</p>
<p><code>https://your-domain.com/your-secret-path</code></p>



Удалить с сервера:
```javascript
# 1. Остановить и удалить контейнер
sudo docker stop vless-combiner 2>/dev/null
sudo docker rm vless-combiner 2>/dev/null

# 2. Удалить файлы проекта
sudo rm -rf /opt/vless-combiner

# 3. Удалить конфиг Nginx
DOMAIN="test.com.net"  # ← замени на свой домен, если использовал другой
sudo rm -f /etc/nginx/sites-available/$DOMAIN
sudo rm -f /etc/nginx/sites-enabled/$DOMAIN
sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true

# 4. (Опционально) Удалить SSL-сертификат Let's Encrypt
# sudo certbot delete --cert-name $DOMAIN 2>/dev/null || true

# 5. Удалить системные зависимости (осторожно!)
# Раскомментируй, только если НИЧЕГО другого не использует Docker/Nginx
# sudo apt remove -y docker.io nginx certbot python3-certbot-nginx
# sudo apt autoremove -y
```

Обновить:
```javascript
cd /opt/vless-combiner && \
curl -s -O https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/app.py   && \
curl -s -O https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/templates/admin.html   && \
curl -s -O https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/templates/index.html   && \
sudo docker restart vless-combiner
```

Telegram-канал: https://t.me/vless_combiner  
