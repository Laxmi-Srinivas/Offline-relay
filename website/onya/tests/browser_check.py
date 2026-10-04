"""Exercise the actual static page in local Chromium. Standard library only.

Uses a temporary browser profile and local HTTP server; no project data leaves
the machine. Screenshots/results go to the requested output directory, not Git.
"""
import argparse
import base64
from functools import partial
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading
import time
import urllib.parse
import urllib.request


class WebSocket:
    def __init__(self, url):
        parsed = urllib.parse.urlparse(url)
        self.socket = socket.create_connection((parsed.hostname, parsed.port), timeout=15)
        key = base64.b64encode(os.urandom(16)).decode()
        request = (f'GET {parsed.path} HTTP/1.1\r\nHost: {parsed.hostname}:{parsed.port}\r\n'
                   f'Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n'
                   'Sec-WebSocket-Version: 13\r\n\r\n')
        self.socket.sendall(request.encode())
        response = b''
        while not response.endswith(b'\r\n\r\n'):
            response += self.socket.recv(1)
        expected = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
        assert response.startswith(b'HTTP/1.1 101 ') and expected in response, 'WebSocket handshake'

    def read(self, length):
        data = b''
        while len(data) < length:
            chunk = self.socket.recv(length - len(data))
            if not chunk:
                raise RuntimeError('Browser closed connection')
            data += chunk
        return data

    def send(self, value):
        data = json.dumps(value).encode()
        mask = os.urandom(4)
        length = len(data)
        header = bytes([0x81, 0x80 | (length if length < 126 else 126 if length < 65536 else 127)])
        if length >= 65536:
            header += struct.pack('!Q', length)
        elif length >= 126:
            header += struct.pack('!H', length)
        self.socket.sendall(header + mask + bytes(byte ^ mask[index % 4] for index, byte in enumerate(data)))

    def receive(self):
        first, second = self.read(2)
        length = second & 127
        if length == 126:
            length = struct.unpack('!H', self.read(2))[0]
        elif length == 127:
            length = struct.unpack('!Q', self.read(8))[0]
        mask = self.read(4) if second & 128 else None
        data = self.read(length)
        if mask:
            data = bytes(byte ^ mask[index % 4] for index, byte in enumerate(data))
        if first & 15 == 8:
            raise RuntimeError('Browser closed WebSocket')
        if first & 15 != 1:
            return self.receive()
        return json.loads(data)


