# 首先，删除可能损坏的文件
cd /opt
rm -rf cf-optimizer-install
mkdir cf-optimizer-install
cd cf-optimizer-install

# 创建新的setup.sh文件
cat > setup.sh << 'EOF'
#!/bin/bash
# Cloudflared优化系统安装脚本

set -e

echo "========================================="
echo " Cloudflared 智能域名优化系统安装程序"
echo "========================================="

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo "请使用root权限运行此脚本: sudo bash setup.sh"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖包..."
    
    # 检测系统类型
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y python3 python3-pip python3-venv curl dnsutils iputils-ping bc wget
        apt-get install -y systemctl || true
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS
        yum install -y python3 python3-pip curl bind-utils iputils bc wget
        yum install -y systemd || true
    elif [ -f /etc/arch-release ]; then
        # Arch Linux
        pacman -Syu --noconfirm python python-pip curl dnsutils iputils bc wget
    else
        log_warn "未知系统类型，尝试安装基本工具..."
        # 尝试通用安装
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y python3 python3-pip curl dnsutils iputils-ping bc wget
        elif command -v yum &> /dev/null; then
            yum install -y python3 python3-pip curl bind-utils iputils bc wget
        fi
    fi
    
    # 安装Python包
    log_info "安装Python依赖包..."
    pip3 install --upgrade pip
    pip3 install requests geoip2 pyyaml flask
}

# 安装cloudflared
install_cloudflared() {
    log_info "安装cloudflared..."
    
    # 检查是否已安装
    if command -v cloudflared &> /dev/null; then
        log_info "cloudflared已安装，跳过安装步骤"
        return 0
    fi
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        arm*)
            ARCH="arm"
            ;;
        *)
            ARCH="amd64"
            ;;
    esac
    
    log_info "系统架构: $ARCH"
    
    # 下载cloudflared
    log_info "下载cloudflared..."
    if ! wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" -O /usr/local/bin/cloudflared; then
        log_error "下载cloudflared失败"
        return 1
    fi
    
    chmod +x /usr/local/bin/cloudflared
    
    # 创建cloudflared目录
    mkdir -p /etc/cloudflared
    
    # 创建默认配置文件
    if [ ! -f /etc/cloudflared/config.yml ]; then
        cat > /etc/cloudflared/config.yml << 'CFEOF'
# Cloudflared 配置文件
# 通过cf-optimizer.py自动更新

proxy-dns: true
proxy-dns-port: 5053
proxy-dns-upstream:
  - https://cloudflare-dns.com/dns-query
  - https://1.1.1.1/dns-query
  - https://1.0.0.1/dns-query

# 可选：设置日志级别
logfile: /var/log/cloudflared.log
loglevel: info
CFEOF
    fi
    
    # 创建服务文件
    cat > /etc/systemd/system/cloudflared.service << 'CFSERVICEEOF'
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared --config /etc/cloudflared/config.yml tunnel run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
CFSERVICEEOF
    
    systemctl daemon-reload
    log_info "cloudflared安装完成"
}

# 下载GeoIP数据库
download_geoip_db() {
    log_info "配置GeoIP数据库..."
    
    GEOIP_DIR="/etc/cloudflared-optimizer"
    GEOIP_DB="$GEOIP_DIR/GeoLite2-City.mmdb"
    
    # 创建目录
    mkdir -p "$GEOIP_DIR"
    
    # 检查是否已有数据库
    if [ -f "$GEOIP_DB" ]; then
        log_info "GeoIP数据库已存在"
        return 0
    fi
    
    log_warn "需要配置GeoIP数据库以支持地理位置优选"
    echo ""
    echo "请选择GeoIP数据库配置方式:"
    echo "1. 使用免费版本（需要手动下载）"
    echo "2. 跳过（将无法使用地理位置优选功能）"
    echo ""
    read -p "请选择 [1/2]: " choice
    
    case $choice in
        1)
            echo ""
            echo "请按以下步骤操作:"
            echo "1. 访问: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data"
            echo "2. 注册免费账户"
            echo "3. 登录后下载 GeoLite2 City 数据库 (MMDB格式)"
            echo "4. 将下载的文件重命名为 GeoLite2-City.mmdb"
            echo "5. 复制到: $GEOIP_DB"
            echo ""
            read -p "按回车键继续..." _
            ;;
        2)
            log_info "跳过GeoIP数据库配置"
            ;;
        *)
            log_info "使用免费版本选项"
            ;;
    esac
    
    # 检查数据库是否存在
    if [ -f "$GEOIP_DB" ]; then
        log_info "GeoIP数据库配置成功"
    else
        log_warn "GeoIP数据库未配置，地理位置优选功能将不可用"
    fi
}

