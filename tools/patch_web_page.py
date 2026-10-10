#!/usr/bin/env python3
"""Patch the web build's play page (castle-engine-output/web/dist/index.html,
CGE's template) for the game's render resolution option, for offline
play (it registers the site's service worker, ../sw.js, which the Web
workflow copies from pages/sw.js) and for a crash report: the last 40
console lines (the game's log) shown over the page when the WebAssembly
program stops (any exception does: FPC's wasm32 target cannot catch
them), e.g. after the CRASH demo command (play/?map=E1M1&demo=W:2,CRASH).

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
        if (lines.length > 40) lines.shift();
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
        box.textContent = 'Castle DOOM stopped: ' + reason +
          '\\n\\nThe last log lines (please add them to a bug report at ' +
          'https://github.com/mariuz/castle-doom/issues):\\n\\n' + lines.join('\\n') +
          '\\n\\nReload the page to play again (your saves are kept).';
        document.body.appendChild(box);
      }
      window.addEventListener('error', e => showCrash(e.message || 'an error'));
      window.castleDoomShowCrash = showCrash;
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
