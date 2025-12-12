```markdown
# VLESS-COMBINER  
**Простой объединитель подписок VLESS с разных серверов**

🔄 Обновляет подписки в клиенте **в реальном времени** по запросу  
🖥️ Имеет веб-интерфейс:  
- Настройка групп подписок  
- Редактор URL-адресов  
- Защита паролем  
- Генерация подписок в Base64 и прямых ссылок  

![Интерфейс VLESS Combiner](https://github.com/user-attachments/assets/3ee84990-4d06-4af2-95b0-9cf0a751f922)

---

## 🚀 Установка

1. Подключитесь к вашему серверу (Ubuntu/Debian).
2. Выполните команду:

```bash
wget https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/install.sh && \
chmod +x install.sh && \
sudo ./install.sh
```

Скрипт запросит:
- **Путь к админке** (например: `/secret-panel`)
- **Домен** (например: `vless.example.com`)

После установки вы получите:
- HTTPS через Let's Encrypt
- Админ-панель по адресу `https://ваш-домен/ваш-путь`
- Готовую подписку по адресу `https://ваш-домен/group1`

---

## 🗑️ Полное удаление

> ⚠️ Внимание: следующие команды **удалят все данные проекта** и, при необходимости, системные пакеты.

```bash
# 1. Остановить и удалить контейнер
sudo docker stop vless-combiner 2>/dev/null
sudo docker rm vless-combiner 2>/dev/null

# 2. Удалить файлы проекта
sudo rm -rf /opt/vless-combiner

# 3. Удалить конфиг Nginx (замените DOMAIN на ваш!)
DOMAIN="ваш.домен.ру"  # ← ОБЯЗАТЕЛЬНО УКАЖИ СВОЙ ДОМЕН
sudo rm -f /etc/nginx/sites-available/$DOMAIN
sudo rm -f /etc/nginx/sites-enabled/$DOMAIN
sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true

# 4. (Опционально) Удалить SSL-сертификат
# sudo certbot delete --cert-name "$DOMAIN" 2>/dev/null || true

# 5. (Опционально) Удалить пакеты — только если они НЕ используются другими сервисами!
# sudo apt remove -y docker.io nginx certbot python3-certbot-nginx
# sudo apt autoremove -y
```

---

## 🔄 Обновление

Файлы обновляются вручную без пересборки контейнера:

```bash
cd /opt/vless-combiner && \
curl -s -O https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/app.py && \
curl -s -O https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/templates/admin.html && \
curl -s -O https://raw.githubusercontent.com/HOLLL-DZ/vless-combiner/main/templates/index.html && \
sudo docker restart vless-combiner
```

---

## 📢 Поддержка и обновления

Следите за новостями и обновлениями в Telegram-канале:  
👉 [https://t.me/vless_combiner](https://t.me/vless_combiner)

---

> 💡 **Совет**: Не забудьте открыть порты **80 (HTTP)** и **443 (HTTPS)** в фаерволе вашего сервера!
```
