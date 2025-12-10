#!/usr/bin/env python3
"""
Cloudflared优化系统Web界面
"""

from flask import Flask, render_template, jsonify, send_from_directory
import json
from datetime import datetime
from pathlib import Path
import threading
import time

# 配置路径
BASE_DIR = Path("/etc/cloudflared-optimizer")
RESULTS_DIR = BASE_DIR / "results"
LATEST_RESULT = RESULTS_DIR / "latest.json"

app = Flask(__name__, 
           template_folder=str(BASE_DIR / "templates"),
           static_folder=str(BASE_DIR / "static"))

def get_latest_results():
    """获取最新结果"""
    if LATEST_RESULT.exists():
        try:
            with open(LATEST_RESULT, 'r', encoding='utf-8') as f:
                return json.load(f)
        except:
            pass
    return {"error": "没有可用的测试结果"}

def get_history_results():
    """获取历史结果"""
    history = []
    if RESULTS_DIR.exists():
        for file in RESULTS_DIR.glob("detailed_*.json"):
            try:
                with open(file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    history.append({
                        'timestamp': data.get('timestamp', ''),
                        'best_domain': data.get('best_domain', {}).get('domain', ''),
                        'best_score': data.get('best_domain', {}).get('score', 0),
                        'file': file.name
                    })
            except:
                continue
    
    # 按时间排序
    history.sort(key=lambda x: x['timestamp'], reverse=True)
    return history[:50]  # 返回最近50条记录

@app.route('/')
def index():
    """主页"""
    results = get_latest_results()
    history = get_history_results()
    
    return render_template('index.html', 
                         results=results,
                         history=history,
                         update_time=datetime.now().strftime('%Y-%m-%d %H:%M:%S'))

@app.route('/api/results/latest')
def api_latest_results():
    """API：获取最新结果"""
    return jsonify(get_latest_results())

@app.route('/api/results/history')
def api_history_results():
    """API：获取历史结果"""
    return jsonify(get_history_results())

@app.route('/api/domains')
def api_domains():
    """API：获取域名列表"""
    domains_file = BASE_DIR / "domains.txt"
    if domains_file.exists():
        with open(domains_file, 'r', encoding='utf-8') as f:
            domains = [line.strip() for line in f if line.strip()]
        return jsonify({"domains": domains})
    return jsonify({"domains": []})

@app.route('/api/run-test')
def api_run_test():
    """API：运行测试"""
    def run_test_background():
        import subprocess
        subprocess.run(['python3', str(BASE_DIR / 'cf-optimizer.py')], 
                      cwd=str(BASE_DIR.parent))
    
    # 在后台运行测试
    thread = threading.Thread(target=run_test_background)
    thread.daemon = True
    thread.start()
    
    return jsonify({"status": "测试已开始运行"})

@app.route('/api/status')
def api_status():
    """API：系统状态"""
    status = {
        "system_time": datetime.now().isoformat(),
        "last_update": None,
        "best_domain": None,
        "best_score": 0,
        "cloudflared_running": False
    }
    
    # 检查最新结果
    latest = get_latest_results()
    if "best_domain" in latest and latest["best_domain"]:
        status["last_update"] = latest.get("timestamp")
        status["best_domain"] = latest["best_domain"].get("domain")
        status["best_score"] = latest["best_domain"].get("score", 0)
    
    # 检查cloudflared服务状态
    import subprocess
    try:
        result = subprocess.run(['systemctl', 'is-active', 'cloudflared'],
                               capture_output=True, text=True)
        status["cloudflared_running"] = result.stdout.strip() == 'active'
    except:
        pass
    
    return jsonify(status)

@app.route('/static/<path:filename>')
def static_files(filename):
    """静态文件"""
    return send_from_directory(str(BASE_DIR / "static"), filename)

# 创建必要的目录和文件
def init_web_files():
    """初始化Web文件"""
    # 创建目录
    templates_dir = BASE_DIR / "templates"
    static_dir = BASE_DIR / "static"
    templates_dir.mkdir(exist_ok=True)
    static_dir.mkdir(exist_ok=True)
    
    # 创建HTML模板
    index_html = templates_dir / "index.html"
    if not index_html.exists():
        html_content = '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cloudflared域名优化系统</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body {
            background-color: #f5f5f5;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        .navbar {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .card {
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            margin-bottom: 20px;
            transition: transform 0.3s;
        }
        .card:hover {
            transform: translateY(-5px);
        }
        .status-badge {
            font-size: 0.8em;
            padding: 5px 10px;
            border-radius: 20px;
        }
        .latency-good { color: #28a745; }
        .latency-ok { color: #ffc107; }
        .latency-bad { color: #dc3545; }
        .progress-bar {
            transition: width 1s ease-in-out;
        }
        .domain-table {
            font-size: 0.9em;
        }
        .refresh-btn {
            cursor: pointer;
            transition: transform 0.5s;
        }
        .refresh-btn:hover {
            transform: rotate(180deg);
        }
    </style>
</head>
<body>
    <!-- 导航栏 -->
    <nav class="navbar navbar-dark navbar-expand-lg mb-4">
        <div class="container">
            <a class="navbar-brand" href="/">
                <i class="fas fa-cloud me-2"></i>
                Cloudflared域名优化系统
            </a>
            <div class="navbar-text text-white">
                <i class="fas fa-sync-alt refresh-btn me-2" onclick="refreshData()"></i>
                <span id="updateTime">最后更新: {{ update_time }}</span>
            </div>
        </div>
    </nav>

    <div class="container">
        <!-- 状态卡片 -->
        <div class="row mb-4">
            <div class="col-md-3">
                <div class="card">
                    <div class="card-body text-center">
                        <h5><i class="fas fa-tachometer-alt text-primary"></i> 当前状态</h5>
                        <div id="serviceStatus"