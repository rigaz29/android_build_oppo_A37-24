#!/bin/bash
# Bandingkan atribut tiap project yang kita ganti dengan entri hulunya.
# Dibuat setelah tiga kali salah menyalin groups/linkfile.
cd /root/a37-24/src/lineage-24 || exit 1
python3 - <<'PY'
import subprocess, xml.etree.ElementTree as ET, glob
def load(f):
    d={}
    for x in ET.parse(f).getroot().iter('project'):
        d[x.get('path') or x.get('name')] = x
    return d
up={}
for f in ['.repo/manifests/default.xml'] + glob.glob('.repo/manifests/snippets/*.xml'):
    up.update(load(f))
loc = ET.parse('.repo/local_manifests/A37-24.xml').getroot()
bad=0
for p in loc.iter('project'):
    path=p.get('path')
    u=up.get(path)
    if u is None: continue
    for attr in ('groups',):
        a,b = p.get(attr), u.get(attr)
        if a!=b: print(f"  BEDA {path:34} {attr}: lokal={a!r} hulu={b!r}"); bad+=1
    lf_l=[l.get('src') for l in p.iter('linkfile')]
    lf_u=[l.get('src') for l in u.iter('linkfile')]
    if lf_l!=lf_u: print(f"  BEDA {path:34} linkfile: lokal={lf_l} hulu={lf_u}"); bad+=1
print(f"  {'semua cocok dengan hulu' if not bad else str(bad)+' selisih'}")
PY
