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

VERSION = "1.7.8"
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
    body_text = """## v1.7.8 Agent 审计大升级

### 🛡️ 新增 Agent 审计功能
- **50+ 种 AI Agent 内置支持**：自动发现本机 Agent 会话数据，审计其对本地文件的操作记录
- **多种存储格式解析**：JSONL、SQLite (state.vscdb)、JSON (file-changes)、MD、数据库

### 新增 Agent 支持
- **OpenClaw** - 专用解析器，解析 `~/.openclaw/agents/` 下 JSONL 会话中的 tool_use/tool_call 操作
- **Hermes** - 双解析器，解析 `~/.hermes/sessions/` 下 JSON 会话 + SQLite state.db
- **CrewAI** - SQLite 解析，自动发现 `~/Library/Application Support/CrewAI/` 下的表结构
- **AutoGen** - SQLite 解析，解析 `~/.autogenstudio/` 下的 session/message/conversation 表
- **OpenHands** - JSON 事件解析，解析轨迹文件中的 action/tool 事件
- **Dify / MetaGPT / CAMEL / DeerFlow / Huginn / BrowserUse** - 通用 JSONL 解析
- 同时在 `knownDirs` 中新增 AgentGPT、LobeHub、LangGraph、Swarm、AgentScope、UI-TARS 路径注册

### 修复
- **修复 Trae/CodeBuddy 审计无记录** - VSCode 类 Agent 智能分发解析器，根据文件扩展名自动调用 parseVscdbSQLite / parseFileChangesJSON / parseGenericJSONL
- **修复内置 Agent 可被重复添加** - 内置 Agent 在添加列表中禁用按钮
- **修复菜单栏退出按钮导致应用卡死** - 先关闭所有窗口再延迟 terminate
- **修复 Kimi 无法获取会话记录** - 添加 `~/.kimi/sessions` 和 `~/.kimi/user-history` 精确路径

### 改进
- **文件发现增强** - `findSessionFiles` 现在支持 .db、.sqlite 文件和包含 session/events/conversation/trajectory 的 JSON 文件
- **VSCode 类 Agent 智能解析器** - 自动根据文件类型分发到正确的解析方法
- **UI 更新** - 所有新增 Agent 均有专属 SF Symbol 图标和颜色
- **通用自动发现优化** - 已注册的 Agent 跳过，避免重复注册
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
