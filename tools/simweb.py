#!/usr/bin/env python3
"""Simulator viewer: a local web page showing the simulated Kindle screen, with the 13 buttons and keyboard shortcuts.
  tools/simweb.py [--port 8470] [--sim build/sim]
Keys pressed on the page are queued in <sim>/keys.txt for the simulated k4keys (tools/simbin/k4keys), the screen is
exported from <sim>/screen.raw with the host k4draw, and refreshes recorded by K4DRAW_TRACE=<sim>/trace.txt are drawn
as outlines (dashed = partial, solid = full flash). Standard library only; runs on Windows or Linux (WSL).
Keyboard: arrows = 5-way, Enter = select, PageUp/PageDown or [ ] = left page keys, , . = right page keys,
          h = home, m = menu, Backspace/b = back, k = keyboard key, shift+k = hold keyboard 1.5 s, r = turn device,
          p = power button (queues powerd's goingToScreenSaver/readyToSuspend, then outOfScreenSaver, for the simulated lipc-wait-event).
"""
import json, os, subprocess, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
PORT = int(args[args.index('--port') + 1]) if '--port' in args else 8470
SIM = args[args.index('--sim') + 1] if '--sim' in args else os.path.join(ROOT, 'build', 'sim')
os.makedirs(SIM, exist_ok=True)
RAW, KEYS, TRACE, EVENTS = (os.path.join(SIM, n) for n in ('screen.raw', 'keys.txt', 'trace.txt', 'events.txt'))
K4DRAW = next((p for p in (os.path.join(ROOT, 'build', 'host', 'k4draw.exe'), os.path.join(ROOT, 'build', 'host', 'k4draw')) if os.path.exists(p)), None)

PAGE = r'''<!doctype html><html><head><meta charset="utf-8"><title>kindle4ever sim</title>
<style>
body{margin:0;background:#2a2a2a;color:#ddd;font:14px system-ui,sans-serif;display:flex;gap:28px;padding:20px;align-items:flex-start}
#dev{background:#111;border-radius:22px;padding:28px 26px 30px;box-shadow:0 10px 40px #000a;position:relative;display:inline-block}
#scr{position:relative;width:600px;height:800px;background:#fff;transition:transform .3s}
#scr img{display:block;width:600px;height:800px;image-rendering:pixelated}
#scr canvas{position:absolute;left:0;top:0;pointer-events:none}
.turn #scr{transform:rotate(-90deg) translate(-100px,-100px)}
.row{display:flex;justify-content:center;gap:10px;margin-top:14px}
button{background:#333;color:#eee;border:1px solid #555;border-radius:8px;padding:8px 12px;font:13px system-ui;cursor:pointer;min-width:58px}
button:active,button.on{background:#777}
.side{position:absolute;top:300px;display:flex;flex-direction:column;gap:120px}
.side.l{left:-2px}.side.r{right:-2px}
.side button{width:22px;min-width:0;height:90px;padding:0;writing-mode:vertical-rl;font-size:11px}
.fiveway{display:grid;grid-template-columns:repeat(3,58px);grid-template-rows:repeat(3,36px);gap:4px;margin:0 12px}
#panel{min-width:320px;line-height:1.6}
#panel code{background:#111;padding:1px 5px;border-radius:4px}
#log{font:12px ui-monospace,monospace;background:#111;padding:8px;border-radius:6px;height:260px;overflow:auto;white-space:pre}
small{color:#999}
</style></head><body>
<div id="dev">
  <div class="side l"><button data-k="lprev">prev</button><button data-k="lnext">next</button></div>
  <div class="side r"><button data-k="rprev">prev</button><button data-k="rnext">next</button></div>
  <div id="scr"><img id="img" src="/screen.png"><canvas id="ov" width="600" height="800"></canvas></div>
  <div class="row">
    <button data-k="back">Back</button><button data-k="kbd" title="shift+click = hold 1.5 s">Kbd</button>
    <div class="fiveway">
      <span></span><button data-k="up">&#9650;</button><span></span>
      <button data-k="left">&#9664;</button><button data-k="select">OK</button><button data-k="right">&#9654;</button>
      <span></span><button data-k="down">&#9660;</button><span></span>
    </div>
    <button data-k="menu">Menu</button><button data-k="home">Home</button>
  </div>
</div>
<div id="panel">
  <b>kindle4ever simulator</b><br>
  <button id="turn">Turn device (r)</button> <button id="clr">Clear trace</button> <label><input type="checkbox" id="trace" checked> show refreshes</label><br>
  <button id="pwr" title="power button: sleep when awake, wake when asleep (p)">Power button (p)</button> <span id="pstate">awake</span><br>
  <small>arrows/Enter = 5-way · [ ] and , . = page keys · h m b k = home menu back kbd · shift+k = hold kbd</small>
  <p>Refreshes: <span id="cnt">0</span> partial, <span id="flash">0</span> full · queue: <span id="q">0</span></p>
  <div id="log"></div>
</div>
<script>
const img=document.getElementById('img'), ov=document.getElementById('ov'), ctx=ov.getContext('2d'), log=document.getElementById('log');
function key(k, hold){ fetch('/key?name='+k+(hold?'&hold='+hold:''),{method:'POST'}); const b=document.querySelector('[data-k="'+k+'"]'); if(b){b.classList.add('on'); setTimeout(()=>b.classList.remove('on'),150);} }
document.querySelectorAll('[data-k]').forEach(b=>b.onclick=e=>key(b.dataset.k, (b.dataset.k==='kbd'&&e.shiftKey)?1500:0));
const map={ArrowUp:'up',ArrowDown:'down',ArrowLeft:'left',ArrowRight:'right',Enter:'select',PageUp:'lprev',PageDown:'lnext','[':'lprev',']':'lnext',',':'rprev','.':'rnext',h:'home',m:'menu',b:'back',Backspace:'back',k:'kbd'};
document.addEventListener('keydown',e=>{ if(e.key==='r'){turn();return;} if(e.key==='p'){power();return;} if(e.key==='K'){key('kbd',1500);return;} const k=map[e.key]; if(k){e.preventDefault(); key(k);} });
function turn(){document.body.classList.toggle('turn');}
let asleep=false;
function power(){ asleep=!asleep; fetch('/event?name='+(asleep?'goingToScreenSaver,readyToSuspend':'outOfScreenSaver'),{method:'POST'}); document.getElementById('pstate').textContent=asleep?'asleep (screensaver shown, powerd would suspend)':'awake'; }
document.getElementById('pwr').onclick=power;
document.getElementById('turn').onclick=turn;
document.getElementById('clr').onclick=()=>fetch('/trace?clear=1',{method:'POST'});
let seen=0;
async function tick(){
  const r=await fetch('/state'); const s=await r.json();
  if(s.screen!==seen){ seen=s.screen; img.src='/screen.png?'+seen; }
  document.getElementById('q').textContent=s.queue;
  document.getElementById('cnt').textContent=s.partial; document.getElementById('flash').textContent=s.full;
  ctx.clearRect(0,0,600,800);
  if(document.getElementById('trace').checked){
    s.rects.forEach((t,i)=>{ const a=0.25+0.75*(i+1)/s.rects.length; ctx.lineWidth=2;
      if(t.fx===3||t.fx===1){ctx.setLineDash([]); ctx.strokeStyle='rgba(220,60,60,'+a+')';} else {ctx.setLineDash([6,4]); ctx.strokeStyle='rgba(60,140,255,'+a+')';}
      ctx.strokeRect(t.x+1,t.y+1,Math.max(t.w-2,1),Math.max(t.h-2,1)); });
  }
  if(s.log!==log.textContent){ log.textContent=s.log; log.scrollTop=log.scrollHeight; }
}
setInterval(tick,300); tick();
</script></body></html>'''

