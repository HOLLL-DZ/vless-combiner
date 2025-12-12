# -*- coding: utf-8 -*-
import os
import yaml
import base64
import requests
from flask import Flask, render_template, request, Response, jsonify, send_file
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
                content_type = resp.headers.get('Content-Type', '').lower()
                if 'text/plain' in content_type:
                    try:
                        decoded = base64.b64decode(resp.text).decode('utf-8')
                        lines = [line.strip() for line in decoded.split('\n') if line.strip()]
                        all_lines.extend(lines)
                    except:
                        lines = [line.strip() for line in resp.text.split('\n') if line.strip() and ('://' in line)]
                        all_lines.extend(lines)
                elif 'text/html' in content_type:
                    import re
                    proxy_links = re.findall(r'(vless://[^\s\'"]+|vmess://[^\s\'"]+|trojan://[^\s\'"]+)', resp.text)
                    all_lines.extend(proxy_links)
                else:
                    try:
                        decoded = base64.b64decode(resp.text).decode('utf-8')
                        lines = [line.strip() for line in decoded.split('\n') if line.strip()]
                        all_lines.extend(lines)
                    except:
                        lines = [line.strip() for line in resp.text.split('\n') if line.strip() and ('://' in line)]
                        all_lines.extend(lines)
        except Exception as e:
            print(f"Error fetching {url}: {e}")
    return all_lines

# === Инициализация Flask ===
app = Flask(__name__, template_folder='.')

config_at_start = load_config()
ADMIN_ROUTE = config_at_start.get('admin_route', 'admin').lstrip('/')

# === Маршруты ===
@app.route('/')
def index():
    config = load_config()
    return render_template('index.html', groups=config.get('groups', {}), base_url=config['base_url'])

@app.route(f'/{ADMIN_ROUTE}')
@requires_auth
def admin_view():
    config = load_config()
    return render_template('admin.html', groups=config.get('groups', {}), base_url=config['base_url'])

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
        return jsonify({"status": "error", "message": "URL is required"}), 400
    
    try:
        resp = requests.get(url, timeout=10)
        if resp.status_code != 200:
            return jsonify({
                "status": "error", 
                "message": f"HTTP {resp.status_code}",
                "sample": resp.text[:100] + "..." if resp.text else ""
            })
        
        content = resp.text.strip()
        content_type = resp.headers.get('Content-Type', '').lower()
        content_length = len(content)
        
        if 'text/plain' in content_type:
            try:
                decoded = base64.b64decode(content).decode('utf-8')
                lines = [line.strip() for line in decoded.split('\n') if line.strip()]
                if lines:
                    return jsonify({
                        "status": "success", 
                        "message": f"Base64 OK ({len(lines)} proxies)",
                        "sample": lines[0][:50] + "...",
                        "contentType": "base64"
                    })
                return jsonify({
                    "status": "warning", 
                    "message": "Base64 decoded but no valid proxies found",
                    "sample": content[:100] + "..."
                })
            except:
                lines = [line.strip() for line in content.split('\n') if line.strip() and ('://' in line)]
                if lines:
                    return jsonify({
                        "status": "success", 
                        "message": f"Direct links OK ({len(lines)} proxies)",
                        "sample": lines[0][:50] + "...",
                        "contentType": "direct_links"
                    })
                return jsonify({
                    "status": "warning",
                    "message": f"Not Base64, but has {content_length} characters",
                    "sample": content[:100] + "...",
                    "contentType": "unknown_text"
                })
        
        if 'text/html' in content_type or '<html' in content.lower():
            import re
            proxy_links = re.findall(r'(vless://[^\s\'"]+|vmess://[^\s\'"]+|trojan://[^\s\'"]+)', content)
            if proxy_links:
                return jsonify({
                    "status": "success", 
                    "message": f"HTML with {len(proxy_links)} proxies found",
                    "sample": proxy_links[0][:50] + "...",
                    "contentType": "html_with_proxies"
                })
            return jsonify({
                "status": "warning",
                "message": "HTML page received - no proxies found",
                "sample": content[:200] + "...",
                "contentType": "html_no_proxies"
            })
        
        if 'application/json' in content_type:
            try:
                json_data = json.loads(content)
                return jsonify({
                    "status": "warning",
                    "message": "JSON response - format not directly supported",
                    "sample": str(json_data)[:200] + "...",
                    "contentType": "json"
                })
            except:
                return jsonify({
                    "status": "warning",
                    "message": f"JSON-like content ({content_length} chars)",
                    "sample": content[:100] + "...",
                    "contentType": "json_like"
                })
        
        return jsonify({
            "status": "warning",
            "message": f"Unknown content type: {content_type}",
            "sample": content[:100] + "...",
            "contentType": "unknown"
        })
    
    except requests.exceptions.ConnectionError as e:
        return jsonify({"status": "error", "message": f"Connection error: {str(e)}"})
    except requests.exceptions.Timeout:
        return jsonify({"status": "error", "message": "Request timed out (10s)"})
    except requests.exceptions.RequestException as e:
        return jsonify({"status": "error", "message": f"Request error: {str(e)}"})
    except Exception as e:
        return jsonify({"status": "error", "message": f"Processing error: {str(e)}"})

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

