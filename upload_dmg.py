import subprocess
import requests
import json

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

VERSION = "2.1.2"
DMG_PATH = f"/tmp/AgentGuard-v{VERSION}-arm64.dmg"
REPO = "AI-Scarlett/AIMacCleaner"
TAG = f"v{VERSION}"

token = get_github_token()
headers = {'Authorization': f'token {token}'}

print(f"Checking for existing release {TAG}...")
response = requests.get(
    f'https://api.github.com/repos/{REPO}/releases/tags/{TAG}',
    headers=headers
)

if response.status_code == 200:
    release_info = response.json()
    release_id = release_info['id']
    print(f"Release {TAG} already exists (id={release_id})")
else:
    print(f"Creating new release {TAG}...")
    body_text = """## v2.1.1 Agent守护模块 + UI重构 + 多语言下拉 + 图标重设计

### 🛡️ Agent 守护模块（全新）
- **批量操作预警**：短时间内大量删除/修改文件自动告警（阈值可调）
- **敏感文件识别**：检测 .env、私钥、证书、凭证等敏感文件被 Agent 访问
- **敏感内容检测**：扫描文件内容中的 API Key、Token、密码等敏感模式（19种规则）
- **保护目录设置**：标记受保护目录，Agent 访问时触发告警
- **系统通知**：macOS 原生通知推送，严重告警使用 Critical Sound
- **告警规则配置**：批量阈值、时间窗口、冷却时间、各检测开关均可调
- **免打扰时段**：支持跨午夜时段（如 23:00-07:00）
- **日志导出**：支持 CSV/JSON 格式导出操作记录和告警记录
- **审计报告**：一键生成 Agent 分布、操作类型分布、最受影响路径等报告
- **历史趋势图**：Swift Charts 柱状图展示最近 48 小时操作趋势

### 🎨 UI 重构
- **侧边栏重构**：核心功能（Agent监控+守护）+ 工具箱折叠子项
- **侧边栏底部精简**：移除多余文字仅保留图标，hover 显示 tooltip
- **图表尺寸统一**：StatCard 固定 minHeight、趋势图 min/max 约束
- **文字换行修复**：告警标题/消息/详情/路径添加 lineLimit + truncationMode

### 🌐 多语言下拉
- 语言切换从按钮改为下拉框，支持全部 6 种语言（中/英/繁/日/韩/马耳他）

### 🔔 图标重设计
- 替换所有 shield 图标为 eye 系列图标，避免版权风险
- 品牌重命名：AgentGuard → AgentWatch，Agent卫士 → Agent守望
"""
    create_response = requests.post(
        f'https://api.github.com/repos/{REPO}/releases',
        headers={**headers, 'Content-Type': 'application/json'},
        data=json.dumps({
            'tag_name': TAG,
            'name': f'AIMacCleaner {TAG}',
            'body': body_text,
            'draft': False,
            'prerelease': False
        })
    )
    create_response.raise_for_status()
    release_info = create_response.json()
    release_id = release_info['id']
    print(f"Release {TAG} created successfully!")

# Delete existing assets for this release
print("Checking for existing assets...")
assets_response = requests.get(
    f'https://api.github.com/repos/{REPO}/releases/{release_id}/assets',
    headers=headers
)
for asset in assets_response.json():
    print(f"Deleting old asset: {asset['name']}")
    delete_response = requests.delete(
        f'https://api.github.com/repos/{REPO}/releases/assets/{asset["id"]}',
        headers=headers
    )
    delete_response.raise_for_status()

# Upload DMG
upload_url = release_info['upload_url'].replace('{?name,label}', '')
print(f"Uploading DMG: {DMG_PATH}...")

with open(DMG_PATH, 'rb') as f:
    response = requests.post(
        f"{upload_url}?name=AgentGuard-{TAG}-arm64.dmg",
        headers={**headers, 'Content-Type': 'application/octet-stream'},
        data=f
    )
response.raise_for_status()
print("DMG uploaded successfully!")

# Also upload the source code as a zip
import zipfile
import os
import tempfile

print("Creating source code zip...")
zip_path = f"/tmp/AgentGuard-{TAG}-source.zip"
source_dir = "/Users/zhouxiaoming/Downloads/MacCleaner"

with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
    for root, dirs, files in os.walk(source_dir):
        if '.git' in root or 'DerivedData' in root or 'build' in root:
            continue
        for file in files:
            file_path = os.path.join(root, file)
            arcname = os.path.relpath(file_path, source_dir)
            zipf.write(file_path, arcname)

print(f"Uploading source code zip: {zip_path}...")
with open(zip_path, 'rb') as f:
    response = requests.post(
        f"{upload_url}?name=AgentGuard-{TAG}-source.zip",
        headers={**headers, 'Content-Type': 'application/zip'},
        data=f
    )
response.raise_for_status()
print("Source code zip uploaded successfully!")

print(f"\nRelease URL: {release_info['html_url']}")
print("Done!")
