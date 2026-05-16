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

VERSION = "1.7.4"
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
    body_text = """## v1.7.3 修复

- **磁盘空间数据与系统设置不一致** - 使用 `URL.resourceValues` API + 十进制GB，数据与macOS系统设置完全一致
- **Agent监控无数据** - 移除per-event的lsof调用，改为批量lsof+缓存匹配架构
- **Agent监控假数据归因** - 重写进程识别，支持进程树追溯，过滤系统进程和Finder扩展
- **新增processName/toolInfo字段** - 显示真实操作进程名和命令行信息
- **存储分析扫描过慢** - 减少不可访问路径，扫描深度从8降到5
- **弹窗底部样式统一** - 版本号/网络状态/退出APP作为弹窗公共外壳
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
