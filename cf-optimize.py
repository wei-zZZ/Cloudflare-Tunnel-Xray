#!/usr/bin/env python3
"""
Cloudflared 域名优选脚本 - Python版
支持多线程测试和更多功能
"""

import sys
import time
import json
import subprocess
import threading
import concurrent.futures
from datetime import datetime
from pathlib import Path
import requests
import argparse

class CloudflaredOptimizer:
    def __init__(self, test_count=3, timeout=3, max_workers=10):
        self.test_count = test_count
        self.timeout = timeout
        self.max_workers = max_workers
        
        # 域名列表
        self.domains = [
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
        
        # 结果存储
        self.results_dir = Path("/opt/cloudflared-optimizer")
        self.results_dir.mkdir(parents=True, exist_ok=True)
        
        # 检查依赖
        self.check_dependencies()
    
    def check_dependencies(self):
        """检查必要的依赖"""
        required = ['curl', 'ping']
        missing = []
        
        for cmd in required:
            try:
                subprocess.run(['which', cmd], check=True, capture_output=True)
            except subprocess.CalledProcessError:
                missing.append(cmd)
        
        if missing:
            print(f"缺少依赖: {missing}")
            print("请安装: ", end="")
            if Path('/etc/debian_version').exists():
                print(f"sudo apt-get install {' '.join(missing)}")
            else:
                print(f"请手动安装 {' '.join(missing)}")
            sys.exit(1)
    
    def test_latency_curl(self, domain):
        """使用curl测试延迟"""
        try:
            start = time.time()
            response = requests.get(
                f'https://{domain}',
                timeout=self.timeout,
                headers={'User-Agent': 'Mozilla/5.0'}
            )
            if response.status_code < 400:
                return (time.time() - start) * 1000  # 毫秒
        except:
            pass
        return None
    
    def test_latency_ping(self, domain):
        """使用ping测试延迟"""
        try:
            result = subprocess.run(
                ['ping', '-c', '2', '-W', str(self.timeout), domain],
                capture_output=True,
                text=True,
                timeout=self.timeout + 2
            )
            
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'min/avg/max' in line:
                        stats = line.split('=')[1].split('/')
                        return float(stats[1])  # 平均延迟
        except:
            pass
        return None
    
    def test_domain(self, domain):
        """测试单个域名"""
        latencies = []
        success_count = 0
        
        for i in range(self.test_count):
            # 尝试curl
            latency = self.test_latency_curl(domain)
            
            # 如果curl失败，尝试ping
            if latency is None:
                latency = self.test_latency_ping(domain)
            
            if latency is not None:
                latencies.append(latency)
                success_count += 1
            
            # 避免请求过快
            time.sleep(0.2)
        
        result = {
            'domain': domain,
            'success_count': success_count,
            'total_tests': self.test_count,
            'latencies': latencies
        }
        
        if latencies:
            result['avg_latency'] = sum(latencies) / len(latencies)
            result['min_latency'] = min(latencies)
            result['max_latency'] = max(latencies)
            result['success_rate'] = (success_count / self.test_count) * 100
        else:
            result['avg_latency'] = 9999
            result['success_rate'] = 0
        
        return result
    
    def calculate_score(self, result):
        """计算域名评分"""
        if result['success_rate'] < 80:  # 成功率低于80%得0分
            return 0
        
        # 基础分：成功率
        score = result['success_rate']
        
        # 延迟加分
        latency = result['avg_latency']
        if latency < 50:
            score += 50
        elif latency < 100:
            score += 40
        elif latency < 200:
            score += 30
        elif latency < 300:
            score += 20
        else:
            score += 10
        
        return round(score, 2)
    
    def run_tests(self):
        """运行所有测试"""
        print(f"开始测试 {len(self.domains)} 个域名...")
        print(f"每个域名测试 {self.test_count} 次")
        print("=" * 60)
        
        results = []
        
        # 使用线程池并发测试
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            future_to_domain = {
                executor.submit(self.test_domain, domain): domain
                for domain in self.domains
            }
            
            for i, future in enumerate(concurrent.futures.as_completed(future_to_domain), 1):
                domain = future_to_domain[future]
                try:
                    result = future.result(timeout=self.timeout * self.test_count + 5)
                    results.append(result)
                    
                    if result['success_rate'] > 0:
                        print(f"[{i}/{len(self.domains)}] {domain}: "
                              f"{result['avg_latency']:.1f}ms, "
                              f"{result['success_rate']:.1f}%")
                    else:
                        print(f"[{i}/{len(self.domains)}] {domain}: 测试失败")
                        
                except Exception as e:
                    print(f"[{i}/{len(self.domains)}] {domain}: 错误 - {e}")
        
        # 计算评分并排序
        for result in results:
            result['score'] = self.calculate_score(result)
        
        results.sort(key=lambda x: x['score'], reverse=True)
        
        return results
    
    def display_results(self, results):
        """显示测试结果"""
        print("\n" + "=" * 80)
        print("Cloudflared 域名优选测试结果")
        print(f"测试时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80)
        print(f"{'排名':<4} {'域名':<30} {'延迟(ms)':<10} {'成功率(%)':<10} {'分数':<8}")
        print("-" * 80)
        
        for i, result in enumerate(results[:10], 1):
            if result['score'] > 0:
                print(f"{i:<4} {result['domain']:<30} "
                      f"{result['avg_latency']:<10.1f} "
                      f"{result['success_rate']:<10.1f} "
                      f"{result['score']:<8.1f}")
            else:
                print(f"{i:<4} {result['domain']:<30} {'测试失败':<28}")
        
        print("=" * 80)
        
        if results and results[0]['score'] > 0:
            best = results[0]
            print(f"\n🎉 推荐域名: {best['domain']}")
            print(f"   平均延迟: {best['avg_latency']:.1f}ms")
            print(f"   成功率: {best['success_rate']:.1f}%")
            print(f"   综合分数: {best['score']:.1f}")
            
            # 保存结果
            self.save_results(best, results)
            
            return best['domain']
        
        return None
    
    def save_results(self, best_result, all_results):
        """保存测试结果"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        # 保存最佳域名
        best_file = self.results_dir / "best-domain.txt"
        best_file.write_text(best_result['domain'])
        
        # 保存详细结果
        detailed_result = {
            'timestamp': datetime.now().isoformat(),
            'best_domain': best_result,
            'all_results': all_results
        }
        
        result_file = self.results_dir / f"result_{timestamp}.json"
        with open(result_file, 'w', encoding='utf-8') as f:
            json.dump(detailed_result, f, indent=2, ensure_ascii=False)
        
        latest_file = self.results_dir / "latest.json"
        latest_file.write_text(json.dumps(detailed_result, indent=2, ensure_ascii=False))
        
        print(f"\n📊 结果已保存到: {self.results_dir}")
    
    def update_config(self, domain, auto_update=False):
        """更新cloudflared配置"""
        config_files = [
            Path("/etc/cloudflared/config.yml"),
            Path("/root/.cloudflared/config.yml"),
            Path.home() / ".cloudflared/config.yml"
        ]
        
        config_file = None
        for cf in config_files:
            if cf.exists():
                config_file = cf
                break
        
        if not config_file:
            print(f"\n⚠ 未找到cloudflared配置文件")
            print(f"请手动设置DNS上游为: https://{domain}/dns-query")
            return False
        
        print(f"\n找到配置文件: {config_file}")
        
        # 备份原配置
        backup_file = config_file.with_suffix(f".bak.{datetime.now().strftime('%Y%m%d_%H%M%S')}")
        import shutil
        shutil.copy2(config_file, backup_file)
        print(f"配置已备份到: {backup_file}")
        
        # 读取和更新配置
        try:
            content = config_file.read_text(encoding='utf-8')
            
            # 更新DNS上游配置
            import re
            new_content = re.sub(
                r'https://[^/]+/dns-query',
                f'https://{domain}/dns-query',
                content
            )
            
            # 如果没有找到，则添加
            if new_content == content:
                if 'proxy-dns-upstream:' in content:
                    lines = content.split('\n')
                    for i, line in enumerate(lines):
                        if 'proxy-dns-upstream:' in line:
                            lines.insert(i + 1, f'  - https://{domain}/dns-query')
                            new_content = '\n'.join(lines)
                            break
                else:
                    new_content = content.rstrip() + f'\nproxy-dns-upstream:\n  - https://{domain}/dns-query\n'
            
            config_file.write_text(new_content, encoding='utf-8')
            print(f"✅ 配置已更新为使用域名: {domain}")
            
            # 重启服务
            if auto_update or input("是否重启cloudflared服务？[y/N]: ").lower() == 'y':
                self.restart_cloudflared()
            
            return True
            
        except Exception as e:
            print(f"❌ 更新配置失败: {e}")
            return False
    
    def restart_cloudflared(self):
        """重启cloudflared服务"""
        try:
            result = subprocess.run(
                ['systemctl', 'restart', 'cloudflared'],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                print("✅ cloudflared服务已重启")
                
                # 检查状态
                time.sleep(2)
                status_result = subprocess.run(
                    ['systemctl', 'status', 'cloudflared'],
                    capture_output=True,
                    text=True
                )
                
                if status_result.returncode == 0:
                    print("✅ cloudflared运行正常")
                else:
                    print("⚠ cloudflared状态异常")
                
                return True
            else:
                print(f"❌ 重启失败: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"❌ 重启失败: {e}")
            return False

def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='Cloudflared域名优选脚本')
    parser.add_argument('-c', '--count', type=int, default=3, help='测试次数，默认3次')
    parser.add_argument('-t', '--timeout', type=int, default=3, help='超时时间，默认3秒')
    parser.add_argument('-w', '--workers', type=int, default=10, help='最大线程数，默认10')
    parser.add_argument('--test-only', action='store_true', help='仅测试，不更新配置')
    parser.add_argument('--auto-update', action='store_true', help='测试后自动更新配置')
    parser.add_argument('--list', action='store_true', help='显示域名列表')
    
    args = parser.parse_args()
    
    if args.list:
        print("Cloudflare域名列表:")
        for domain in [
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
        ]:
            print(f"  {domain}")
        return
    
    print("=" * 60)
    print("Cloudflared 域名优选系统")
    print("=" * 60)
    
    optimizer = CloudflaredOptimizer(
        test_count=args.count,
        timeout=args.timeout,
        max_workers=args.workers
    )
    
    try:
        # 运行测试
        results = optimizer.run_tests()
        
        # 显示结果
        best_domain = optimizer.display_results(results)
        
        if best_domain:
            if not args.test_only:
                if args.auto_update:
                    optimizer.update_config(best_domain, auto_update=True)
                else:
                    choice = input("\n是否更新cloudflared配置？[Y/n]: ").strip().lower()
                    if choice in ['y', 'yes', '']:
                        optimizer.update_config(best_domain)
        
        print("\n✅ 完成！")
        
    except KeyboardInterrupt:
        print("\n\n⚠ 测试被用户中断")
        sys.exit(130)
    except Exception as e:
        print(f"\n❌ 发生错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()