@app.route('/<group_id>')
def serve_group(group_id):
    config = load_config()
    groups = config.get('groups', {})
    
    if group_id not in groups:
        return "Group not found", 404
    
    group_data = groups[group_id]
    urls = group_data.get('urls', [])
    
    if not urls:
        return "No URLs in this group", 404
    
    all_lines = fetch_and_combine(urls)
    
    if not all_lines:
        return "No valid proxies found", 404
    
    combined_text = "\n".join(all_lines)
    encoded = base64.b64encode(combined_text.encode('utf-8')).decode('utf-8')
    
    return Response(encoded, mimetype='text/plain')

# === НОВЫЕ ЭНДПОИНТЫ: ИМПОРТ / ЭКСПОРТ ===
@app.route('/api/export-config')
@requires_auth
def api_export_config():
    if not os.path.exists(CONFIG_PATH):
        # Если файла нет — отдаём дефолтный YAML
        default = {
            "base_url": "http://localhost:8080",
            "admin_password": "admin123",
            "admin_route": "admin",
            "port": 8080,
            "groups": {}
        }
        data = yaml.dump(default, allow_unicode=True, default_flow_style=False, indent=2)
        return Response(
            data,
            mimetype='application/x-yaml',
            headers={"Content-Disposition": "attachment;filename=config.yaml"}
        )
    # Иначе — читаем реальный файл с диска
    with open(CONFIG_PATH, 'rb') as f:
        data = f.read()
    return Response(
        data,
        mimetype='application/x-yaml',
        headers={"Content-Disposition": "attachment;filename=config.yaml"}
    )

@app.route('/api/import-config', methods=['POST'])
@requires_auth
def api_import_config():
    if 'file' not in request.files:
        return jsonify({"error": "No file provided"}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "Empty filename"}), 400
    if not (file.filename.endswith('.yaml') or file.filename.endswith('.yml')):
        return jsonify({"error": "Only .yaml or .yml files allowed"}), 400

    try:
        content = file.read().decode('utf-8')
        config = yaml.safe_load(content)
        if config is None:
            return jsonify({"error": "YAML is empty or invalid"}), 400
        if not isinstance(config, dict):
            return jsonify({"error": "YAML root must be an object"}), 400

        # Перезаписываем файл на диске
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            f.write(content)

        return jsonify({"status": "ok", "message": "Config imported successfully"})
    except yaml.YAMLError as e:
        return jsonify({"error": f"Invalid YAML syntax: {str(e)}"}), 400
    except UnicodeDecodeError:
        return jsonify({"error": "File must be UTF-8 encoded"}), 400
    except Exception as e:
        return jsonify({"error": f"Failed to save config: {str(e)}"}), 500

# === Запуск ===
if __name__ == '__main__':
    config = load_config()
    app.run(host='0.0.0.0', port=config.get('port', 8080))