def export_png():
    out = os.path.join(SIM, 'screen.png')
    if not K4DRAW or not os.path.exists(RAW):
        return None
    env = dict(os.environ, K4DRAW_FB=RAW)
    env.pop('K4DRAW_ROTATE', None)  # the raw file is always the physical portrait panel
    subprocess.run([K4DRAW, 'export', out, '--panel'], env=env, capture_output=True)
    return out

def trace():
    rects, partial, full = [], 0, 0
    try:
        for ln in open(TRACE, encoding='utf-8', errors='replace').read().splitlines():
            p = ln.split()
            if len(p) < 6: continue
            fx = int(p[1][3:]); x, y, w, h = map(int, p[2:6])
            if fx in (1, 3): full += 1
            else: partial += 1
            rects.append(dict(fx=fx, x=x, y=y, w=w, h=h))
    except FileNotFoundError:
        pass
    return rects[-40:], partial, full

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body, ctype='text/plain'):
        self.send_response(code); self.send_header('Content-Type', ctype); self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        u = urlparse(self.path)
        if u.path == '/':
            return self.send(200, PAGE.encode(), 'text/html; charset=utf-8')
        if u.path == '/screen.png':
            out = export_png()
            if not out: return self.send(404, b'no screen yet (run something with tools/sim first)')
            return self.send(200, open(out, 'rb').read(), 'image/png')
        if u.path == '/state':
            rects, partial, full = trace()
            try: queue = len(open(KEYS).read().split())
            except FileNotFoundError: queue = 0
            mtime = int(os.path.getmtime(RAW) * 1000) if os.path.exists(RAW) else 0
            tail = ''
            lp = os.path.join(SIM, 'run.log')
            if os.path.exists(lp):
                tail = open(lp, encoding='utf-8', errors='replace').read()[-4000:]
            return self.send(200, json.dumps(dict(screen=mtime, queue=queue, partial=partial, full=full, rects=rects, log=tail)).encode(), 'application/json')
        self.send(404, b'not found')
    def do_POST(self):
        u = urlparse(self.path); q = parse_qs(u.query)
        if u.path == '/key':
            name = q.get('name', [''])[0]; hold = q.get('hold', ['0'])[0]
            if name:
                with open(KEYS, 'a', newline='\n') as f: f.write(f'{name} {hold}\n')
            return self.send(200, b'ok')
        if u.path == '/trace':
            open(TRACE, 'w').close(); return self.send(200, b'ok')
        if u.path == '/event':
            for name in q.get('name', [''])[0].split(','):
                if name:
                    with open(EVENTS, 'a', newline='\n') as f: f.write(name + '\n')
            return self.send(200, b'ok')
        self.send(404, b'not found')

if __name__ == '__main__':
    print(f'kindle4ever sim viewer: http://localhost:{PORT}  (screen {RAW}, keys {KEYS})')
    ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
