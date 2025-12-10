# -*- coding: utf-8 -*-
import os
import yaml
import base64
import requests
from flask import Flask, render_template, request, Response, jsonify
from functools import wraps

app = Flask(__name__)

CONFIG_PATH = os.path.join(os.path.dirname(__file__), 'config.yaml')

def load_config():
    if not os.path.exists(CONFIG_PATH):
        return {
            "base_url": "http://localhost:8080",
            "admin_password": "admin123",
            "groups": {
                "group1": {
                    "urls": []
                }
            }
        }
    with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
        if 'base_url' not in config:
            config['base_url'] = "http://localhost:8080"
        if 'admin_password' not in config:
            config['admin_password'] = "admin123"
        return config

def save_config(config):
    with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, allow_unicode=True, default_flow_style=False, indent=2)

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

@app.route('/<group_id>')
def serve_group(group_id):
    config = load_config()
    groups = config.get('groups', {})
    if group_id not in groups:
        return "Group not found", 404
    urls = groups[group_id].get('urls', [])
    proxies = fetch_and_combine(urls)
    if not proxies:
        return "No valid proxies", 500
    combined = '\n'.join(proxies)
    encoded = base64.b64encode(combined.encode('utf-8')).decode('utf-8')
    return Response(encoded, mimetype='text/plain')

@app.route('/')
def index():
    config = load_config()
    return render_template('index.html', groups=config.get('groups', {}))

@app.route('/djufbsjrlhddyg/admin')
@requires_auth
def admin():
    config = load_config()
    return render_template('admin.html', groups=config.get('groups', {}), config=config)

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
        # groups — это объект, где ключ = ID (URL)
        groups_input = data.get('groups', {})
        if not isinstance(groups_input, dict):
            return jsonify({"error": "Invalid groups format"}), 400
        
        new_groups = {}
        for new_id, g_data in groups_input.items():
            # Новый ID должен быть непустым и валидным
            clean_id = new_id.strip()
            if not clean_id:
                continue
            new_groups[clean_id] = {
                'urls': [u.strip() for u in g_data.get('urls', []) if u.strip()]
            }
        
        base_url = data.get('base_url', "http://localhost:8080")
        config = load_config()
        config.update({'base_url': base_url, 'groups': new_groups})
        save_config(config)
        return jsonify({"status": "ok"})

    return jsonify({"error": "Unknown action"}), 400

@app.route('/api/check-server', methods=['POST'])
def api_check_server():
    from urllib.parse import urlparse
    import socket
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

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
