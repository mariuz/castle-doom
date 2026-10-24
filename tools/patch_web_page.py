#!/usr/bin/env python3
"""Patch the web build's play page (castle-engine-output/web/dist/index.html,
CGE's template) for the game's render resolution option, for offline
play (it registers the site's service worker, ../sw.js, which the Web
workflow copies from pages/sw.js, and links the web app manifest,
../manifest.webmanifest, so browsers can install the site) and for a crash
report: the last 40
console lines (the game's log) shown over the page when the WebAssembly
program stops (any exception does: FPC's wasm32 target cannot catch
them), e.g. after the CRASH demo command (play/?map=E1M1&demo=W:2,CRASH),
for the map editor's export (GameViewEdit): window.castleDoomDownload(name,
bytes, type) saves a "binary string" (one character per byte) as a file,
and window.castleDoomOpenFile(kind) / castleDoomTakeFile() /
castleDoomTakeFileBytes() let the custom game page open WAD files,
and for the touch controls (GameTouch): CGE's web backend reports every
pointer as finger 0, so the page tracks the fingers itself. While the game
is played (it calls window.castleDoomTouches(1) every frame) touch
pointer events on the canvas do not reach the engine; the function returns
whether the last pointer was a finger and where the fingers are. The
menus call it with 0 (or not at all for half a second): taps are clicks
there.

CGE's page sizes the canvas to the display's pixels in a ResizeObserver
callback. The patch multiplies that size by window.castleDoomScale (1 by
default) and adds window.castleDoomSetScale(percent), which the game calls
(GameSettings.ApplyWindowSettings) when the "Resolution" option changes or
at startup: fewer pixels for slow browsers, stretched by CSS. CGE notices
the new drawing buffer size itself (TCastleWindow's UpdateCallResize).

Usage: patch_web_page.py INDEX_HTML   (exit code 1 if the template changed
and the patch no longer applies, so CI notices)
"""
import re
import sys

OLD = """      canvas.width = width;
      canvas.height = height;
    }"""

NEW = """      window.castleDoomCanvasSize = [width, height];
      const scale = window.castleDoomScale || 1;
      canvas.width = Math.max(1, Math.round(width * scale));
      canvas.height = Math.max(1, Math.round(height * scale));
    }

    /* Castle DOOM's render resolution option (tools/patch_web_page.py). */
    window.castleDoomSetScale = function (percent) {
      window.castleDoomScale = Math.min(1, Math.max(0.1, percent / 100));
      const size = window.castleDoomCanvasSize;
      if (size) {
        canvas.width = Math.max(1, Math.round(size[0] * window.castleDoomScale));
        canvas.height = Math.max(1, Math.round(size[1] * window.castleDoomScale));
      }
      console.log(`Castle DOOM: render scale ${percent}% (canvas ${canvas.width}x${canvas.height})`);
    };"""


SW_OLD = """    rtl.showUncaughtExceptions=true;"""

SW_NEW = """    /* Offline play after one visit (pages/sw.js at the site root). */
    if ('serviceWorker' in navigator)
      navigator.serviceWorker.register('../sw.js').catch(e => console.log('Service worker not registered:', e));

    rtl.showUncaughtExceptions=true;"""


# The game's script tag (CGE's template: <script src="NAME.js?SUFFIX"></script>);
# the crash script goes before it, so the console.log the game's JS keeps a
# reference to is already the one that remembers the lines.
CRASH_TAG = re.compile(r'(\n  <script src="[^"]+\.js[^"]*"></script>)')

