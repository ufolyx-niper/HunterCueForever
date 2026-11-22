"""Build and verify a deterministic Forever ZIP; does not install or publish."""
import hashlib,json,zipfile,re
from pathlib import Path
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
NAME='HunterCueForever'
source=ROOT/NAME
toc=(source/(NAME+'.toc')).read_text(encoding='utf-8')
version=re.search(r'^## Version: (.+)$',toc,re.M)[1].strip()
assert version=='1.0.0' and '## Interface: 16001' in toc
assert 'Dependencies:' not in toc
files=[line.strip() for line in toc.splitlines() if line.strip() and not line.startswith('#')]
lua=LuaRuntime();assert lua.eval('_VERSION')=='Lua 5.1'
for f in files:
    assert f.endswith('.lua') and (source/f).is_file()
    lua.execute('assert(loadstring(...))',(source/f).read_text(encoding='utf-8'))
assert 'ns.version = "'+version+'"' in (source/'Data.lua').read_text(encoding='utf-8')
members=files+[NAME+'.toc','README.txt','LICENSE']
assert set(p.name for p in source.iterdir())==set(members), 'Unexpected runtime directory member'
dist=ROOT/'dist';dist.mkdir(exist_ok=True)
filename=f'{NAME}-{version}-forever.zip';archive=dist/filename
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for member in sorted(members):
        info=zipfile.ZipInfo(NAME+'/'+member,(2026,11,22,0,0,0))
        info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16
        z.writestr(info,(source/member).read_bytes())
sha=lambda b:hashlib.sha256(b).hexdigest()
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert set(z.namelist())=={NAME+'/'+f for f in members}
    for f in members:assert z.read(NAME+'/'+f)==(source/f).read_bytes()
    manifest={f:sha(z.read(f)) for f in z.namelist()}
release={'releases':[{'name':NAME,'version':version,'filename':filename,'nolib':False,
    'metadata':[{'flavor':'forever','interface':16001}]}]}
(dist/'release.json').write_text(json.dumps(release,indent=2)+'\n',encoding='utf-8')
result={'version':version,'filename':filename,'sha256':sha(archive.read_bytes()),'members':manifest,
    'releaseMetadata':release,'validation':'Lua 5.1 syntax; TOC file list; exact member/source equality; ZIP CRC; SHA256'}
(ROOT/'package-manifest.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,indent=2))
