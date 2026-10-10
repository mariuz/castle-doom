#!/usr/bin/env python3
"""Patch the web build's play page (castle-engine-output/web/dist/index.html,
CGE's template) for the game's render resolution option.

CGE's page sizes the canvas to the display's pixels in a ResizeObserver
callback. The patch multiplies that size by window.castleDoomScale (1 by
default) and adds window.castleDoomSetScale(percent), which the game calls
(GameSettings.ApplyWindowSettings) when the "Resolution" option changes or
at startup: fewer pixels for slow browsers, stretched by CSS. CGE notices
the new drawing buffer size itself (TCastleWindow's UpdateCallResize).

Usage: patch_web_page.py INDEX_HTML   (exit code 1 if the template changed
and the patch no longer applies, so CI notices)
"""
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


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    path = sys.argv[1]
    with open(path, encoding='utf-8') as f:
        text = f.read()
    if 'castleDoomSetScale' in text:
        print('%s: already patched' % path)
        return
    if text.count(OLD) != 1:
        print('%s: the canvas sizing code was not found, cannot patch' % path)
        sys.exit(1)
    text = text.replace(OLD, NEW)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('%s: patched for the render scale' % path)


if __name__ == '__main__':
    main()
