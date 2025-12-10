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
                        <div id="serviceStatus" class="mt-2">
                            <span class="badge bg-secondary">检查中...</span>
                        </div>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card">
                    <div class="card-body text-center">
                        <h5><i class="fas fa-star text-warning"></i> 最佳域名</h5>
                        <h4 id="bestDomain" class="mt-2">-</h4>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card">
                    <div class="card-body text-center">
                        <h5><i class="fas fa-bolt text-success"></i> 平均延迟</h5>
                        <h4 id="avgLatency" class="mt-2">-</h4>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card">
                    <div class="card-body text-center">
                        <h5><i class="fas fa-chart-line text-info"></i> 综合分数</h5>
                        <h4 id="totalScore" class="mt-2">-</h4>
                    </div>
                </div>
            </div>
        </div>

        <!-- 控制面板 -->
        <div class="row mb-4">
            <div class="col-12">
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="fas fa-sliders-h"></i> 控制面板</h5>
                    </div>
                    <div class="card-body">
                        <div class="d-grid gap-2 d-md-flex justify-content-md-center">
                            <button class="btn btn-primary me-2" onclick="runTest()">
                                <i class="fas fa-play-circle me-1"></i> 立即测试
                            </button>
                            <button class="btn btn-success me-2" onclick="applyBestDomain()">
                                <i class="fas fa-check-circle me-1"></i> 应用最佳域名
                            </button>
                            <button class="btn btn-info me-2" onclick="showConfig()">
                                <i class="fas fa-cog me-1"></i> 查看配置
                            </button>
                            <button class="btn btn-warning" onclick="showHistory()">
                                <i class="fas fa-history me-1"></i> 历史记录
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- 域名排名 -->
        <div class="row">
            <div class="col-lg-8">
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="fas fa-trophy"></i> 域名排名</h5>
                    </div>
                    <div class="card-body">
                        <div class="table-responsive">
                            <table class="table table-hover domain-table">
                                <thead>
                                    <tr>
                                        <th>排名</th>
                                        <th>域名</th>
                                        <th>延迟</th>
                                        <th>速度</th>
                                        <th>成功率</th>
                                        <th>分数</th>
                                        <th>位置</th>
                                        <th>状态</th>
                                    </tr>
                                </thead>
                                <tbody id="domainTable">
                                    <!-- 通过JavaScript填充 -->
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>

            <!-- 统计图表 -->
            <div class="col-lg-4">
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="fas fa-chart-pie"></i> 统计图表</h5>
                    </div>
                    <div class="card-body">
                        <canvas id="latencyChart" height="200"></canvas>
                        <hr>
                        <canvas id="scoreChart" height="200"></canvas>
                    </div>
                </div>
            </div>
        </div>

        <!-- 详细信息 -->
        <div class="row mt-4">
            <div class="col-12">
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="fas fa-info-circle"></i> 详细信息</h5>
                    </div>
                    <div class="card-body">
                        <pre id="detailInfo" style="max-height: 300px; overflow-y: auto;">加载中...</pre>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- 模态框 -->
    <div class="modal fade" id="historyModal" tabindex="-1">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">历史记录</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body">
                    <table class="table">
                        <thead>
                            <tr>
                                <th>时间</th>
                                <th>最佳域名</th>
                                <th>分数</th>
                                <th>操作</th>
                            </tr>
                        </thead>
                        <tbody id="historyTable">
                            <!-- 通过JavaScript填充 -->
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        let latencyChart = null;
        let scoreChart = null;

        // 初始化页面
        document.addEventListener('DOMContentLoaded', function() {
            loadData();
            setInterval(loadData, 30000); // 每30秒刷新一次
        });

        // 加载数据
        async function loadData() {
            try {
                // 加载状态
                const statusResp = await fetch('/api/status');
                const status = await statusResp.json();
                updateStatus(status);

                // 加载最新结果
                const resultsResp = await fetch('/api/results/latest');
                const results = await resultsResp.json();
                updateResults(results);

                // 更新时间
                document.getElementById('updateTime').textContent = 
                    `最后更新: ${new Date().toLocaleString()}`;
            } catch (error) {
                console.error('加载数据失败:', error);
            }
        }

        // 更新状态
        function updateStatus(status) {
            const statusEl = document.getElementById('serviceStatus');
            if (status.cloudflared_running) {
                statusEl.innerHTML = '<span class="badge bg-success">运行中</span>';
            } else {
                statusEl.innerHTML = '<span class="badge bg-danger">未运行</span>';
            }
        }

        // 更新结果
        function updateResults(results) {
            if (results.error) {
                document.getElementById('bestDomain').textContent = '无数据';
                document.getElementById('avgLatency').textContent = '-';
                document.getElementById('totalScore').textContent = '-';
                return;
            }

            const bestDomain = results.best_domain;
            if (bestDomain) {
                document.getElementById('bestDomain').textContent = bestDomain.domain;
                document.getElementById('avgLatency').textContent = 
                    bestDomain.avg_latency ? bestDomain.avg_latency.toFixed(1) + 'ms' : '-';
                document.getElementById('totalScore').textContent = 
                    bestDomain.score ? bestDomain.score.toFixed(1) : '-';
            }

            // 更新域名表格
            updateDomainTable(results.results || []);

            // 更新图表
            updateCharts(results.results || []);

            // 更新详细信息
            document.getElementById('detailInfo').textContent = 
                JSON.stringify(results, null, 2);
        }

        // 更新域名表格
        function updateDomainTable(domains) {
            const tableBody = document.getElementById('domainTable');
            tableBody.innerHTML = '';

            domains.slice(0, 20).forEach((domain, index) => {
                const latencyClass = getLatencyClass(domain.avg_latency);
                const successClass = domain.success_rate >= 80 ? 'text-success' : 
                                   domain.success_rate >= 50 ? 'text-warning' : 'text-danger';

                const row = document.createElement('tr');
                row.innerHTML = `
                    <td>${index + 1}</td>
                    <td><small>${domain.domain}</small></td>
                    <td class="${latencyClass}">${domain.avg_latency ? domain.avg_latency.toFixed(1) + 'ms' : '-'}</td>
                    <td>${domain.avg_speed ? domain.avg_speed.toFixed(1) + 'KB/s' : '-'}</td>
                    <td class="${successClass}">${domain.success_rate ? domain.success_rate.toFixed(1) + '%' : '0%'}</td>
                    <td>${domain.score ? domain.score.toFixed(1) : '0'}</td>
                    <td><small>${domain.geo_info?.country || '未知'}</small></td>
                    <td>
                        ${domain.success_rate >= 80 ? 
                          '<span class="badge bg-success">良好</span>' : 
                         domain.success_rate >= 50 ? 
                          '<span class="badge bg-warning">一般</span>' : 
                          '<span class="badge bg-danger">较差</span>'}
                    </td>
                `;
                tableBody.appendChild(row);
            });
        }

        // 更新图表
        function updateCharts(domains) {
            const validDomains = domains.filter(d => d.score > 0);
            
            // 延迟图表
            const latencyCtx = document.getElementById('latencyChart').getContext('2d');
            if (latencyChart) {
                latencyChart.destroy();
            }
            
            latencyChart = new Chart(latencyCtx, {
                type: 'bar',
                data: {
                    labels: validDomains.slice(0, 5).map(d => d.domain.substring(0, 15) + '...'),
                    datasets: [{
                        label: '延迟 (ms)',
                        data: validDomains.slice(0, 5).map(d => d.avg_latency),
                        backgroundColor: validDomains.slice(0, 5).map(d => 
                            d.avg_latency < 100 ? '#28a745' : 
                            d.avg_latency < 200 ? '#ffc107' : '#dc3545'
                        )
                    }]
                },
                options: {
                    responsive: true,
                    scales: {
                        y: {
                            beginAtZero: true,
                            title: {
                                display: true,
                                text: '延迟 (ms)'
                            }
                        }
                    }
                }
            });

            // 分数图表
            const scoreCtx = document.getElementById('scoreChart').getContext('2d');
            if (scoreChart) {
                scoreChart.destroy();
            }
            
            scoreChart = new Chart(scoreCtx, {
                type: 'pie',
                data: {
                    labels: ['优秀(>80)', '良好(60-80)', '一般(40-60)', '较差(<40)'],
                    datasets: [{
                        data: [
                            validDomains.filter(d => d.score >= 80).length,
                            validDomains.filter(d => d.score >= 60 && d.score < 80).length,
                            validDomains.filter(d => d.score >= 40 && d.score < 60).length,
                            validDomains.filter(d => d.score < 40).length
                        ],
                        backgroundColor: ['#28a745', '#17a2b8', '#ffc107', '#dc3545']
                    }]
                },
                options: {
                    responsive: true
                }
            });
        }

        // 获取延迟等级
        function getLatencyClass(latency) {
            if (!latency) return '';
            if (latency < 100) return 'latency-good';
            if (latency < 200) return 'latency-ok';
            return 'latency-bad';
        }

        // 运行测试
        async function runTest() {
            const btn = event.target;
            const originalText = btn.innerHTML;
            
            btn.disabled = true;
            btn.innerHTML = '<i class="fas fa-spinner fa-spin me-1"></i> 测试中...';
            
            try {
                const response = await fetch('/api/run-test');
                const result = await response.json();
                
                alert('测试已开始运行，请稍后刷新页面查看结果');
            } catch (error) {
                alert('启动测试失败: ' + error);
            } finally {
                setTimeout(() => {
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }, 5000);
            }
        }

        // 应用最佳域名
        function applyBestDomain() {
            if (confirm('确定要应用最佳域名并重启cloudflared服务吗？')) {
                // 这里可以添加调用API的代码
                alert('功能开发中...');
            }
        }

        // 显示历史记录
        async function showHistory() {
            try {
                const response = await fetch('/api/results/history');
                const history = await response.json();
                
                const tableBody = document.getElementById('historyTable');
                tableBody.innerHTML = '';
                
                history.forEach(item => {
                    const row = document.createElement('tr');
                    const date = new Date(item.timestamp);
                    row.innerHTML = `
                        <td>${date.toLocaleString()}</td>
                        <td><small>${item.best_domain}</small></td>
                        <td>${item.best_score.toFixed(1)}</td>
                        <td>
                            <button class="btn btn-sm btn-info" onclick="viewHistory('${item.file}')">
                                查看
                            </button>
                        </td>
                    `;
                    tableBody.appendChild(row);
                });
                
                new bootstrap.Modal(document.getElementById('historyModal')).show();
            } catch (error) {
                alert('加载历史记录失败: ' + error);
            }
        }

        // 查看历史详情
        function viewHistory(filename) {
            alert('查看历史详情: ' + filename);
            // 这里可以添加查看详情的功能
        }

        // 显示配置
        function showConfig() {
            alert('配置查看功能开发中...');
        }

        // 刷新数据
        function refreshData() {
            const refreshBtn = event.target;
            refreshBtn.classList.add('fa-spin');
            
            loadData().finally(() => {
                setTimeout(() => {
                    refreshBtn.classList.remove('fa-spin');
                }, 500);
            });
        }
    </script>
</body>
</html>'''
        
        with open(index_html, 'w', encoding='utf-8') as f:
            f.write(html_content)
        
        print("Web界面文件已初始化")

if __name__ == "__main__":
    # 初始化文件
    init_web_files()
    
    # 启动Web服务器
    print("Cloudflared优化系统Web界面")
    print("访问地址: http://127.0.0.1:5000")
    print("按 Ctrl+C 停止服务器")
    
    app.run(host='0.0.0.0', port=5000, debug=False)