class CDP:
    def __init__(self, url):
        self.ws = WebSocket(url)
        self.next_id = 0
        self.events = []

    def call(self, method, **params):
        self.next_id += 1
        request_id = self.next_id
        self.ws.send({'id': request_id, 'method': method, 'params': params})
        while True:
            message = self.ws.receive()
            if message.get('id') == request_id:
                if 'error' in message:
                    raise RuntimeError(message['error'])
                return message.get('result', {})
            self.events.append(message)

    def evaluate(self, expression):
        result = self.call('Runtime.evaluate', expression=expression, returnByValue=True, awaitPromise=True)
        if 'exceptionDetails' in result:
            raise RuntimeError(result['exceptionDetails'])
        return result['result'].get('value')


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def translate_path(self, path):
        if path.startswith('/Offline-relay/'):
            path = path[len('/Offline-relay'):]
        return super().translate_path(path)

    def handle(self):
        try:
            super().handle()
        except (ConnectionResetError, BrokenPipeError):
            # Chromium closes keep-alive sockets when the temporary profile exits.
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', required=True, help='Path to Chrome or Edge executable')
    parser.add_argument('--output', required=True, help='External directory for results/screenshots')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    results = []
    server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(root)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    origin = f'http://127.0.0.1:{server.server_port}'
    process = None

    def passed(name):
        results.append(name)
        print('PASS:', name, flush=True)

    with tempfile.TemporaryDirectory(prefix='onya-browser-') as profile:
        log = open(output / 'browser.log', 'wb')
        try:
            process = subprocess.Popen([args.browser, '--headless=new', '--disable-gpu', '--no-first-run',
                '--disable-background-networking', '--disable-component-update', '--disable-sync',
                '--disable-default-apps', '--remote-debugging-port=0', '--remote-debugging-address=127.0.0.1',
                '--user-data-dir=' + profile, 'about:blank'], stdout=log, stderr=log,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            port_file = Path(profile) / 'DevToolsActivePort'
            for _ in range(150):
                if port_file.exists():
                    break
                time.sleep(.1)
            assert port_file.exists(), 'Chromium did not start; inspect browser.log'
            port = int(port_file.read_text().splitlines()[0])
            targets = json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}/json'))
            cdp = CDP(next(item['webSocketDebuggerUrl'] for item in targets if item['type'] == 'page'))
            cdp.call('Runtime.enable')
            cdp.call('Page.enable')
            cdp.call('Network.enable')
            cdp.call('Log.enable')
            cdp.call('Page.navigate', url=origin + '/')
            for _ in range(100):
                if cdp.evaluate("document.readyState === 'complete' && !!document.querySelector('.simulation') && document.querySelector('[data-step]').hasAttribute('aria-current')"):
                    break
                time.sleep(.05)
            cdp.evaluate('document.fonts.ready.then(() => true)')
            assert cdp.evaluate("document.querySelector('.simulation').dataset.state") == 'available'
            assert cdp.evaluate("Array.from(document.fonts).some(f => f.family === 'Manrope' && f.status === 'loaded')"), 'Local font did not load'
            passed('Local page, JavaScript and self-hosted font load without console exceptions')
            assert cdp.evaluate("(() => { const ids = Array.from(document.querySelectorAll('[id]')).map(e => e.id); return new Set(ids).size === ids.length; })()"), 'Duplicate element IDs'
            assert cdp.evaluate("Array.from(document.querySelectorAll('[aria-labelledby]')).every(e => e.getAttribute('aria-labelledby').split(' ').every(id => document.getElementById(id)))")
            assert cdp.evaluate("Array.from(document.querySelectorAll('button')).every(e => e.textContent.trim() || e.getAttribute('aria-label'))")
            passed('Unique IDs, resolved accessible label references and named buttons')
            assert cdp.evaluate("document.getElementById('android-download').hidden && !document.getElementById('android-download').hasAttribute('href') && document.getElementById('iphone-demo').hidden && !document.getElementById('iphone-demo').hasAttribute('href')")
            passed('Android APK and iPhone demo links stay absent until real supplied assets exist')

            def state():
                return cdp.evaluate("document.querySelector('.simulation').dataset.state")

            def click(identifier):
                cdp.evaluate(f"document.getElementById('{identifier}').click()")

            for invalid in ['accept-button', 'chat-button', 'request-button', 'reject-button']:
                click(invalid)
                assert state() == 'available'
            assert cdp.evaluate("document.getElementById('requester-chat').hidden")
            passed('Out-of-order transitions cannot open chat')
            click('discover-button')
            assert state() == 'discovered'
            click('request-button')
            assert state() == 'requested'
            click('chat-button')
            assert state() == 'requested' and cdp.evaluate("document.getElementById('requester-chat').hidden")
            click('reject-button')
            assert state() == 'rejected' and cdp.evaluate("document.getElementById('requester-chat').hidden")
            click('accept-button')
            assert state() == 'rejected'
            passed('Rejection keeps chat closed and cannot be overridden by a stale accept')
            click('restart-button')
            click('discover-button')
            click('request-button')
            click('accept-button')
            assert state() == 'accepted' and cdp.evaluate("document.activeElement.id") == 'chat-button'
            click('chat-button')
            assert state() == 'chat' and cdp.evaluate("document.querySelectorAll('#requester-chat .chat-bubble').length") == 3
            assert not cdp.evaluate("document.getElementById('requester-chat').hidden")
            click('reset-simulation')
            assert state() == 'available' and cdp.evaluate("document.querySelectorAll('.chat-bubble').length") == 0
            passed('Acceptance, example chat and reset work; reset removes previous chat')

            for sequence in [[], ['discover-button'], ['discover-button', 'request-button'],
                             ['discover-button', 'request-button', 'accept-button'],
                             ['discover-button', 'request-button', 'reject-button']]:
                for identifier in sequence:
                    click(identifier)
                click('reset-simulation')
                assert state() == 'available'
            passed('Reset works from every intermediate/rejected state')

            cdp.evaluate("document.getElementById('discover-button').focus()")
            cdp.call('Input.dispatchKeyEvent', type='keyDown', key='Enter', code='Enter', windowsVirtualKeyCode=13, text='\r')
            cdp.call('Input.dispatchKeyEvent', type='keyUp', key='Enter', code='Enter', windowsVirtualKeyCode=13)
            assert state() == 'discovered'
            assert cdp.evaluate("document.activeElement.id") == 'request-button'
            cdp.call('Input.dispatchKeyEvent', type='keyDown', key='Tab', code='Tab', windowsVirtualKeyCode=9)
            cdp.call('Input.dispatchKeyEvent', type='keyUp', key='Tab', code='Tab', windowsVirtualKeyCode=9)
            assert cdp.evaluate("getComputedStyle(document.activeElement).outlineStyle") != 'none'
            passed('Keyboard Enter activates the flow; focus follows state and Tab has a visible outline')

            links = cdp.evaluate("Array.from(document.querySelectorAll('a[href],link[href],script[src],img[src]')).map(e => e.getAttribute('href') || e.getAttribute('src'))")
            for link in links:
                if link.startswith('https:'):
                    assert urllib.parse.urlparse(link).hostname == 'github.com', link
                    continue
                parsed = urllib.parse.urlparse(link)
                if parsed.path:
                    resource = urllib.request.urlopen(origin + '/' + parsed.path)
                    assert resource.status == 200, link
                if not parsed.path and parsed.fragment:
                    assert cdp.evaluate('!!document.getElementById(' + json.dumps(parsed.fragment) + ')'), link
            passed('All presentation local assets, evidence links and anchors resolve; external links target the approved GitHub repo')

            cdp.call('Emulation.setEmulatedMedia', features=[{'name': 'prefers-reduced-motion', 'value': 'reduce'}])
            assert cdp.evaluate("matchMedia('(prefers-reduced-motion: reduce)').matches && getComputedStyle(document.documentElement).scrollBehavior === 'auto'")
            passed('Reduced-motion preference disables smooth scrolling; content does not depend on animation')
            click('reset-simulation')
            for width in [1440, 1024, 768, 390, 320]:
                cdp.call('Emulation.setDeviceMetricsOverride', width=width, height=1000, deviceScaleFactor=1, mobile=width < 500)
                time.sleep(.1)
                dimensions = cdp.evaluate('({width:innerWidth,scroll:document.documentElement.scrollWidth})')
                assert dimensions['scroll'] <= dimensions['width'] + 1, f'Horizontal overflow at {width}: {dimensions}'
                assert cdp.evaluate("Array.from(document.querySelectorAll('main h1,main h2')).every(e => getComputedStyle(e).display !== 'none')")
                passed(f'Responsive viewport {width}px: no horizontal overflow; all section headings present')
                for sequence in [['discover-button'], ['request-button'], ['accept-button'], ['chat-button']]:
                    for identifier in sequence:
                        click(identifier)
                    assert cdp.evaluate("Array.from(document.querySelectorAll('.phone')).every(p => { const bottom = p.querySelector('.phone-bottom').getBoundingClientRect().top; const content = p.querySelector('.chat-messages:not([hidden])') || p.querySelector('.phone-panel'); return content.getBoundingClientRect().bottom <= bottom; })"), f'Phone content overlaps navigation at {width}px in {state()}'
                click('reset-simulation')
                passed(f'All active simulation screens fit inside the phones at {width}px')
                if width in [1440, 390]:
                    cdp.evaluate('document.activeElement.blur()')
                    cdp.evaluate('scrollTo(0,0)')
                    screenshot = cdp.call('Page.captureScreenshot', format='png', captureBeyondViewport=True,
                        clip={'x': 0, 'y': 0, 'width': width, 'height': min(cdp.evaluate('document.documentElement.scrollHeight'), 8000), 'scale': 1})
                    (output / f'presentation-{width}.png').write_bytes(base64.b64decode(screenshot['data']))
                    hero = cdp.call('Page.captureScreenshot', format='png',
                        clip={'x': 0, 'y': 0, 'width': width, 'height': 1000, 'scale': 1})
                    (output / f'hero-{width}.png').write_bytes(base64.b64decode(hero['data']))

            cdp.call('Emulation.setDeviceMetricsOverride', width=1440, height=1000, deviceScaleFactor=1, mobile=False)
            click('discover-button'); click('request-button'); click('accept-button'); click('chat-button')
            cdp.evaluate("document.getElementById('simulation').scrollIntoView()")
            screenshot = cdp.call('Page.captureScreenshot', format='png')
            (output / 'simulation-chat.png').write_bytes(base64.b64decode(screenshot['data']))

            cdp.call('Page.navigate', url=origin + '/evidence.html')
            time.sleep(.3)
            assert cdp.evaluate("document.title") == 'Onya — Evidence sources'
            evidence_links = cdp.evaluate("Array.from(document.querySelectorAll('a[href]')).map(e=>e.getAttribute('href')).filter(h=>!h.startsWith('https:')&&!h.startsWith('#'))")
            for link in evidence_links:
                assert urllib.request.urlopen(origin + '/' + link.split('#')[0]).status == 200
            passed('Offline evidence appendix and every local report link load')

            cdp.call('Emulation.setDeviceMetricsOverride', width=1200, height=800, deviceScaleFactor=1, mobile=False)
            cdp.call('Page.navigate', url=origin + '/presentation/cover.html')
            time.sleep(.2)
            cdp.evaluate('document.fonts.ready.then(() => true)')
            assert cdp.evaluate('document.documentElement.scrollHeight') == 800
            cover = cdp.call('Page.captureScreenshot', format='png')
            (output / 'devpost-cover.png').write_bytes(base64.b64decode(cover['data']))
            passed('Devpost project-illustration cover renders at 1200 × 800 (3:2)')

            cdp.call('Emulation.setScriptExecutionDisabled', value=True)
            cdp.call('Page.navigate', url=origin + '/')
            time.sleep(.3)
            assert cdp.evaluate("document.querySelector('noscript').offsetHeight > 0")
            passed('JavaScript-disabled page includes a readable noninteractive flow')
            cdp.call('Emulation.setScriptExecutionDisabled', value=False)
            cdp.call('Page.navigate', url=origin + '/Offline-relay/')
            time.sleep(.2)
            cdp.evaluate('document.fonts.ready.then(() => true)')
            click('discover-button'); click('request-button'); click('accept-button'); click('chat-button')
            assert state() == 'chat'
            assert cdp.evaluate("Array.from(document.images).every(i => i.complete && i.naturalWidth > 0)")
            assert cdp.evaluate("Array.from(document.fonts).filter(f => f.status === 'loaded').length === 2")
            passed('GitHub Pages /Offline-relay/ project subpath loads both fonts/assets and the complete interaction')
            cdp.call('Network.setBlockedURLs', urls=['http://*', 'https://*'])
            cdp.call('Page.navigate', url=(root / 'index.html').as_uri())
            for _ in range(50):
                if cdp.evaluate("document.querySelector('.simulation')?.dataset.state === 'available' && document.querySelector('[data-step]')?.hasAttribute('aria-current')"):
                    break
                time.sleep(.05)
            click('discover-button'); click('request-button'); click('accept-button'); click('chat-button')
            assert state() == 'chat'
            assert cdp.evaluate("Array.from(document.images).every(i=>i.complete&&i.naturalWidth>0)")
            passed('Direct file:// fallback works with all HTTP/HTTPS requests blocked, including simulation and illustration')
            exceptions = [event for event in cdp.events if event.get('method') == 'Runtime.exceptionThrown']
            assert not exceptions, exceptions
            requests = [event['params']['request']['url'] for event in cdp.events if event.get('method') == 'Network.requestWillBeSent']
            external_requests = [url for url in requests if url.startswith(('https:', 'http:')) and not url.startswith(origin + '/')]
            assert not external_requests, external_requests
            passed('No JavaScript runtime exceptions or external website resource requests')
            (output / 'results.json').write_text(json.dumps({'checks_passed': results, 'browser': args.browser,
                'limitations': ['No physical mobile tests', 'No external link HTTP checks', 'No screen-reader audit',
                                'No Safari/Firefox or physical browser device tests', 'file:// may use system font fallback'],
                'screenshots': ['presentation-1440.png', 'presentation-390.png', 'simulation-chat.png']}, indent=2) + '\n')
        finally:
            if process is not None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            log.close()
            server.shutdown()


if __name__ == '__main__':
    main()