CRASH_NEW = """
  <script>
    /* Castle DOOM's crash report (tools/patch_web_page.py): the last
       console lines over the page when the program stops. */
    (function () {
      const lines = [];
      const log = console.log.bind(console);
      console.log = function (...args) {
        lines.push(args.join(' ').replace(/\\s+$/, ''));
        if (lines.length > 200) lines.shift();
        log(...args);
      };
      let shown = false;
      function showCrash(reason) {
        if (shown) return;
        shown = true;
        const box = document.createElement('div');
        box.id = 'castle-doom-crash';
        box.style.cssText = 'position:fixed;left:5%;top:5%;width:90%;height:90%;z-index:10000;' +
          'background:#1a0000;color:#fdd;font:13px monospace;padding:16px;box-sizing:border-box;' +
          'overflow:auto;border:2px solid #f44;white-space:pre-wrap';
        const report = 'Castle DOOM stopped: ' + reason +
          '\\n\\nThe last log lines:\\n\\n' + lines.join('\\n');
        const copy = document.createElement('button');
        copy.id = 'castle-doom-crash-copy';
        copy.textContent = 'Copy report';
        copy.style.cssText = 'font:14px sans-serif;padding:6px 14px;margin-bottom:12px';
        copy.onclick = () => {
          const done = () => { copy.textContent = 'Copied'; };
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(report).then(done, () => { copy.textContent = 'Select the text to copy'; });
          } else {
            copy.textContent = 'Select the text to copy';
          }
        };
        const intro = document.createElement('div');
        intro.textContent = 'Please add the report to a bug report at ' +
          'https://github.com/mariuz/castle-doom/issues. Reload the page to play again ' +
          '(your saves are kept).';
        intro.style.marginBottom = '8px';
        const text = document.createElement('div');
        text.id = 'castle-doom-crash-text';
        text.textContent = report;
        box.appendChild(intro);
        box.appendChild(copy);
        box.appendChild(text);
        document.body.appendChild(box);
      }
      window.addEventListener('error', e => showCrash(e.message || 'an error'));
      window.castleDoomShowCrash = showCrash;
    })();
  </script>"""


MANIFEST_TAG = re.compile(r'(  <title>[^<]*</title>\n)')

MANIFEST_NEW = """  <link rel="manifest" href="../manifest.webmanifest">
  <link rel="icon" href="../icon-192.png">
  <meta name="theme-color" content="#280808">
"""


# Before the crash script (both go before the game's script tag).
TOUCH_NEW = """
  <style>canvas { touch-action: none; }</style>
  <script>
    /* Castle DOOM's touch controls (tools/patch_web_page.py): the fingers
       on the canvas for GameTouch.PollTouches, kept from the engine while
       the game is played. */
    (function () {
      const fingers = new Map();
      let canvas = null;
      let capture = false;
      let askedAt = 0;
      let touchMode = !!(window.matchMedia && matchMedia('(pointer: coarse)').matches);
      function where(e) {
        const r = canvas.getBoundingClientRect();
        return [Math.round((e.clientX - r.left) * canvas.width / Math.max(1, r.width)),
                Math.round(canvas.height - (e.clientY - r.top) * canvas.height / Math.max(1, r.height))];
      }
      function capturing() {
        return capture && performance.now() - askedAt < 500;
      }
      window.addEventListener('pointerdown', function (e) {
        if (e.pointerType !== 'touch') {
          touchMode = false;
          return;
        }
        touchMode = true;
        if (!capturing() || !(e.target instanceof HTMLCanvasElement)) return;
        canvas = e.target;
        fingers.set(e.pointerId, where(e));
        e.stopPropagation();
        e.preventDefault();
      }, true);
      window.addEventListener('pointermove', function (e) {
        if (e.pointerType === 'mouse' && (e.movementX || e.movementY)) touchMode = false;
        if (!fingers.has(e.pointerId)) return;
        fingers.set(e.pointerId, where(e));
        e.stopPropagation();
        e.preventDefault();
      }, true);
      function up(e) {
        if (!fingers.has(e.pointerId)) return;
        fingers.delete(e.pointerId);
        e.stopPropagation();
        e.preventDefault();
      }
      window.addEventListener('pointerup', up, true);
      window.addEventListener('pointercancel', up, true);
      window.castleDoomTouches = function (playing) {
        capture = !!playing;
        askedAt = performance.now();
        let s = touchMode ? '1' : '0';
        for (const [id, p] of fingers) s += ';' + id + ',' + p[0] + ',' + p[1];
        return s;
      };
    })();
  </script>"""


