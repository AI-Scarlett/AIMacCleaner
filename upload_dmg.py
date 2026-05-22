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

VERSION = "2.1.0"
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
    body_text = """## v2.1.0 国际化修复 + 图标重设计 + 布局优化

### 🌐 国际化修复
- 修复任务栏Agent监控硬编中文（OperationType.rawValue→localizedLabel）
- 修复适配检测/其它工具/依赖管理硬编中文（subCategory→localizedSubCategory）
- 修复IntelMigrationTab硬编中文（IntelAppType.rawValue→localizedLabel）
- 修复Models.swift confidenceLabel硬编中文
- 修复ScannerService.swift AI提示词硬编中文→英文
- 修复窗口标题匹配"Agent守护"→"Agent卫士"
- 新增localizedSubCategory/localizedConfidence/langToggleText到Localizer
- 新增flag/label属性到AppLanguage枚举
- 默认语言从中文改为英文

### 🎨 图标重设计
- 全新原创六边形哨兵之眼图标（不使用SF Symbols，无版权风险）
- 蓝紫渐变背景+青色虹膜+电路纹理
- 重新生成所有尺寸图标文件

### 📐 布局优化
- 任务栏弹窗宽度340→360pt
- Agent统计行名称宽度80→90pt，添加truncationMode
- 操作类型胶囊添加lineLimit+minimumScaleFactor防止换行
- 最近操作列表优化间距和截断
- 操作控制栏按钮添加minimumScaleFactor
- 硬件概览底部统计行添加lineLimit
- 设置语言选择器改为横向滚动+提取languageButton函数
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
