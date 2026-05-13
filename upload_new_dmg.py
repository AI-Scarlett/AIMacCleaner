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

print("Getting release info...")
response = requests.get(
    'https://api.github.com/repos/AI-Scarlett/AIMacCleaner/releases/tags/v1.6.0',
    headers=headers
)
response.raise_for_status()
release_info = response.json()

for asset in release_info.get('assets', []):
    if asset['name'] == 'AIMacCleaner.dmg':
        print(f"Deleting old asset: {asset['id']}")
        delete_response = requests.delete(
            f'https://api.github.com/repos/AI-Scarlett/AIMacCleaner/releases/assets/{asset["id"]}',
            headers=headers
        )
        delete_response.raise_for_status()
        print("Old asset deleted")
        break

upload_url = release_info['upload_url'].replace('{?name,label}', '')
dmg_path = '/private/tmp/AIMacCleaner.dmg'
print(f"Uploading new {dmg_path}...")

with open(dmg_path, 'rb') as f:
    response = requests.post(
        f"{upload_url}?name=AIMacCleaner.dmg",
        headers={**headers, 'Content-Type': 'application/octet-stream'},
        data=f
    )
response.raise_for_status()
print("DMG uploaded successfully!")
print(f"Release URL: {release_info['html_url']}")