# 安装优化系统
install_optimizer() {
    log_info "安装优化系统..."
    
    # 创建目录结构
    mkdir -p /etc/cloudflared-optimizer/{results,logs,templates,static}
    
    # 检查当前目录是否有脚本文件
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 创建主脚本（如果不存在）
    if [ ! -f "/etc/cloudflared-optimizer/cf-optimizer.py" ]; then
        log_info "创建主脚本..."
        cat > /etc/cloudflared-optimizer/cf-optimizer.py << 'PYEOF'
#!/usr/bin/env python3
"""
Cloudflared 智能域名优化系统 - 简化版本
"""

import os
import sys
import json
import time
import logging
import subprocess
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests
from pathlib import Path

# 配置路径
BASE_DIR = Path("/etc/cloudflared-optimizer")
CONFIG_FILE = BASE_DIR / "config.json"
DOMAINS_FILE = BASE_DIR / "domains.txt"
RESULTS_DIR = BASE_DIR / "results"
LOG_DIR = BASE_DIR / "logs"

# 确保目录存在
for directory in [BASE_DIR, RESULTS_DIR, LOG_DIR]:
    directory.mkdir(parents=True, exist_ok=True)

# 设置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_DIR / f"cf-optimizer-{datetime.now().strftime('%Y%m%d')}.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class CloudflaredOptimizer:
    def __init__(self):
        self.config = self.load_config()
        self.domains = self.load_domains()
    
    def load_config(self):
        """加载配置文件"""
        default_config = {
            "test_count": 3,
            "timeout": 3,
            "max_threads": 10,
            "min_success_rate": 80,
            "auto_update_config": True,
            "restart_cloudflared": True,
            "cloudflared_config": "/etc/cloudflared/config.yml",
            "update_interval": 3600,
            "speed_test": True,
            "speed_test_size": 102400,
        }
        
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                user_config = json.load(f)
                default_config.update(user_config)
        
        # 保存配置
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(default_config, f, indent=2, ensure_ascii=False)
        
        return default_config
    
    def load_domains(self):
        """加载域名列表"""
        default_domains = [
            "cf.cdn.cloudflare.net",
            "cdn.cloudflare.net",
            "one.one.one.one",
            "1.1.1.1",
            "1.0.0.1",
            "dns.cloudflare.com",
            "speed.cloudflare.com",
            "cloudflare.com",
            "www.cloudflare.com",
            "time.cloudflare.com",
        ]
        
        if DOMAINS_FILE.exists():
            with open(DOMAINS_FILE, 'r', encoding='utf-8') as f:
                custom_domains = [line.strip() for line in f if line.strip() and not line.startswith('#')]
                if custom_domains:
                    return custom_domains
        
        # 保存默认域名列表
        with open(DOMAINS_FILE, 'w', encoding='utf-8') as f:
            for domain in default_domains:
                f.write(f"{domain}\n")
        
        return default_domains
    
    def test_latency(self, domain):
        """测试域名延迟"""
        try:
            # 使用curl测试
            start = time.time()
            response = requests.get(
                f'https://{domain}',
                timeout=self.config['timeout'],
                headers={'User-Agent': 'Mozilla/5.0'}
            )
            if response.status_code < 400:
                return (time.time() - start) * 1000  # 转换为毫秒
        except:
            try:
                # 尝试ping测试
                cmd = ['ping', '-c', '2', '-W', str(self.config['timeout']), domain]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=self.config['timeout']+2)
                
                if result.returncode == 0:
                    lines = result.stdout.strip().split('\n')
                    for line in lines:
                        if 'min/avg/max' in line:
                            stats = line.split('=')[1].split('/')
                            return float(stats[1])  # 返回平均延迟
            except:
                pass
        
        return None
    
    def test_domain(self, domain):
        """测试域名"""
        result = {
            'domain': domain,
            'latencies': [],
            'success_count': 0,
            'tests_count': self.config['test_count'],
            'score': 0
        }
        
        # 测试延迟
        for _ in range(self.config['test_count']):
            latency = self.test_latency(domain)
            if latency is not None:
                result['latencies'].append(latency)
                result['success_count'] += 1
            
            time.sleep(0.2)  # 避免请求过密
        
        # 计算统计数据
        if result['latencies']:
            result['avg_latency'] = sum(result['latencies']) / len(result['latencies'])
            result['min_latency'] = min(result['latencies'])
            result['max_latency'] = max(result['latencies'])
            result['success_rate'] = (result['success_count'] / result['tests_count']) * 100
            
            # 计算分数
            if result['success_rate'] >= self.config['min_success_rate']:
                # 基础分数
                score = result['success_rate']
                # 延迟加成
                if result['avg_latency'] < 50:
                    score += 30
                elif result['avg_latency'] < 100:
                    score += 25
                elif result['avg_latency'] < 200:
                    score += 20
                else:
                    score += 10
                result['score'] = score
        else:
            result['avg_latency'] = 9999
            result['success_rate'] = 0
            result['score'] = 0
        
        return result
    
    def run_tests(self):
        """运行所有测试"""
        logger.info("开始域名优选测试...")
        logger.info(f"测试域名数量: {len(self.domains)}")
        
        results = []
        
        # 使用线程池并发测试
        with ThreadPoolExecutor(max_workers=self.config['max_threads']) as executor:
            future_to_domain = {
                executor.submit(self.test_domain, domain): domain
                for domain in self.domains
            }
            
            completed = 0
            for future in as_completed(future_to_domain):
                domain = future_to_domain[future]
                try:
                    result = future.result(timeout=self.config['timeout'] * self.config['test_count'] + 5)
                    results.append(result)
                    completed += 1
                    
                    logger.info(f"测试进度: {completed}/{len(self.domains)} - {domain}: "
                               f"延迟{result.get('avg_latency', 0):.1f}ms, "
                               f"成功率{result.get('success_rate', 0):.1f}%")
                except Exception as e:
                    logger.error(f"测试域名 {domain} 失败: {e}")
        
        # 按分数排序
        results.sort(key=lambda x: x['score'], reverse=True)
        
        # 保存结果
        self.save_results(results)
        
        return results
    
    def save_results(self, results):
        """保存测试结果"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        # 保存详细结果
        detailed_result = {
            'timestamp': datetime.now().isoformat(),
            'config': self.config,
            'results': results,
            'best_domain': results[0] if results else None
        }
        
        result_file = RESULTS_DIR / f"detailed_{timestamp}.json"
        with open(result_file, 'w', encoding='utf-8') as f:
            json.dump(detailed_result, f, indent=2, ensure_ascii=False)
        
        # 保存最新结果
        latest_file = RESULTS_DIR / "latest.json"
        with open(latest_file, 'w', encoding='utf-8') as f:
            json.dump(detailed_result, f, indent=2, ensure_ascii=False)
        
        # 保存最佳域名
        if results:
            best_domain = results[0]['domain']
            best_file = RESULTS_DIR / "best-domain.txt"
            with open(best_file, 'w', encoding='utf-8') as f:
                f.write(best_domain)
        
        logger.info(f"结果已保存到: {result_file}")
    
    def update_cloudflared_config(self, domain):
        """更新Cloudflared配置文件"""
        config_path = Path(self.config['cloudflared_config'])
        
        if not config_path.exists():
            logger.warning(f"Cloudflared配置文件不存在: {config_path}")
            return False
        
        try:
            # 读取现有配置
            with open(config_path, 'r', encoding='utf-8') as f:
                config_content = f.read()
            
            # 更新域名
            lines = config_content.split('\n')
            updated_lines = []
            in_upstream = False
            
            for line in lines:
                if 'proxy-dns-upstream:' in line.lower():
                    updated_lines.append(line)
                    in_upstream = True
                elif in_upstream and line.strip().startswith('- https://'):
                    # 跳过旧的域名配置
                    continue
                elif in_upstream and line and not line.startswith('  '):
                    # 结束upstream部分
                    in_upstream = False
                    updated_lines.append(f'  - https://{domain}/dns-query')
                    updated_lines.append('  - https://1.1.1.1/dns-query')
                    updated_lines.append('  - https://1.0.0.1/dns-query')
                    updated_lines.append(line)
                else:
                    updated_lines.append(line)
            
            # 如果没找到upstream部分，添加到末尾
            if not in_upstream:
                if updated_lines and not updated_lines[-1].strip():
                    updated_lines.pop()
                updated_lines.append('proxy-dns-upstream:')
                updated_lines.append(f'  - https://{domain}/dns-query')
                updated_lines.append('  - https://1.1.1.1/dns-query')
                updated_lines.append('  - https://1.0.0.1/dns-query')
            
            # 备份原文件
            backup_path = config_path.with_suffix(f'.bak.{datetime.now().strftime("%Y%m%d_%H%M%S")}')
            import shutil
            shutil.copy2(config_path, backup_path)
            
            # 写入新配置
            with open(config_path, 'w', encoding='utf-8') as f:
                f.write('\n'.join(updated_lines))
            
            logger.info(f"Cloudflared配置已更新，使用域名: {domain}")
            logger.info(f"原配置已备份到: {backup_path}")
            
            return True
            
        except Exception as e:
            logger.error(f"更新Cloudflared配置失败: {e}")
            return False
    
    def restart_cloudflared(self):
        """重启Cloudflared服务"""
        try:
            result = subprocess.run(
                ['systemctl', 'restart', 'cloudflared'],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                logger.info("Cloudflared服务重启成功")
                
                # 检查服务状态
                time.sleep(2)
                status_result = subprocess.run(
                    ['systemctl', 'status', '--no-pager', 'cloudflared'],
                    capture_output=True,
                    text=True
                )
                
                if status_result.returncode == 0:
                    logger.info("Cloudflared服务运行正常")
                else:
                    logger.warning("Cloudflared服务状态异常")
                
                return True
            else:
                logger.error(f"重启Cloudflared失败: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"重启Cloudflared失败: {e}")
            return False
    
    def run(self):
        """运行优化流程"""
        logger.info("=" * 60)
        logger.info("Cloudflared域名优化系统启动")
        logger.info(f"开始时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        logger.info("=" * 60)
        
        # 获取当前使用的域名
        current_domain = None
        config_path = Path(self.config['cloudflared_config'])
        if config_path.exists():
            try:
                with open(config_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    import re
                    matches = re.findall(r'https://([^/]+)/dns-query', content)
                    if matches:
                        current_domain = matches[0]
            except:
                pass
        
        logger.info(f"当前使用域名: {current_domain or '未知'}")
        
        # 运行测试
        results = self.run_tests()
        
        if not results:
            logger.error("没有获得有效的测试结果")
            return False
        
        # 显示结果
        self.display_results(results)
        
        # 获取最佳域名
        best_result = results[0]
        best_domain = best_result['domain']
        
        if best_domain == current_domain:
            logger.info("当前域名已经是最佳选择，无需更新")
            return True
        
        # 检查是否满足更新条件
        if best_result['score'] < 60:
            logger.warning(f"最佳域名分数较低 ({best_result['score']})，暂不更新")
            return False
        
        # 更新配置
        if self.config['auto_update_config']:
            if self.update_cloudflared_config(best_domain):
                # 重启服务
                if self.config['restart_cloudflared']:
                    self.restart_cloudflared()
                
                logger.info("域名优化完成并已应用新配置")
            else:
                logger.error("更新配置失败")
                return False
        else:
            logger.info("自动更新已禁用，最佳域名: " + best_domain)
        
        return True
    
    def display_results(self, results):
        """显示测试结果"""
        print("\n" + "=" * 80)
        print("Cloudflared 域名优选测试结果")
        print(f"测试时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80)
        print(f"{'排名':<4} {'域名':<30} {'延迟(ms)':<10} {'成功率(%)':<10} {'分数':<8}")
        print("-" * 80)
        
        for i, result in enumerate(results[:15], 1):
            if result['score'] > 0:
                print(f"{i:<4} {result['domain']:<30} "
                      f"{result.get('avg_latency', 0):<10.1f} "
                      f"{result.get('success_rate', 0):<10.1f} "
                      f"{result.get('score', 0):<8.1f}")
            else:
                print(f"{i:<4} {result['domain']:<30} {'失败':<28}")
        
        print("=" * 80)
        
        # 显示最佳域名详情
        if results:
            best = results[0]
            print(f"\n🎉 推荐域名: {best['domain']}")
            print(f"   平均延迟: {best.get('avg_latency', 0):.1f}ms")
            print(f"   成功率: {best.get('success_rate', 0):.1f}%")
            print(f"   综合分数: {best.get('score', 0):.1f}")

def main():
    """主函数"""
    # 检查是否为root用户
    if os.geteuid() != 0:
        print("请使用root权限运行此脚本！")
        print("sudo python3 cf-optimizer.py")
        sys.exit(1)
    
    print("Cloudflared 智能域名优化系统")
    print("=" * 60)
    
    optimizer = CloudflaredOptimizer()
    
    try:
        success = optimizer.run()
        if success:
            print("\n✅ 优化完成！")
        else:
            print("\n⚠ 优化过程中出现问题，请检查日志")
    except KeyboardInterrupt:
        print("\n\n⚠ 测试被用户中断")
        sys.exit(130)
    except Exception as e:
        print(f"\n❌ 发生错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
PYEOF
        chmod +x /etc/cloudflared-optimizer/cf-optimizer.py
    else
        log_info "主脚本已存在，跳过创建"
    fi
    
    # 创建Web界面脚本（如果不存在）
    if [ ! -f "/etc/cloudflared-optimizer/web-ui.py" ]; then
        log_info "创建Web界面脚本..."
        cat > /etc/cloudflared-optimizer/web-ui.py << 'WEBEOF'
#!/usr/bin/env python3
"""
Cloudflared优化系统Web界面 - 简化版本
"""

from flask import Flask, jsonify
import json
from datetime import datetime
from pathlib import Path
import subprocess

# 配置路径
BASE_DIR = Path("/etc/cloudflared-optimizer")
RESULTS_DIR = BASE_DIR / "results"
LATEST_RESULT = RESULTS_DIR / "latest.json"

app = Flask(__name__)

def get_latest_results():
    """获取最新结果"""
    if LATEST_RESULT.exists():
        try:
            with open(LATEST_RESULT, 'r', encoding='utf-8') as f:
                return json.load(f)
        except:
            pass
    return {"error": "没有可用的测试结果"}

@app.route('/')
def index():
    """主页"""
    results = get_latest_results()
    
    html = '''
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Cloudflared域名优化系统</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
        <style>
            body { background-color: #f5f5f5; font-family: Arial, sans-serif; }
            .navbar { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
            .card { border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); margin-bottom: 20px; }
            .latency-good { color: #28a745; }
            .latency-ok { color: #ffc107; }
            .latency-bad { color: #dc3545; }
        </style>
    </head>
    <body>
        <nav class="navbar navbar-dark mb-4">
            <div class="container">
                <span class="navbar-brand">Cloudflared域名优化系统</span>
                <span class="navbar-text text-white">
                    最后更新: ''' + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + '''
                </span>
            </div>
        </nav>
        
        <div class="container">
            <div class="row mb-4">
                <div class="col-12">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="mb-0">控制面板</h5>
                        </div>
                        <div class="card-body">
                            <button class="btn btn-primary me-2" onclick="runTest()">立即测试</button>
                            <button class="btn btn-success me-2" onclick="location.reload()">刷新页面</button>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="row">
                <div class="col-lg-8">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="mb-0">域名排名</h5>
                        </div>
                        <div class="card-body">
                            <div id="results"></div>
                        </div>
                    </div>
                </div>
                
                <div class="col-lg-4">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="mb-0">系统状态</h5>
                        </div>
                        <div class="card-body">
                            <div id="status"></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <script>
            function loadResults() {
                fetch('/api/results/latest')
                    .then(response => response.json())
                    .then(data => {
                        if (data.error) {
                            document.getElementById('results').innerHTML = 
                                '<p class="text-danger">' + data.error + '</p>';
                            return;
                        }
                        
                        let html = '<table class="table table-sm"><thead><tr>' +
                            '<th>排名</th><th>域名</th><th>延迟</th><th>成功率</th><th>分数</th>' +
                            '</tr></thead><tbody>';
                        
                        if (data.results) {
                            data.results.slice(0, 10).forEach((result, index) => {
                                const latencyClass = getLatencyClass(result.avg_latency);
                                html += '<tr>' +
                                    '<td>' + (index + 1) + '</td>' +
                                    '<td><small>' + result.domain + '</small></td>' +
                                    '<td class="' + latencyClass + '">' + 
                                        (result.avg_latency ? result.avg_latency.toFixed(1) + 'ms' : '-') + '</td>' +
                                    '<td>' + (result.success_rate ? result.success_rate.toFixed(1) + '%' : '0%') + '</td>' +
                                    '<td>' + (result.score ? result.score.toFixed(1) : '0') + '</td>' +
                                    '</tr>';
                            });
                        }
                        
                        html += '</tbody></table>';
                        document.getElementById('results').innerHTML = html;
                        
                        // 更新状态
                        if (data.best_domain) {
                            document.getElementById('status').innerHTML = 
                                '<p><strong>最佳域名:</strong> ' + data.best_domain.domain + '</p>' +
                                '<p><strong>平均延迟:</strong> ' + data.best_domain.avg_latency.toFixed(1) + 'ms</p>' +
                                '<p><strong>成功率:</strong> ' + data.best_domain.success_rate.toFixed(1) + '%</p>' +
                                '<p><strong>分数:</strong> ' + data.best_domain.score.toFixed(1) + '</p>' +
                                '<p><strong>测试时间:</strong> ' + new Date(data.timestamp).toLocaleString() + '</p>';
                        }
                    })
                    .catch(error => {
                        document.getElementById('results').innerHTML = 
                            '<p class="text-danger">加载数据失败: ' + error + '</p>';
                    });
            }
            
            function getLatencyClass(latency) {
                if (!latency) return '';
                if (latency < 100) return 'latency-good';
                if (latency < 200) return 'latency-ok';
                return 'latency-bad';
            }
            
            function runTest() {
                fetch('/api/run-test')
                    .then(response => response.json())
                    .then(data => {
                        alert('测试已开始运行，请稍后刷新页面查看结果');
                    })
                    .catch(error => {
                        alert('启动测试失败: ' + error);
                    });
            }
            
            // 页面加载时获取数据
            window.onload = loadResults;
        </script>
    </body>
    </html>
    '''
    
    return html

@app.route('/api/results/latest')
def api_latest_results():
    """API：获取最新结果"""
    return jsonify(get_latest_results())

@app.route('/api/run-test')
def api_run_test():
    """API：运行测试"""
    def run_test_background():
        subprocess.run(['python3', '/etc/cloudflared-optimizer/cf-optimizer.py'], 
                      cwd='/etc/cloudflared-optimizer')
    
    import threading
    thread = threading.Thread(target=run_test_background)
    thread.daemon = True
    thread.start()
    
    return jsonify({"status": "测试已开始运行"})

if __name__ == "__main__":
    print("Cloudflared优化系统Web界面")
    print("访问地址: http://127.0.0.1:5000")
    print("按 Ctrl+C 停止服务器")
    app.run(host='0.0.0.0', port=5000, debug=False)
WEBEOF
        chmod +x /etc/cloudflared-optimizer/web-ui.py
    else
        log_info "Web界面脚本已存在，跳过创建"
    fi
    
    # 创建配置文件
    if [ ! -f /etc/cloudflared-optimizer/config.json ]; then
        cat > /etc/cloudflared-optimizer/config.json << 'CFGEOF'
{
    "test_count": 3,
    "timeout": 3,
    "max_threads": 10,
    "min_success_rate": 80,
    "auto_update_config": true,
    "restart_cloudflared": true,
    "cloudflared_config": "/etc/cloudflared/config.yml",
    "update_interval": 3600,
    "speed_test": true,
    "speed_test_size": 102400
}
CFGEOF
        log_info "创建配置文件"
    fi
    
    # 创建域名列表
    if [ ! -f /etc/cloudflared-optimizer/domains.txt ]; then
        cat > /etc/cloudflared-optimizer/domains.txt << 'DOMAINSEOF'
cf.cdn.cloudflare.net
cdn.cloudflare.net
one.one.one.one
1.1.1.1
1.0.0.1
dns.cloudflare.com
speed.cloudflare.com
cloudflare.com
www.cloudflare.com
time.cloudflare.com
DOMAINSEOF
        log_info "创建域名列表"
    fi
    
    log_info "优化系统文件安装完成"
}

# 配置系统服务
setup_services() {
    log_info "配置系统服务..."
    
    # 创建定时服务
    cat > /etc/systemd/system/cf-optimizer.timer << 'TIMEREOF'
[Unit]
Description=定时运行Cloudflared优化
Requires=cf-optimizer.service

[Timer]
OnCalendar=*-*-* 0,6,12,18:00:00
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF
    
    # 创建优化服务
    cat > /etc/systemd/system/cf-optimizer.service << 'SERVICEEOF'
[Unit]
Description=Cloudflared域名优化服务
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/bin/python3 /etc/cloudflared-optimizer/cf-optimizer.py
WorkingDirectory=/etc/cloudflared-optimizer
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF
    
    # 创建Web界面服务
    cat > /etc/systemd/system/cf-webui.service << 'WEBUIEOF'
[Unit]
Description=Cloudflared优化系统Web界面
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/cloudflared-optimizer
ExecStart=/usr/bin/python3 /etc/cloudflared-optimizer/web-ui.py
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
WEBUIEOF
    
    # 启用服务
    systemctl daemon-reload
    
    # 启用定时任务
    systemctl enable cf-optimizer.timer
    systemctl start cf-optimizer.timer
    
    log_info "定时服务已启用（每天0,6,12,18点运行）"
    
    # 询问是否启用Web界面
    echo ""
    read -p "是否启用Web界面服务？[Y/n]: " choice
    choice=${choice:-Y}
    
    if [[ $choice =~ ^[Yy]$ ]]; then
        systemctl enable cf-webui.service
        systemctl start cf-webui.service
        log_info "Web界面已启用，访问: http://服务器IP:5000"
    fi
    
    # 询问是否启用cloudflared服务
    echo ""
    read -p "是否启用并启动cloudflared服务？[Y/n]: " choice
    choice=${choice:-Y}
    
    if [[ $choice =~ ^[Yy]$ ]]; then
        systemctl enable cloudflared.service
        systemctl start cloudflared.service
        log_info "cloudflared服务已启用"
    fi
}

# 第一次运行测试
run_first_test() {
    log_info "运行第一次测试..."
    
    echo ""
    read -p "是否现在运行第一次域名测试？[Y/n]: " choice
    choice=${choice:-Y}
    
    if [[ $choice =~ ^[Yy]$ ]]; then
        cd /etc/cloudflared-optimizer
        python3 cf-optimizer.py
        
        if [ $? -eq 0 ]; then
            log_info "测试完成！"
            
            # 显示最佳域名
            if [ -f "/etc/cloudflared-optimizer/results/best-domain.txt" ]; then
                echo ""
                echo "最佳域名: $(cat /etc/cloudflared-optimizer/results/best-domain.txt)"
            fi
        else
            log_warn "测试过程中出现警告"
        fi
    fi
}

# 显示使用说明
show_usage() {
    echo ""
    echo "========================================="
    echo "安装完成！"
    echo "========================================="
    echo ""
    echo "主要文件位置:"
    echo "  /etc/cloudflared-optimizer/cf-optimizer.py    # 主脚本"
    echo "  /etc/cloudflared-optimizer/web-ui.py         # Web界面"
    echo "  /etc/cloudflared-optimizer/config.json       # 配置文件"
    echo "  /etc/cloudflared-optimizer/domains.txt       # 域名列表"
    echo ""
    echo "使用方法:"
    echo "1. 手动运行测试:"
    echo "   sudo python3 /etc/cloudflared-optimizer/cf-optimizer.py"
    echo ""
    echo "2. 访问Web界面:"
    echo "   http://服务器IP:5000"
    echo ""
    echo "3. 查看服务状态:"
    echo "   sudo systemctl status cf-optimizer.timer"
    echo "   sudo systemctl status cf-webui.service"
    echo "   sudo systemctl status cloudflared"
    echo ""
    echo "4. 查看测试结果:"
    echo "   sudo cat /etc/cloudflared-optimizer/results/best-domain.txt"
    echo ""
    echo "========================================="
}

# 主安装流程
main() {
    echo "开始安装Cloudflared优化系统..."
    echo ""
    
    # 安装依赖
    install_dependencies
    
    # 安装cloudflared
    install_cloudflared
    
    # 配置GeoIP数据库
    download_geoip_db
    
    # 安装优化系统
    install_optimizer
    
    # 配置服务
    setup_services
    
    # 第一次运行测试
    run_first_test
    
    # 显示使用说明
    show_usage
    
    log_info "安装完成！"
}

# 运行主函数
main "$@"
EOF

# 设置权限
chmod +x setup.sh

echo "安装脚本创建完成！"