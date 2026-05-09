import json
import base64
import re
import urllib.request

SERVICES = ['auth-service', 'core-service', 'media-service', 'frontend']


def github_api(url, token, data=None):
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
        'User-Agent': 'detailsnap-deploy-lambda',
    }
    body = json.dumps(data).encode() if data else None
    method = 'PUT' if body else 'GET'
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def lambda_handler(event, context):
    image_tag = event['image_tag']
    github_token = event['github_token']
    repo = event.get('repo', 'theolecuyer/detailsnap-web-infra')
    branch = event.get('branch', 'main')

    for service in SERVICES:
        path = f"k8s/overlays/qa/{service}/kustomization.yaml"
        api_url = f"https://api.github.com/repos/{repo}/contents/{path}"

        file_data = github_api(api_url, github_token)
        file_sha = file_data['sha']
        content = base64.b64decode(file_data['content']).decode()

        new_content = re.sub(r'newTag: .*', f'newTag: {image_tag}', content)

        github_api(api_url, github_token, data={
            'message': f'chore: deploy {image_tag} to QA [skip ci]',
            'content': base64.b64encode(new_content.encode()).decode(),
            'sha': file_sha,
            'branch': branch,
        })

        print(f"Updated {service} -> {image_tag}")

    return {'success': True, 'deployed_tag': image_tag}
