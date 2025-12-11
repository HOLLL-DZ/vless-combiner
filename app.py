# -*- coding: utf-8 -*-
import os
import yaml
import base64
import requests
from flask import Flask, render_template, request, Response
from functools import wraps
from urllib.parse import urlparse
import socket

# === Путь к конфигурации ===
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
        defaults = {
            "base_url": "http://localhost:8080",
            "admin_password": "admin123",
            "admin_route": "admin",
            "port": 8080,
            "groups": {}
        }
        for key, value in defaults.items():
            config.setdefault(key, value)
        return config

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

# === Flask: шаблоны в корне проекта ===
app = Flask(__name__, template_folder='.')

# Загружаем маршрут админки
config_at_start = load_config()
ADMIN_ROUTE = config_at_start.get('admin_route', 'admin').lstrip('/')

@app.route('/')
def index():
    config = load_config()
    return render_template('index.html', groups=config.get('groups', {}), base_url=config['base_url'])

@app.route(f'/{ADMIN_ROUTE}')
@requires_auth
def admin_view():
    config = load_config()
    return render_template('admin.html', groups=config.get('groups', {}), base_url=config['base_url'])

@app.route('/<group_id>')
def serve_group(group_id):
    config = load_config()
    groups = config.get('groups', {})
    if group_id not in groups:
        return "Group not found", 404
    urls = groups[group_id].get('urls', [])
    if not urls:
        return "No URLs in group", 404
    all_lines = fetch_and_combine(urls)
    if not all_lines:
        return "No valid proxies", 404
    combined = "\n".join(all_lines)
    encoded = base64.b64encode(combined.encode('utf-8')).decode('utf-8')
    return Response(encoded, mimetype='text/plain')

if __name__ == '__main__':
    config = load_config()
    app.run(host='0.0.0.0', port=config.get('port', 8080))