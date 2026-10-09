#!/usr/bin/env python3
"""Write a WiX (v4/v5 schema) source for a Windows installer of Castle DOOM.

Usage: make_msi_wxs.py PACKAGE_ZIP VERSION OUT_DIR

Unpacks the zip that `castle-engine package --os=win64` made into
OUT_DIR/files, and writes OUT_DIR/castle-doom.wxs installing every file
under "Program Files\\Castle DOOM" with a Start menu shortcut. Build it on
Windows with `wix build -arch x64 OUT_DIR/castle-doom.wxs -o NAME.msi`
(the CI `build-msi` job in .github/workflows/build.yml does).
"""

import os
import sys
import zipfile
from xml.sax.saxutils import quoteattr

# Never change this: Windows Installer recognises newer versions of the
# same product by it (MajorUpgrade replaces the installed one).
UPGRADE_CODE = '3DE97CAD-B07D-4D0C-9582-92CA6657467D'
EXE = 'castle-doom.exe'


def main():
    package_zip, version, out_dir = sys.argv[1:4]
    files_dir = os.path.join(out_dir, 'files')
    with zipfile.ZipFile(package_zip) as z:
        z.extractall(files_dir)
    # The package zip has one top directory (castle-doom/); install its contents.
    root = files_dir
    entries = os.listdir(root)
    while len(entries) == 1 and os.path.isdir(os.path.join(root, entries[0])):
        root = os.path.join(root, entries[0])
        entries = os.listdir(root)
    if not os.path.isfile(os.path.join(root, EXE)):
        sys.exit('%s not found in %s' % (EXE, package_zip))

    # MSI versions are major.minor.build (0..255.0..255.0..65535).
    msi_version = '.'.join((version.split('.') + ['0', '0', '0'])[:3])

    counter = [0]

    def new_id(prefix):
        counter[0] += 1
        return '%s%d' % (prefix, counter[0])

    components = []

    def directory(path, indent):
        lines = []
        for name in sorted(os.listdir(path)):
            full = os.path.join(path, name)
            source = os.path.abspath(full)
            if os.path.isdir(full):
                lines.append('%s<Directory Id="%s" Name=%s>' % (indent, new_id('Dir'), quoteattr(name)))
                lines += directory(full, indent + '  ')
                lines.append('%s</Directory>' % indent)
            else:
                comp = new_id('Comp')
                components.append(comp)
                lines.append('%s<Component Id="%s">' % (indent, comp))
                if name == EXE and path == root:
                    # Advertised shortcut: no registry key path needed.
                    lines.append('%s  <File Id="MainExe" Source=%s KeyPath="yes">' % (indent, quoteattr(source)))
                    lines.append('%s    <Shortcut Id="StartMenuShortcut" Directory="ProgramMenuFolder" '
                                 'Name="Castle DOOM" WorkingDirectory="INSTALLFOLDER" Icon="AppIcon.exe" '
                                 'IconIndex="0" Advertise="yes" />' % indent)
                    lines.append('%s  </File>' % indent)
                else:
                    lines.append('%s  <File Id="%s" Source=%s KeyPath="yes" />' % (indent, new_id('File'), quoteattr(source)))
                lines.append('%s</Component>' % indent)
        return lines

    tree = directory(root, '        ')
    wxs = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">',
        '  <Package Name="Castle DOOM" Manufacturer="Castle DOOM contributors"',
        '           Version="%s" UpgradeCode="%s" Scope="perMachine" Compressed="yes">' % (msi_version, UPGRADE_CODE),
        '    <MajorUpgrade DowngradeErrorMessage="A newer version of Castle DOOM is already installed." />',
        '    <MediaTemplate EmbedCab="yes" />',
        '    <Icon Id="AppIcon.exe" SourceFile=%s />' % quoteattr(os.path.abspath(os.path.join(root, EXE))),
        '    <Property Id="ARPPRODUCTICON" Value="AppIcon.exe" />',
        '    <Property Id="ARPURLINFOABOUT" Value="https://github.com/mariuz/castle-doom" />',
        '    <StandardDirectory Id="ProgramFiles64Folder">',
        '      <Directory Id="INSTALLFOLDER" Name="Castle DOOM">',
    ] + tree + [
        '      </Directory>',
        '    </StandardDirectory>',
        '    <StandardDirectory Id="ProgramMenuFolder" />',
        '    <Feature Id="Main" Title="Castle DOOM">',
    ] + ['      <ComponentRef Id="%s" />' % c for c in components] + [
        '    </Feature>',
        '  </Package>',
        '</Wix>',
        '',
    ]
    with open(os.path.join(out_dir, 'castle-doom.wxs'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(wxs))
    print('Wrote %s: %d files, version %s' % (os.path.join(out_dir, 'castle-doom.wxs'), len(components), msi_version))


if __name__ == '__main__':
    main()
