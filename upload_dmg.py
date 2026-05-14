import subprocess
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

print("Getting release info...")
response = requests.get(
    'https://api.github.com/repos/AI-Scarlett/AIMacCleaner/releases/tags/v1.6.0',
    headers=headers
)
response.raise_for_status()
release_info = response.json()

# Delete existing assets
for asset in release_info.get('assets', []):
    print(f"Deleting old asset: {asset['name']}")
    delete_response = requests.delete(
        f'https://api.github.com/repos/AI-Scarlett/AIMacCleaner/releases/assets/{asset["id"]}',
        headers=headers
    )
    delete_response.raise_for_status()

upload_url = release_info['upload_url'].replace('{?name,label}', '')
dmg_path = '/Users/zhouxiaoming/Downloads/MacCleaner/dist/AIMacCleaner-v1.6.0-arm64.dmg'
print(f"Uploading new DMG: {dmg_path}...")

with open(dmg_path, 'rb') as f:
    response = requests.post(
        f"{upload_url}?name=AIMacCleaner-v1.6.0-arm64.dmg",
        headers={**headers, 'Content-Type': 'application/octet-stream'},
        data=f
    )
response.raise_for_status()
print("DMG uploaded successfully!")
print(f"Release URL: {release_info['html_url']}")