DOWNLOAD_NEW = """
  <script>
    /* Castle DOOM's file saving (tools/patch_web_page.py): the map
       editor's PWAD export, bytes as a "binary string". */
    window.castleDoomDownload = function (name, bytes, type) {
      const data = new Uint8Array(bytes.length);
      for (let i = 0; i < bytes.length; i++) data[i] = bytes.charCodeAt(i) & 255;
      const url = URL.createObjectURL(new Blob([data], {type: type || 'application/octet-stream'}));
      const a = document.createElement('a');
      a.href = url;
      a.download = name;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
    };
    /* Opening files (the custom game page's IWAD and PWADs, Options ->
       Play demo...): a hidden
       <input type=file>; the chosen file waits until the game takes it,
       first "kind|name", then its bytes as a binary string. The browser
       allows the click shortly after the key press that asked for it. */
    (function () {
      let input = null, kind = '', picked = [];
      window.castleDoomOpenFile = function (k) {
        kind = k;
        if (!input) {
          input = document.createElement('input');
          input.type = 'file';
          input.style.display = 'none';
          input.addEventListener('change', function () {
            const file = input.files && input.files[0];
            if (!file) return;
            const thisKind = kind;
            file.arrayBuffer().then(function (buffer) {
              const bytes = new Uint8Array(buffer);
              keep(file.name, buffer);
              let s = '';
              for (let i = 0; i < bytes.length; i += 8192)
                s += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
              picked.push({head: thisKind + '|' + file.name, bytes: s});
              console.log('Castle DOOM: picked ' + file.name + ' (' + bytes.length + ' bytes)');
            });
            input.value = '';
          });
          document.body.appendChild(input);
        }
        input.accept = k === 'demo' ? '.cdemo' : '.wad,.WAD';
        input.click();
      };
      /* The picked files outlive the page in IndexedDB (database
         castle-doom-files, store files, key the name): read at load,
         given back by name (castleDoomStoredFile, a binary string or
         null) when a recent set, save or demo names upload:/NAME. */
      const stored = {};
      let db = null;
      try {
        const open = indexedDB.open('castle-doom-files', 1);
        open.onupgradeneeded = function () { open.result.createObjectStore('files'); };
        open.onsuccess = function () {
          db = open.result;
          const cursor = db.transaction('files').objectStore('files').openCursor();
          cursor.onsuccess = function () {
            const c = cursor.result;
            if (!c) return;
            if (!(c.key in stored)) stored[c.key] = c.value;
            c.continue();
          };
        };
      } catch (e) { console.log('Castle DOOM: no IndexedDB, picked files last until a reload'); }
      function keep(name, buffer) {
        stored[name] = buffer;
        if (db) db.transaction('files', 'readwrite').objectStore('files').put(buffer, name);
      }
      window.castleDoomStoredFile = function (name) {
        const buffer = stored[name];
        if (!buffer) return null;
        const bytes = new Uint8Array(buffer);
        let s = '';
        for (let i = 0; i < bytes.length; i += 8192)
          s += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
        return s;
      };
      window.castleDoomForgetFile = function (name) {
        delete stored[name];
        if (db) db.transaction('files', 'readwrite').objectStore('files').delete(name);
      };
      window.castleDoomTakeFile = function () {
        return picked.length ? picked[0].head : null;
      };
      window.castleDoomTakeFileBytes = function () {
        const f = picked.shift();
        return f ? f.bytes : null;
      };
    })();
  </script>"""


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    path = sys.argv[1]
    with open(path, encoding='utf-8') as f:
        text = f.read()
    done = []
    if 'castle-doom-crash' not in text:
        if len(CRASH_TAG.findall(text)) != 1:
            print('%s: the game script tag was not found, cannot add the crash report' % path)
            sys.exit(1)
        text = CRASH_TAG.sub(lambda m: CRASH_NEW + m.group(1), text)
        done.append('crash report')
    if 'castleDoomTouches' not in text:
        if len(CRASH_TAG.findall(text)) != 1:
            print('%s: the game script tag was not found, cannot add the touch controls' % path)
            sys.exit(1)
        text = CRASH_TAG.sub(lambda m: TOUCH_NEW + m.group(1), text)
        done.append('touch controls')
    if 'castleDoomDownload' not in text:
        if len(CRASH_TAG.findall(text)) != 1:
            print('%s: the game script tag was not found, cannot add file saving' % path)
            sys.exit(1)
        text = CRASH_TAG.sub(lambda m: DOWNLOAD_NEW + m.group(1), text)
        done.append('file saving')
    if 'manifest.webmanifest' not in text:
        if len(MANIFEST_TAG.findall(text)) != 1:
            print('%s: the title was not found, cannot link the manifest' % path)
            sys.exit(1)
        text = MANIFEST_TAG.sub(lambda m: m.group(1) + MANIFEST_NEW, text)
        done.append('manifest')
    for marker, before, after, what in [('castleDoomSetScale', OLD, NEW, 'render scale'),
                                        ('serviceWorker', SW_OLD, SW_NEW, 'service worker')]:
        if marker in text:
            continue
        if text.count(before) != 1:
            print('%s: the code for the %s patch was not found, cannot patch' % (path, what))
            sys.exit(1)
        text = text.replace(before, after)
        done.append(what)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('%s: patched (%s)' % (path, ', '.join(done) or 'already patched'))


if __name__ == '__main__':
    main()
