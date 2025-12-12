Простой объединитель подписок vless с разных серверов.
Обновляет подписки в приложении по запросу в реальном времени.
Имеет веб интерфейс с настройками и редактором.
<img width="1207" height="851" alt="2025-12-12_09-46-11" src="https://github.com/user-attachments/assets/3ee84990-4d06-4af2-95b0-9cf0a751f922  " />


Установка:

```javascript
wget https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/install.sh   && chmod +x install.sh && sudo ./install.sh
```

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

ТГ канал: https://t.me/vless_combiner  

добавь большими буквами имя проекта вверху, можешь отредактировать код по своему вкусу
