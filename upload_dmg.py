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

VERSION = "1.6.3"
DMG_PATH = f"/tmp/AIMacCleaner-v{VERSION}-arm64.dmg"
REPO = "AI-Scarlett/AIMacCleaner"
TAG = f"v{VERSION}"

token = get_github_token()
headers = {'Authorization': f'token {token}'}

# Check if tag/release already exists
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
    # Create new release
    print(f"Creating new release {TAG}...")
    body_text = """## 新功能

- **设置页整合** - 将 AI 设置、功能开关、监控设置、版本更新检测整合到统一的设置页面
- **功能开关** - 菜单栏监控、设备监控、操作记录均可在设置中一键开关
- **监控设置** - 存储警告阈值可调、回收站删除模式开关
- **版本检测** - 设置页内置版本更新检测功能，显示当前版本号
- **全盘扫描** - 存储分析全面升级，扫描整个磁盘包括系统文件、应用程序、应用数据、文稿、Agent、依赖、日志缓存等
- **目录复制** - 存储分析文件列表新增"目录"列，显示完整路径，点击复制按钮可直接复制路径
- **应用数据分类** - 存储分析新增"应用数据"和"日志与缓存"分类

## 修复

- 修复闪退问题：安全处理网络接口遍历和文件句柄关闭操作
- 修复权限持久化：添加系统权限描述，重启后无需重新授权
- 修复存储分析不准确：扫描范围从用户目录扩展到整个磁盘
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
        f"{upload_url}?name=AIMacCleaner-{TAG}-arm64.dmg",
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
zip_path = f"/tmp/AIMacCleaner-{TAG}-source.zip"
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
        f"{upload_url}?name=AIMacCleaner-{TAG}-source.zip",
        headers={**headers, 'Content-Type': 'application/zip'},
        data=f
    )
response.raise_for_status()
print("Source code zip uploaded successfully!")

print(f"\nRelease URL: {release_info['html_url']}")
print("Done!")
