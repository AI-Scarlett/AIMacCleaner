import subprocess
import json
import requests

def get_github_token():
    result = subprocess.run(
        ['git', 'credential', 'fill'],
        input=b'protocol=https\nhost=github.com\n',
        capture_output=True
    )
    for line in result.stdout.decode().splitlines():
        if line.startswith('password='):
            return line.split('=', 1)[1]
    return None

token = get_github_token()
headers = {'Authorization': f'token {token}'}

print("Creating release v1.6.0...")
release_data = {
    "tag_name": "v1.6.0",
    "name": "v1.6.0 - 硬件监控功能",
    "body": "## 更新内容\n\n### 新增\n- **硬件监控** - 菜单栏监控 Tab 新增硬件监控区域，实时显示系统状态\n- **CPU 使用率** - 实时显示 CPU 使用百分比和核心数，颜色随负载变化\n- **内存使用** - 显示内存压力百分比和已用/总量(GB)，含进度条\n- **CPU 温度** - 通过 AppleSMC/IORegistry 读取 CPU 温度\n- **电池状态** - 显示电池百分比、充电状态和剩余时间\n- **网络速率** - 实时计算并显示上传/下载速率\n- **系统信息** - 显示进程数、线程数、系统运行时间\n- **3秒刷新** - 硬件数据每 3 秒自动刷新",
    "prerelease": False
}
response = requests.post(
    'https://api.github.com/repos/AI-Scarlett/AIMacCleaner/releases',
    headers=headers,
    json=release_data
)
response.raise_for_status()
release_info = response.json()
print(f"Release created: {release_info['html_url']}")

upload_url = release_info['upload_url'].replace('{?name,label}', '')
dmg_path = 'dist/AIMacCleaner.dmg'
print(f"Uploading {dmg_path}...")

with open(dmg_path, 'rb') as f:
    response = requests.post(
        f"{upload_url}?name=AIMacCleaner.dmg",
        headers={**headers, 'Content-Type': 'application/octet-stream'},
        data=f
    )
response.raise_for_status()
print("DMG uploaded successfully!")
print(f"Release URL: {release_info['html_url']}")
