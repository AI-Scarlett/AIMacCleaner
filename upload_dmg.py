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

VERSION = "1.8.0"
DMG_PATH = f"/tmp/AIMacCleaner-v{VERSION}-arm64.dmg"
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
    body_text = """## v1.8.0 芯片迁移功能

### 🆕 新功能：芯片迁移 (Intel → Apple Silicon)
- **新增「芯片迁移」Tab页** - 一键扫描本机所有 Intel 架构的应用、CLI工具、Homebrew包
- **架构检测** - 使用 `lipo -info` 和 `file` 命令精确识别 x86_64/ARM64/Universal 二进制
- **Intel 应用扫描** - 扫描 /Applications 和 ~/Applications 下所有 .app 的架构
- **CLI 工具扫描** - 扫描 /usr/local/bin、/opt/homebrew/bin、~/.cargo/bin、~/go/bin 等
- **Homebrew Intel 包检测** - 识别 /usr/local/Cellar 下的 Intel Homebrew 包
- **Rosetta 进程检测** - 检测正在通过 Rosetta 转译运行的进程
- **搜索 ARM 替代** - 联网搜索 ARM 版本下载链接（Google搜索/Mac App Store/brew install）
- **一键卸载 Intel 版本** - 支持 .app 移入回收站、CLI 直接删除、brew uninstall
- **一键重装 ARM 版本** - Homebrew 包支持 `brew install` 重装 ARM 版本
- **统计面板** - Intel 应用数量、通用二进制数量、ARM 原生数量、可释放空间

### 数据模型
- `IntelAppInfo` - 含 BinaryArchitecture (x86_64/arm64/universal/rosetta/unknown) 和 IntelAppType (app/cli/homebrew/framework)

### 修复 (来自 v1.7.9)
- 修复自定义Agent无法审计
- 修复Trae审计结果目标路径为空
- 修复未扫描出其他内置Agent
- 修复退出并更新流程无效
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
