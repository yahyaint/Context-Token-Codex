# SPDX-License-Identifier: MIT
"""Private integration test: installed Codex engine, isolated home, local fake provider.

No real chats, account settings, credentials, or model quota are used.
"""
import argparse, json, pathlib, queue, subprocess, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

parser = argparse.ArgumentParser()
parser.add_argument('--exe', required=True)
parser.add_argument('--report', required=True)
parser.add_argument('--model', default='gpt-6.1-sol')
parser.add_argument('--cache', default=str(pathlib.Path.home() / '.codex/models_cache.json'))
args = parser.parse_args()
root = pathlib.Path(tempfile.mkdtemp(prefix='ctc-native-limits-'))
home = root / 'home'; home.mkdir()
project = root / 'project'; project.mkdir()
subprocess.run(['git', 'init', '--quiet', str(project)], check=True, creationflags=0x08000000)
(project / '.codex').mkdir(); child = project / 'src'; child.mkdir()
cache = json.loads(pathlib.Path(args.cache).read_text(encoding='utf-8-sig'))
model = next(m for m in cache['models'] if m['slug'] == args.model)
model['prefer_websockets'] = False
catalog = home / 'models.json'
catalog.write_text(json.dumps({'models': [model]}), encoding='utf-8')
calls = []
class FakeProvider(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
        calls.append({'path': self.path, 'model': body.get('model')})
        response = {'id': 'resp_fixture', 'object': 'response', 'status': 'completed',
                    'output': [{'id': 'msg_fixture', 'type': 'message', 'role': 'assistant',
                                'content': [{'type': 'output_text', 'text': 'OK', 'annotations': []}]}],
                    'usage': {'input_tokens': 100, 'output_tokens': 1, 'total_tokens': 101,
                              'input_tokens_details': {'cached_tokens': 0},
                              'output_tokens_details': {'reasoning_tokens': 0}}}
        events = [
            {'type': 'response.created', 'response': {**response, 'status': 'in_progress', 'output': []}},
            {'type': 'response.output_item.added', 'output_index': 0, 'item': {**response['output'][0], 'content': []}},
            {'type': 'response.output_text.delta', 'item_id': 'msg_fixture', 'output_index': 0, 'content_index': 0, 'delta': 'OK'},
            {'type': 'response.output_item.done', 'output_index': 0, 'item': response['output'][0]},
            {'type': 'response.completed', 'response': response},
        ]
        data = ''.join('event: '+e['type']+'\ndata: '+json.dumps(e)+'\n\n' for e in events).encode()
        self.send_response(200); self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
server = ThreadingHTTPServer(('127.0.0.1', 0), FakeProvider)
threading.Thread(target=server.serve_forever, daemon=True).start()
def configuration(global_window=None):
    text = ('model = '+json.dumps(args.model)+'\nmodel_provider = "ctc-fixture"\n'
            + 'model_catalog_json = '+json.dumps(str(catalog))+'\n'
            + (f'model_context_window = {global_window}\n' if global_window else '')
            + 'disable_response_storage = true\n'
            + '[model_providers.ctc-fixture]\nname = "CTC local test"\nwire_api = "responses"\n'
            + f'base_url = "http://127.0.0.1:{server.server_port}/v1"\nrequires_openai_auth = false\n'
            + '[projects.'+json.dumps(str(project))+']\ntrust_level = "trusted"\n')
    (home / 'config.toml').write_text(text, encoding='utf-8')
configuration()
config = project / '.codex/config.toml'
config.write_text('model_context_window = 544000\n', encoding='utf-8')
results = []
def usable(window):
    return min(window, model['max_context_window']) * model['effective_context_window_percent'] // 100
class Engine:
    def __init__(self):
        import os
        env = {**os.environ, 'CODEX_HOME': str(home), 'CODEX_SQLITE_HOME': str(home)}
        self.p = subprocess.Popen([args.exe, 'app-server'], cwd=project, env=env,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, encoding='utf-8', creationflags=0x08000000)
        self.q = queue.Queue(); self.notes = []; self.errors = []; self.counter = 0
        def reader():
            for line in self.p.stdout:
                try: self.q.put(json.loads(line))
                except ValueError: pass
        def errreader():
            for line in self.p.stderr: self.errors.append(line.rstrip())
        threading.Thread(target=reader, daemon=True).start()
        threading.Thread(target=errreader, daemon=True).start()
        self.rpc('initialize', {'clientInfo': {'name': 'ctc-native-limit-test', 'version': '1'},
                                'capabilities': {'experimentalApi': True}})
        self.send({'method': 'initialized', 'params': {}})
    def send(self, message):
        self.p.stdin.write(json.dumps(message)+'\n'); self.p.stdin.flush()
    def rpc(self, method, params):
        self.counter += 1; ident = self.counter
        self.send({'id': ident, 'method': method, 'params': params})
        deadline = time.monotonic()+45
        while time.monotonic() < deadline:
            r = self.q.get(timeout=max(.01, deadline-time.monotonic()))
            if r.get('id') == ident:
                if 'error' in r: raise RuntimeError(f'{method}: {r["error"]}')
                return r['result']
            self.notes.append(r)
        raise RuntimeError(method+' timed out')
    def turn(self, ident):
        self.notes.clear()
        r = self.rpc('turn/start', {'threadId': ident, 'input': [{'type': 'text', 'text': 'Reply OK. Use no tools.', 'text_elements': []}]})
        deadline = time.monotonic()+45
        while time.monotonic() < deadline:
            n = self.q.get(timeout=max(.01, deadline-time.monotonic())); self.notes.append(n)
            if n.get('method') == 'turn/completed':
                if n['params']['turn']['status'] != 'completed': raise RuntimeError(json.dumps(n))
                break
        windows = []
        for note in self.notes:
            params = note.get('params', {})
            w = params.get('tokenUsage', {}).get('modelContextWindow')
            if w is None: w = params.get('msg', {}).get('model_context_window')
            if w is not None: windows.append(w)
        if not windows: raise RuntimeError('No runtime capacity was recorded: '+str([n.get('method') for n in self.notes]))
        return windows[-1]
    def close(self):
        self.p.stdin.close()
        try: self.p.wait(timeout=2)
        except subprocess.TimeoutExpired: self.p.kill(); self.p.wait()
engines = []
try:
    e = Engine(); engines.append(e)
    def check(name, actual, expected):
        results.append({'case': name, 'actual': actual, 'expected': expected, 'passed': actual == expected})
    read = e.rpc('config/read', {'cwd': str(project), 'includeLayers': True})
    check('Native project configuration reads saved 544k', read['config'].get('model_context_window'), 544000)
    check('Nested cwd inherits project limit', e.rpc('config/read', {'cwd': str(child)})['config'].get('model_context_window'), 544000)
    t = e.rpc('thread/start', {'cwd': str(project), 'experimentalRawEvents': True})['thread']['id']
    check('Fresh chat records effective 544k window', e.turn(t), usable(544000))
    config.write_text('model_context_window = 800000\nmodel_auto_compact_token_limit = 720000\n', encoding='utf-8')
    check('Running chat retains old window after file edit', e.turn(t), usable(544000))
    check('Native reread sees edited window', e.rpc('config/read', {'cwd': str(project)})['config'].get('model_context_window'), 800000)
    check('Native reread sees edited compaction threshold', e.rpc('config/read', {'cwd': str(project)})['config'].get('model_auto_compact_token_limit'), 720000)
    # Start and resume must use new configuration. Use only fixture chats and home.
    t2 = e.rpc('thread/start', {'cwd': str(project), 'experimentalRawEvents': True})['thread']['id']
    check('New chat uses edited project window', e.turn(t2), usable(800000))
    e.close(); engines.remove(e); e = Engine(); engines.append(e)
    resumed = e.rpc('thread/resume', {'threadId': t, 'cwd': str(project)})['thread']['id']
    check('Fresh engine resumes saved chat with edited window', e.turn(resumed), usable(800000))
    t3 = e.rpc('thread/start', {'cwd': str(project), 'config': {'model_context_window': 400000}, 'experimentalRawEvents': True})['thread']['id']
    check('Per-chat native override takes precedence', e.turn(t3), usable(400000))
    config.write_text('model_context_window = 1200000\n', encoding='utf-8')
    t4 = e.rpc('thread/start', {'cwd': str(project), 'experimentalRawEvents': True})['thread']['id']
    check('Native catalog caps oversized window', e.turn(t4), int(model['max_context_window']*model['effective_context_window_percent']//100))
    config.write_text('', encoding='utf-8'); configuration(300000)
    t5 = e.rpc('thread/start', {'cwd': str(project), 'experimentalRawEvents': True})['thread']['id']
    check('Removing project override restores global window', e.turn(t5), usable(300000))
    configuration()
    t6 = e.rpc('thread/start', {'cwd': str(project), 'experimentalRawEvents': True})['thread']['id']
    check('Removing global override restores model default', e.turn(t6), int(model['context_window']*model['effective_context_window_percent']//100))
except Exception as ex:
    results.append({'case': 'Native test infrastructure', 'passed': False, 'error': str(ex),
                    'stderr': engines[-1].errors[-6:] if engines else []})
finally:
    for e in engines: e.close()
    server.shutdown()
    version = subprocess.check_output([args.exe, '--version'], text=True, creationflags=0x08000000).strip()
    report = {'fixture': str(root), 'engine': args.exe, 'engineVersion': version, 'model': model['slug'],
              'provider': 'localhost fixture; no account quota', 'requests': len(calls), 'results': results}
    pathlib.Path(args.report).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(args.report).write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    if not all(r['passed'] for r in results): raise SystemExit(1)
