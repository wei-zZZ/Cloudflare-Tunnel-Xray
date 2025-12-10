#!/usr/bin/env python3
"""
Cloudflared 智能域名优化系统
功能：
1. 多维度域名测试（延迟、速度、成功率）
2. 地理位置优选
3. 自动更新配置并重启cloudflared
4. 数据记录和报告
"""

import os
import sys
import json
import time
import logging
import subprocess
import threading
import ipaddress
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests
import geoip2.database
import yaml
from pathlib import Path

# 配置路径
BASE_DIR = Path("/etc/cloudflared-optimizer")
CONFIG_FILE = BASE_DIR / "config.json"
DOMAINS_FILE = BASE_DIR / "domains.txt"
RESULTS_DIR = BASE_DIR / "results"
LOG_DIR = BASE_DIR / "logs"
GEOIP_DB = BASE_DIR / "GeoLite2-City.mmdb"

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
        self.geoip_reader = None
        self.local_ip_info = None
        
        # 初始化GeoIP数据库
        self.init_geoip()
        
        # 获取本地IP信息
        self.get_local_ip_info()
    
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
            "update_interval": 3600,  # 1小时
            "regions": {
                "china": ["Asia/Shanghai", "Asia/Beijing", "Asia/Chongqing"],
                "europe": ["Europe/*"],
                "america": ["America/*"]
            },
            "preferred_regions": [],  # 优先选择的区域
            "speed_test": True,
            "speed_test_size": 1024 * 100,  # 100KB测试文件
            "notification": {
                "enabled": False,
                "type": "webhook",  # webhook, email, telegram
                "webhook_url": ""
            }
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
            "edge.icloud-content.com",  # Cloudflare边缘节点
            "time.cloudflare.com",
            "captive.apple.com"  # 通常也走Cloudflare
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
    
    def init_geoip(self):
        """初始化GeoIP数据库"""
        if not GEOIP_DB.exists():
            logger.warning("GeoIP数据库不存在，正在下载...")
            self.download_geoip_db()
        
        try:
            self.geoip_reader = geoip2.database.Reader(str(GEOIP_DB))
            logger.info("GeoIP数据库加载成功")
        except Exception as e:
            logger.error(f"加载GeoIP数据库失败: {e}")
            self.geoip_reader = None
    
    def download_geoip_db(self):
        """下载GeoIP数据库"""
        # 这里需要MaxMind的许可证密钥，或者使用免费版本
        # 简化处理：如果没有数据库，跳过地理位置优选
        logger.info("请手动下载GeoIP数据库并放置到: " + str(GEOIP_DB))
        logger.info("下载地址: https://dev.maxmind.com/geoip/geoip2/geolite2/")
    
    def get_local_ip_info(self):
        """获取本地IP的地理位置信息"""
        try:
            response = requests.get('https://ipinfo.io/json', timeout=5)
            self.local_ip_info = response.json()
            
            if self.geoip_reader:
                try:
                    geoip_response = self.geoip_reader.city(self.local_ip_info['ip'])
                    self.local_ip_info['latitude'] = geoip_response.location.latitude
                    self.local_ip_info['longitude'] = geoip_response.location.longitude
                    self.local_ip_info['city_name'] = geoip_response.city.name
                    self.local_ip_info['country_name'] = geoip_response.country.name
                except:
                    pass
            
            logger.info(f"本地IP信息: {self.local_ip_info.get('city', 'Unknown')}, "
                       f"{self.local_ip_info.get('region', 'Unknown')}, "
                       f"{self.local_ip_info.get('country', 'Unknown')}")
        except Exception as e:
            logger.warning(f"获取IP信息失败: {e}")
            self.local_ip_info = {'ip': 'unknown', 'country': 'unknown'}
    
    def get_domain_ip(self, domain):
        """获取域名的IP地址"""
        try:
            result = subprocess.run(
                ['dig', '+short', domain],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                ips = result.stdout.strip().split('\n')
                return [ip for ip in ips if self.is_valid_ip(ip)]
        except:
            pass
        return []
    
    def is_valid_ip(self, ip_str):
        """检查是否为有效的IP地址"""
        try:
            ipaddress.ip_address(ip_str)
            return True
        except:
            return False
    
    def test_latency(self, domain):
        """测试域名延迟"""
        try:
            # 使用ping测试
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
        
        # 如果ping失败，尝试curl测试
        try:
            start = time.time()
            response = requests.get(
                f'https://{domain}',
                timeout=self.config['timeout'],
                headers={'User-Agent': 'Mozilla/5.0'}
            )
            if response.status_code < 400:
                return (time.time() - start) * 1000  # 转换为毫秒
        except:
            pass
        
        return None
    
    def test_speed(self, domain):
        """测试下载速度"""
        if not self.config['speed_test']:
            return None
        
        try:
            test_url = f'https://{domain}/cdn-cgi/trace'
            start = time.time()
            response = requests.get(test_url, timeout=self.config['timeout'], stream=True)
            
            # 读取指定大小的数据
            total_size = 0
            chunk_size = 4096
            max_size = self.config['speed_test_size']
            
            for chunk in response.iter_content(chunk_size=chunk_size):
                total_size += len(chunk)
                if total_size >= max_size:
                    break
            
            elapsed = time.time() - start
            if elapsed > 0:
                speed = (total_size / 1024) / elapsed  # KB/s
                return speed
        except:
            pass
        
        return None
    
    def test_domain_comprehensive(self, domain):
        """综合测试域名"""
        result = {
            'domain': domain,
            'ips': [],
            'latencies': [],
            'speeds': [],
            'success_count': 0,
            'tests_count': self.config['test_count'],
            'geo_info': {},
            'score': 0
        }
        
        # 获取IP地址
        ips = self.get_domain_ip(domain)
        result['ips'] = ips
        
        if not ips:
            return result
        
        # 测试延迟和速度
        for _ in range(self.config['test_count']):
            latency = self.test_latency(domain)
            if latency is not None:
                result['latencies'].append(latency)
                result['success_count'] += 1
            
            speed = self.test_speed(domain)
            if speed is not None:
                result['speeds'].append(speed)
            
            time.sleep(0.2)  # 避免请求过密
        
        # 计算统计数据
        if result['latencies']:
            result['avg_latency'] = sum(result['latencies']) / len(result['latencies'])
            result['min_latency'] = min(result['latencies'])
            result['max_latency'] = max(result['latencies'])
            result['success_rate'] = (result['success_count'] / result['tests_count']) * 100
        else:
            result['avg_latency'] = 9999
            result['success_rate'] = 0
        
        if result['speeds']:
            result['avg_speed'] = sum(result['speeds']) / len(result['speeds'])
        else:
            result['avg_speed'] = 0
        
        # 计算综合分数
        result['score'] = self.calculate_score(result)
        
        # 获取地理位置信息
        if ips and self.geoip_reader:
            try:
                geo_response = self.geoip_reader.city(ips[0])
                result['geo_info'] = {
                    'country': geo_response.country.name,
                    'city': geo_response.city.name,
                    'latitude': geo_response.location.latitude,
                    'longitude': geo_response.location.longitude
                }
            except:
                pass
        
        return result
    
    def calculate_score(self, result):
        """计算域名综合评分"""
        if result['success_rate'] < self.config['min_success_rate']:
            return 0
        
        # 基础分：成功率
        score = result['success_rate'] / 100 * 40
        
        # 延迟分：延迟越低分数越高
        if result['avg_latency'] < 50:  # < 50ms
            score += 30
        elif result['avg_latency'] < 100:  # < 100ms
            score += 25
        elif result['avg_latency'] < 200:  # < 200ms
            score += 20
        elif result['avg_latency'] < 300:  # < 300ms
            score += 15
        else:
            score += 10
        
        # 速度分
        if result['avg_speed'] > 1000:  # > 1MB/s
            score += 30
        elif result['avg_speed'] > 500:  # > 500KB/s
            score += 25
        elif result['avg_speed'] > 200:  # > 200KB/s
            score += 20
        elif result['avg_speed'] > 100:  # > 100KB/s
            score += 15
        else:
            score += 10
        
        # 地理位置加分
        if self.local_ip_info and 'country' in self.local_ip_info:
            local_country = self.local_ip_info.get('country', '').lower()
            if result['geo_info'].get('country', '').lower() == local_country:
                score += 20
        
        return round(score, 2)
    
    def run_tests(self):
        """运行所有测试"""
        logger.info("开始域名优选测试...")
        logger.info(f"测试域名数量: {len(self.domains)}")
        logger.info(f"本地位置: {self.local_ip_info.get('city', 'Unknown')}, "
                   f"{self.local_ip_info.get('country', 'Unknown')}")
        
        results = []
        
        # 使用线程池并发测试
        with ThreadPoolExecutor(max_workers=self.config['max_threads']) as executor:
            future_to_domain = {
                executor.submit(self.test_domain_comprehensive, domain): domain
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
            'local_ip_info': self.local_ip_info,
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
            
            # 更新域名（简单替换）
            # 这里可以根据实际配置格式进行更复杂的处理
            lines = config_content.split('\n')
            updated_lines = []
            
            for line in lines:
                if 'proxy-dns-upstream:' in line.lower() or any(x in line for x in ['https://', 'dns-query']):
                    # 跳过包含URL的行，我们会在后面添加
                    continue
                updated_lines.append(line)
            
            # 添加新的DNS上游配置
            updated_lines.append('proxy-dns-upstream:')
            updated_lines.append(f'  - https://{domain}/dns-query')
            updated_lines.append('  - https://1.1.1.1/dns-query')
            updated_lines.append('  - https://1.0.0.1/dns-query')
            
            # 备份原文件
            backup_path = config_path.with_suffix(f'.bak.{datetime.now().strftime("%Y%m%d_%H%M%S")}')
            config_path.rename(backup_path)
            
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
            # 尝试不同的服务管理方式
            services = ['cloudflared', 'cloudflared.service']
            
            for service in services:
                try:
                    # systemd
                    result = subprocess.run(
                        ['systemctl', 'restart', service],
                        capture_output=True,
                        text=True,
                        timeout=30
                    )
                    
                    if result.returncode == 0:
                        logger.info(f"Cloudflared服务重启成功: {service}")
                        
                        # 检查服务状态
                        time.sleep(2)
                        status_result = subprocess.run(
                            ['systemctl', 'status', '--no-pager', service],
                            capture_output=True,
                            text=True
                        )
                        
                        if status_result.returncode == 0:
                            logger.info("Cloudflared服务运行正常")
                        else:
                            logger.warning("Cloudflared服务状态异常")
                        
                        return True
                except:
                    continue
            
            logger.warning("无法通过systemd重启服务，尝试直接重启进程...")
            
            # 尝试直接重启进程
            subprocess.run(['pkill', '-f', 'cloudflared'], timeout=10)
            time.sleep(1)
            
            # 尝试启动
            subprocess.run(['cloudflared', 'service', 'restart'], timeout=30)
            
            logger.info("尝试重启Cloudflared进程完成")
            return True
            
        except Exception as e:
            logger.error(f"重启Cloudflared失败: {e}")
            return False
    
    def send_notification(self, old_domain, new_domain, results):
        """发送通知"""
        if not self.config['notification']['enabled']:
            return
        
        notification_type = self.config['notification']['type']
        
        if notification_type == 'webhook' and self.config['notification']['webhook_url']:
            self.send_webhook_notification(old_domain, new_domain, results)
    
    def send_webhook_notification(self, old_domain, new_domain, results):
        """发送Webhook通知"""
        try:
            best_result = results[0] if results else {}
            
            message = {
                "text": "Cloudflared域名优选完成",
                "attachments": [{
                    "title": "优选结果",
                    "fields": [
                        {"title": "旧域名", "value": old_domain or "无", "short": True},
                        {"title": "新域名", "value": new_domain or "无", "short": True},
                        {"title": "延迟", "value": f"{best_result.get('avg_latency', 0):.1f}ms", "short": True},
                        {"title": "成功率", "value": f"{best_result.get('success_rate', 0):.1f}%", "short": True},
                        {"title": "分数", "value": f"{best_result.get('score', 0)}", "short": True},
                        {"title": "位置", "value": best_result.get('geo_info', {}).get('country', '未知'), "short": True}
                    ],
                    "color": "#36a64f" if best_result.get('score', 0) > 60 else "#ff0000",
                    "ts": int(time.time())
                }]
            }
            
            response = requests.post(
                self.config['notification']['webhook_url'],
                json=message,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info("通知发送成功")
            else:
                logger.warning(f"通知发送失败: {response.status_code}")
                
        except Exception as e:
            logger.error(f"发送通知失败: {e}")
    
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
                    # 简单提取域名
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
                
                # 发送通知
                self.send_notification(current_domain, best_domain, results)
                
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
        print(f"本地位置: {self.local_ip_info.get('city', 'Unknown')}, "
              f"{self.local_ip_info.get('region', 'Unknown')}, "
              f"{self.local_ip_info.get('country', 'Unknown')}")
        print("=" * 80)
        print(f"{'排名':<4} {'域名':<30} {'延迟(ms)':<10} {'速度(KB/s)':<12} {'成功率(%)':<10} {'分数':<8} {'位置':<15}")
        print("-" * 80)
        
        for i, result in enumerate(results[:15], 1):  # 显示前15个
            if result['score'] > 0:
                location = result.get('geo_info', {}).get('country', '未知')
                print(f"{i:<4} {result['domain']:<30} "
                      f"{result.get('avg_latency', 0):<10.1f} "
                      f"{result.get('avg_speed', 0):<12.1f} "
                      f"{result.get('success_rate', 0):<10.1f} "
                      f"{result.get('score', 0):<8.1f} "
                      f"{location:<15}")
            else:
                print(f"{i:<4} {result['domain']:<30} {'失败':<55}")
        
        print("=" * 80)
        
        # 显示最佳域名详情
        if results:
            best = results[0]
            print(f"\n🎉 推荐域名: {best['domain']}")
            print(f"   平均延迟: {best.get('avg_latency', 0):.1f}ms")
            print(f"   平均速度: {best.get('avg_speed', 0):.1f}KB/s")
            print(f"   成功率: {best.get('success_rate', 0):.1f}%")
            print(f"   综合分数: {best.get('score', 0):.1f}")
            if best.get('geo_info'):
                print(f"   地理位置: {best['geo_info'].get('city', '未知')}, {best['geo_info'].get('country', '未知')}")
            print(f"   IP地址: {', '.join(best.get('ips', []))}")

def install_dependencies():
    """安装依赖包"""
    print("正在安装依赖包...")
    
    dependencies = [
        'requests',
        'geoip2',
        'pyyaml'
    ]
    
    import importlib
    import subprocess
    import sys
    
    for package in dependencies:
        try:
            importlib.import_module(package.split('==')[0])
            print(f"✓ {package} 已安装")
        except ImportError:
            print(f"正在安装 {package}...")
            subprocess.check_call([sys.executable, '-m', 'pip', 'install', package])
            print(f"✓ {package} 安装完成")
    
    # 安装系统依赖
    system_deps = ['curl', 'ping', 'dig', 'bc']
    for dep in system_deps:
        try:
            subprocess.run(['which', dep], check=True, capture_output=True)
            print(f"✓ 系统命令 {dep} 可用")
        except:
            print(f"⚠ 系统命令 {dep} 未安装，部分功能可能受限")
    
    print("\n所有依赖安装完成！")

def main():
    """主函数"""
    # 检查是否安装依赖
    if len(sys.argv) > 1 and sys.argv[1] == '--install':
        install_dependencies()
        return
    
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
        logger.error(f"运行出错: {e}")
        print(f"\n❌ 发生错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()