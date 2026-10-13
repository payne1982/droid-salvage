#!/usr/bin/env python3
"""List the symbols the vendor blobs import that nothing in the built system exports.

    tools/missing-symbols.py out/target/product/ASUS_P00I [proprietary-files.txt]

The dynamic linker reports a missing symbol one at a time, when the file is loaded,
and stops there: a daemon with five of them takes five builds to find out. This reads
them all from the build output instead. For every blob it takes the undefined dynamic
symbols and looks for each in the blob's DT_NEEDED libraries, followed to the end, and
in the shim libraries TARGET_LD_SHIM_LIBS gives it (--shim 'path|lib.so:...').

Only blobs are looked at (the files proprietary-files.txt names): what the tree
compiles is checked by its own link. Needs readelf and nm.

What it cannot see: a symbol a library gets from the process that dlopen()s it, which
shows here as missing though it is not; and libraries a daemon dlopen()s by name.
"""
import os
import re
import subprocess
import sys

args = [a for a in sys.argv[1:] if not a.startswith('--')]
opts = [a for a in sys.argv[1:] if a.startswith('--')]
if not args:
    sys.exit(__doc__)
out = args[0].rstrip('/')
here = os.path.dirname(os.path.abspath(__file__))
plist = args[1] if len(args) > 1 else os.path.join(here, '..', 'proprietary-files.txt')
system = os.path.join(out, 'system')

shims = {}
for o in opts:
    if o.startswith('--shim='):
        for pair in o[len('--shim='):].split(':'):
            target, lib = pair.split('|')
            shims.setdefault(target.replace('/system/', '', 1), []).append(lib)


def elf_class(path):
    try:
        with open(path, 'rb') as f:
            head = f.read(5)
    except OSError:
        return None
    if head[:4] != b'\x7fELF':
        return None
    return 64 if head[4] == 2 else 32


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


# Every shared library in the image, by bitness and name. The first directory wins,
# in roughly the order the linker would look.
libs = {32: {}, 64: {}}
subdirs = {32: ['lib', 'vendor/lib', 'system_ext/lib', 'product/lib'],
           64: ['lib64', 'vendor/lib64', 'system_ext/lib64', 'product/lib64']}
for bits, dirs in subdirs.items():
    roots = [os.path.join(system, d) for d in dirs]
    apex = os.path.join(system, 'apex')
    if os.path.isdir(apex):
        for a in sorted(os.listdir(apex)):
            roots.append(os.path.join(apex, a, 'lib64' if bits == 64 else 'lib'))
    for root in roots:
        for dirpath, _, files in os.walk(root):
            for name in files:
                if name.endswith('.so') and name not in libs[bits]:
                    path = os.path.join(dirpath, name)
                    if elf_class(path) == bits:
                        libs[bits][name] = path

needed_cache, defined_cache = {}, {}


def needed(path):
    if path not in needed_cache:
        needed_cache[path] = re.findall(r'Shared library: \[(.*?)\]', run('readelf', '-d', path))
    return needed_cache[path]


def symbols(path, flag):
    names = set()
    for line in run('nm', '-D', flag, path).splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[-2] not in 'wv':      # weak undefined may stay so
            names.add(parts[-1].split('@')[0])
    return names


def defined(path):
    if path not in defined_cache:
        defined_cache[path] = symbols(path, '--defined-only')
    return defined_cache[path]


blobs = []
for line in open(plist):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    line = line.lstrip('-').split('|')[0]
    blobs.append(line.split(':')[-1])

total = 0
for rel in sorted(set(blobs)):
    path = os.path.join(system, rel)
    bits = elf_class(path)
    if bits is None:
        continue
    queue = needed(path) + shims.get(rel, [])
    seen, have, absent = set(), set(), []
    while queue:
        name = queue.pop(0)
        if name in seen:
            continue
        seen.add(name)
        lib = libs[bits].get(name)
        if lib is None:
            absent.append(name)
            continue
        have |= defined(lib)
        queue += needed(lib)
    missing = sorted(symbols(path, '--undefined-only') - have - defined(path))
    if missing or absent:
        print(rel)
        for name in absent:
            print('    no library  ' + name)
        for name in missing:
            print('    ' + name)
        total += len(missing)
print('%d missing symbols' % total, file=sys.stderr)
