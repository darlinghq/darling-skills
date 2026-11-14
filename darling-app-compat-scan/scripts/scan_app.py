#!/usr/bin/env python3
"""Statically compare a macOS app's imports against an installed Darling.

usage: scan_app.py <app dir or Mach-O> [--arch x86_64] [--root /usr/local/libexec/darling]
                   [--json out.json] [--max 40]

Walks every Mach-O file under the app (main executable, frameworks, bundles,
plugins, helpers), takes the chosen architecture slice, and for every system
library it links (/System/..., /usr/lib/...) checks whether Darling installs
that library and exports each imported symbol (following LC_REEXPORT_DYLIB).
Weak imports are reported separately: a missing weak symbol does not stop
loading, it only becomes NULL at runtime.

Needs llvm-objdump and llvm-nm on the host. Only reads binary metadata (load
commands and symbol tables); it does not disassemble anything.
"""
import argparse, collections, functools, json, os, re, struct, subprocess, sys

def is_macho(path):
    try:
        with open(path, 'rb') as f:
            head = f.read(8)
    except OSError:
        return False
    if len(head) < 8:
        return False
    if head[:4] in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe'):
        return True
    if head[:4] == b'\xca\xfe\xba\xbe':
        # Java class files share this magic; a fat header has a small arch count
        return struct.unpack('>I', head[4:8])[0] < 20
    return False

def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout

CPU = {'i386': 7, 'x86_64': 0x01000007, 'arm64': 0x0100000c}

def has_arch(path, arch):
    with open(path, 'rb') as f:
        head = f.read(8 + 20 * 20)
    if head[:4] == b'\xca\xfe\xba\xbe':
        n = struct.unpack('>I', head[4:8])[0]
        cpus = [struct.unpack('>i', head[8 + 20 * i:12 + 20 * i])[0] for i in range(n)]
    else:
        cpus = [struct.unpack('<i', head[4:8])[0]]
    return CPU[arch] in cpus

def dylibs_used(path, arch):
    libs = []
    for line in run('llvm-objdump', '--macho', '--dylibs-used', '--arch=' + arch, path).splitlines()[1:]:
        line = line.strip()
        if line and not line.endswith(':'):
            libs.append(line.split(' (')[0])
    return libs

UNDEF = re.compile(r'\s*\(undefined\)( weak)? external (\S+) \(from (\S+)\)')

def imports(path, arch):
    res = []
    for line in run('llvm-nm', '-m', '-u', '--arch=' + arch, path).splitlines():
        m = UNDEF.match(line)
        if m:
            res.append((m.group(2), bool(m.group(1)), m.group(3)))
    return res

EXPORT = re.compile(r'\s*\S*\s*\((?!undefined)[^)]*\) (?:weak )?external (?:\[[^]]*\] )?(\S+)')

def short_names(install_name):
    """Names llvm-nm -m may print in "(from X)" for a library."""
    b = os.path.basename(install_name)
    return {b, re.sub(r'\.dylib$', '', b), re.sub(r'(\.[A-Z0-9]+)?\.dylib$', '', b)}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('app')
    ap.add_argument('--arch', default='x86_64')
    ap.add_argument('--root', default='/usr/local/libexec/darling')
    ap.add_argument('--json')
    ap.add_argument('--max', type=int, default=40, help='missing symbols listed per library')
    a = ap.parse_args()

    files = []
    if os.path.isfile(a.app):
        files = [a.app]
    else:
        for r, _, fs in os.walk(a.app):
            for f in fs:
                p = os.path.join(r, f)
                if not os.path.islink(p) and is_macho(p):
                    files.append(p)
    files = [p for p in files if has_arch(p, a.arch)]

    users = collections.defaultdict(set)        # install name -> files linking it
    imp = collections.defaultdict(dict)         # short name -> symbol -> [weak?, files]
    for p in files:
        rel = os.path.relpath(p, a.app) if os.path.isdir(a.app) else p
        for lib in dylibs_used(p, a.arch):
            if lib.startswith(('/System/', '/usr/lib/')):
                users[lib].add(rel)
        for sym, weak, frm in imports(p, a.arch):
            e = imp[frm].setdefault(sym, [True, set()])
            e[0] = e[0] and weak                # strong if any file imports it strongly
            e[1].add(rel)

    def real(install_name):
        q = a.root + install_name
        return q if os.path.exists(q) else None

    @functools.lru_cache(None)
    def exports(install_name):
        q = real(install_name)
        if not q:
            return None
        # defined exports plus indirect ones ("_bzero (for __platform_bzero)"),
        # which a plain --defined-only listing leaves out
        s = set()
        for l in run('llvm-nm', '-m', '--arch=' + a.arch, q).splitlines():
            m = EXPORT.match(l)
            if m:
                s.add(m.group(1))
        hdr = run('llvm-objdump', '--macho', '--private-headers', '--arch=' + a.arch, q)
        for m in re.finditer(r'cmd LC_REEXPORT_DYLIB\n.*\n\s+name (\S+)', hdr):
            sub = exports(m.group(1))
            if sub:
                s |= sub
        return frozenset(s)

    report = []
    for lib in sorted(users):
        syms = {}
        for n in short_names(lib):
            syms.update(imp.get(n, {}))
        ex = exports(lib)
        missing = sorted((s, w, sorted(f)) for s, (w, f) in syms.items() if ex is None or s not in ex)
        report.append({'library': lib, 'present': ex is not None, 'users': sorted(users[lib]),
                       'imports': len(syms),
                       'missing_strong': [(s, f) for s, w, f in missing if not w],
                       'missing_weak': [(s, f) for s, w, f in missing if w]})

    print('%d Mach-O files with an %s slice, %d system libraries' % (len(files), a.arch, len(report)))
    # libraries with strong gaps first: those are the ones that stop loading
    for r in sorted(report, key=lambda r: (r['present'], -len(r['missing_strong']), r['library'])):
        ms, mw = r['missing_strong'], r['missing_weak']
        if r['present'] and not ms and not mw:
            continue
        print('%s %s  users=%d imports=%d missing strong=%d weak=%d' % (
            'OK     ' if r['present'] else 'MISSING', r['library'], len(r['users']), r['imports'], len(ms), len(mw)))
        for s, f in ms[:a.max]:
            print('      %s  (%s%s)' % (s, f[0], ', +%d' % (len(f) - 1) if len(f) > 1 else ''))
        for s, f in mw[:max(0, a.max - len(ms))]:
            print('      %s  [weak] (%s)' % (s, f[0]))
    clean = [r['library'] for r in report if r['present'] and not r['missing_strong'] and not r['missing_weak']]
    print('fully satisfied: %d libraries' % len(clean))
    if a.json:
        json.dump({'arch': a.arch, 'files': len(files), 'libraries': report}, open(a.json, 'w'), indent=1)

if __name__ == '__main__':
    sys.exit(main())
