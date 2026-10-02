"""Small real Claude Code calls, with sanitized outgoing request metadata."""

import concurrent.futures
import http.server
import json
import os
from pathlib import Path
import shlex
import subprocess
import threading
import urllib.error
import urllib.request

ROOT = Path('/data/swepmv2-harbor-runtime')
MODELS = ['deepseek-v4-flash-siflow', 'qwen3.8-max-qiniu',
          'glm-5.3-siflow', 'kimi-k3-qiniu']
BINARY = ROOT / 'tools/claude-code/2.1.140/linux-x64/claude'
OUT = ROOT / 'campaigns/v2-0930-max300-nomcp/preflight'


def main():
    credentials = {}
    for line in (ROOT / '.env.deepseek-v4-flash-siflow').read_text().splitlines():
        parts = shlex.split(line.removeprefix('export '), comments=True)
        if len(parts) == 1 and '=' in parts[0]:
            key, value = parts[0].split('=', 1)
            credentials[key] = value
    base = credentials['ANTHROPIC_BASE_URL'].rstrip('/')
    token = credentials['ANTHROPIC_AUTH_TOKEN']
    OUT.mkdir(parents=True, exist_ok=True)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    events = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            data = json.loads(body)
            event = {
                'path': self.path, 'model': data.get('model'),
                'thinking': data.get('thinking'),
                'output_config': data.get('output_config'),
                'max_tokens': data.get('max_tokens'),
                'tool_names': [t.get('name') for t in data.get('tools', [])],
            }
            events.append(event)
            headers = {k: v for k, v in self.headers.items()
                       if k.lower() not in {'host', 'content-length', 'connection',
                                            'authorization', 'x-api-key'}}
            headers['Authorization'] = 'Bearer ' + token
            request = urllib.request.Request(base + self.path, data=body, headers=headers)
            try:
                response = opener.open(request, timeout=180)
            except urllib.error.HTTPError as exc:
                response = exc
            except Exception as exc:
                event['error'] = type(exc).__name__
                self.send_error(502)
                return
            with response:
                event['status'] = response.status
                self.send_response(response.status)
                self.send_header('Content-Type', response.headers.get('Content-Type', 'application/json'))
                self.send_header('Connection', 'close')
                self.end_headers()
                try:
                    while chunk := response.read1(65536):
                        self.wfile.write(chunk)
                        self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    event['client_disconnected'] = True
            self.close_connection = True

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    def probe(model):
        target = OUT / model
        target.mkdir(exist_ok=True)
        env = dict(os.environ)
        for name in ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy',
                     'ANTHROPIC_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN']:
            env.pop(name, None)
        env.update({
            'ANTHROPIC_BASE_URL': f'http://127.0.0.1:{server.server_port}',
            'ANTHROPIC_AUTH_TOKEN': token, 'ANTHROPIC_MODEL': model,
            'ANTHROPIC_DEFAULT_OPUS_MODEL': model, 'ANTHROPIC_DEFAULT_SONNET_MODEL': model,
            'ANTHROPIC_DEFAULT_HAIKU_MODEL': model, 'CLAUDE_CODE_SUBAGENT_MODEL': model,
            'CLAUDE_CONFIG_DIR': str(target / 'config'), 'XDG_CACHE_HOME': str(target / 'cache'),
            'TMPDIR': str(target / 'tmp'), 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1',
            'DISABLE_AUTOUPDATER': '1', 'IS_SANDBOX': '1',
            'CLAUDE_CODE_EFFORT_LEVEL': 'max',
        })
        (target / 'tmp').mkdir(exist_ok=True)
        cmd = [str(BINARY), '--print', '--verbose', '--output-format', 'stream-json',
               '--model', model, '--effort', 'max', '--max-turns', '3',
               '--permission-mode', 'bypassPermissions', '--strict-mcp-config',
               '--mcp-config', '{"mcpServers":{}}', '--disallowedTools', 'mcp__*',
               '--settings', '{"alwaysThinkingEnabled":true}',
               'Use Bash once to run printf SWEPM_PREFLIGHT_OK. Then reply exactly SWEPM_PREFLIGHT_OK. Do not read or modify any files.']
        with (target / 'claude-code.txt').open('w') as log:
            try:
                result = subprocess.run(cmd, env=env, cwd=target, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=240)
                status = {'model': model, 'exit_code': result.returncode}
            except subprocess.TimeoutExpired:
                status = {'model': model, 'timeout': True}
        parsed = []
        for line in (target / 'claude-code.txt').read_text().splitlines():
            try:
                parsed.append(json.loads(line))
            except json.JSONDecodeError:
                pass
        status['init'] = [{k: e.get(k) for k in ['model', 'mcp_servers', 'claude_code_version']}
                          for e in parsed if e.get('type') == 'system' and e.get('subtype') == 'init']
        status['result'] = [{k: e.get(k) for k in ['subtype', 'is_error', 'num_turns', 'result']}
                            for e in parsed if e.get('type') == 'result']
        status['requests'] = [e for e in events if e.get('model') == model]
        (target / 'summary.json').write_text(json.dumps(status, indent=2) + '\n')
        print(json.dumps(status), flush=True)
        return status

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        statuses = list(executor.map(probe, MODELS))
    server.shutdown()
    (OUT / 'summary.json').write_text(json.dumps(statuses, indent=2) + '\n')


if __name__ == '__main__':
    main()
