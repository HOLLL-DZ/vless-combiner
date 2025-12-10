# -*- coding: utf-8 -*-
import os
import yaml
import base64
import requests
from flask import Flask, render_template, request, Response, jsonify
from functools import wraps
from urllib.parse import urlparse
import socket
import json
import time
import threading
from datetime import datetime

# === Загрузка конфигурации ===
CONFIG_PATH = os.path.join(os.path.dirname(__file__), 'config.yaml')

def load_config():
    if not os.path.exists(CONFIG_PATH):
        return {
            "base_url": "http://localhost:8080",
            "admin_password": "admin123",
            "admin_route": "admin",
            "port": 8080,
            "groups": {}
        }
    with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
        # Устанавливаем значения по умолчанию, если отсутствуют
        defaults = {
            "base_url": "http://localhost:8080",
            "admin_password": "admin123",
            "admin_route": "admin",
            "port": 8080,
            "groups": {}
        }
        for key, value in defaults.items():
            if key not in config:
                config[key] = value
        return config

def save_config(config):
    with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, allow_unicode=True, default_flow_style=False, indent=2)

# === Аутентификация ===
def check_auth(username, password):
    config = load_config()
    return password == config.get('admin_password', 'admin123')

def authenticate():
    return Response('Login required', 401,
                    {'WWW-Authenticate': 'Basic realm="Admin Login"'})

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or not check_auth(auth.username, auth.password):
            return authenticate()
        return f(*args, **kwargs)
    return decorated

# === Вспомогательные функции ===
def fetch_and_combine(urls):
    all_lines = []
    for url in urls:
        try:
            resp = requests.get(url, timeout=10)
            if resp.status_code == 200:
                decoded = base64.b64decode(resp.text).decode('utf-8')
                lines = [line.strip() for line in decoded.split('\n') if line.strip()]
                all_lines.extend(lines)
        except Exception as e:
            print(f"Error fetching {url}: {e}")
    return all_lines

# === Инициализация Flask ===
app = Flask(__name__)

# Загружаем маршрут админки при старте
config_at_start = load_config()
ADMIN_ROUTE = config_at_start.get('admin_route', 'admin').lstrip('/')

@app.route(f'/{ADMIN_ROUTE}')
@requires_auth
def admin_view():
    config = load_config()
    return render_template('admin.html', groups=config.get('groups', {}), config=config)

@app.route('/')
def index():
    config = load_config()
    return render_template('index.html', groups=config.get('groups', {}))

# === Динамический маршрут админки ===
@app.route('/test-admin')
@requires_auth
def test_admin():
    config = load_config()
    return render_template('admin.html', groups=config.get('groups', {}), config=config)

def admin_view():
    config = load_config()
    return render_template('admin.html', groups=config.get('groups', {}), config=config)

# === API ===
@app.route('/api/save', methods=['POST'])
@requires_auth
def api_save():
    data = request.json
    action = data.get('action', 'save_config')
    
    if action == 'change_password':
        new_pass = data.get('new_password', '').strip()
        if len(new_pass) < 4:
            return jsonify({"error": "Password too short"}), 400
        config = load_config()
        config['admin_password'] = new_pass
        save_config(config)
        return jsonify({"status": "ok", "message": "Password changed. Re-login required."})
    
    elif action == 'save_config':
        groups = {}
        groups_input = data.get('groups', {})
        if isinstance(groups_input, dict):
            for gid, g_data in groups_input.items():
                groups[gid] = {
                    'name': g_data.get('name', gid),
                    'urls': [u.strip() for u in g_data.get('urls', []) if u.strip()]
                }
        else:
            return jsonify({"error": "Invalid groups format"}), 400
        base_url = data.get('base_url', "http://localhost:8080")
        config = load_config()
        config.update({'base_url': base_url, 'groups': groups})
        save_config(config)
        return jsonify({"status": "ok"})

    return jsonify({"error": "Unknown action"}), 400

@app.route('/api/check-server', methods=['POST'])
def api_check_server():
    data = request.json
    url = data.get('url', '').strip()
    if not url:
        return jsonify({"error": "URL is required"}), 400
    try:
        parsed = urlparse(url)
        host = parsed.hostname
        port = parsed.port or (443 if parsed.scheme == 'https' else 80)
        with socket.create_connection((host, port), timeout=5):
            pass
        resp = requests.get(url, timeout=10)
        if resp.status_code != 200:
            return jsonify({"status": "error", "message": f"HTTP {resp.status_code}"})
        decoded = base64.b64decode(resp.text).decode('utf-8')
        lines = [line.strip() for line in decoded.split('\n') if line.strip()]
        if not lines:
            return jsonify({"status": "error", "message": "Empty or invalid Base64"})
        return jsonify({"status": "success", "message": f"OK ({len(lines)} proxies)"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

@app.route('/api/groups')
def api_groups():
    config = load_config()
    groups = {}
    for gid, data in config.get('groups', {}).items():
        groups[gid] = {
            'name': data.get('name', gid),
            'url_count': len(data.get('urls', []))
        }
    return jsonify(groups)

@app.route('/api/config')
def api_config():
    config = load_config()
    safe_config = {
        'groups': {
            gid: {
                'name': data.get('name'),
                'url_count': len(data.get('urls', []))
            }
            for gid, data in config.get('groups', {}).items()
        }
    }
    return jsonify(safe_config)

# === Запуск ===
if __name__ == '__main__':
    config = load_config()
    app.run(host='0.0.0.0', port=config.get('port', 8080))