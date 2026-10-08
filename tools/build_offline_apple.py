#!/usr/bin/env python3
"""Vendor pinned iOS-device dependencies; never download dependencies at app build time."""
import concurrent.futures,hashlib,json,pathlib,plistlib,re,shutil,sys,urllib.request,zipfile,time
assets=json.loads(pathlib.Path(sys.argv[1]).read_text())
work=pathlib.Path(sys.argv[2]);work.mkdir(parents=True,exist_ok=True)
base=pathlib.Path(sys.argv[3]);out=pathlib.Path(sys.argv[4])
root=work/'TogetherPoC.swiftpm'
if root.exists():shutil.rmtree(root)
with zipfile.ZipFile(base) as z:z.extractall(work)
vendor=root/'Vendor';vendor.mkdir(exist_ok=True)
cache=work/'downloads';cache.mkdir(exist_ok=True)
def fetch(url,path,checksum=None):
 if not path.exists() or (checksum and hashlib.sha256(path.read_bytes()).hexdigest()!=checksum):
  tmp=path.with_suffix('.part')
  for attempt in range(3):
   try:
    with urllib.request.urlopen(url,timeout=90) as response,tmp.open('wb') as f:shutil.copyfileobj(response,f)
    if checksum:assert hashlib.sha256(tmp.read_bytes()).hexdigest()==checksum,'checksum mismatch'
    tmp.replace(path);break
   except Exception:
    tmp.unlink(missing_ok=True)
    if attempt==2:raise
    time.sleep(attempt+1)
 return path
for name,repo,rev in [('PrismCore','Wenzlik/PrismCore','36c841bc4c8e91fb83532860d2f2f04957d8c0e5'),('MPVKit','mpvkit/MPVKit','288527dffbc6d3e63cce147fc7b520c64a791603')]:
 archive=fetch(f'https://codeload.github.com/{repo}/zip/{rev}',cache/(name+'-source.zip'))
 with zipfile.ZipFile(archive) as z:
  prefix=z.namelist()[0].split('/')[0]+'/'
  for n in z.namelist():
   rel=n.removeprefix(prefix)
   if n.endswith('/') or not rel:continue
   # Package source only: fixtures and VCS caches do not belong in an app.
   if rel.startswith('Sources/') or '/' not in rel:
    p=vendor/name/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(n))
print('Pinned package sources fetched',flush=True)
mpv=vendor/'MPVKit';raw=(mpv/'Package.swift').read_text()
prefix=raw[:raw.index('        .target(\n            name: "_MPVKit-GPL"')]
prefix=re.sub(r'\s*\.library\(\s*name: "MPVKit-GPL",\s*targets: \["_MPVKit-GPL"\]\s*\),','',prefix)
prefix=re.sub(r'^\s*\.target\(name: "Libluajit".*\n','',prefix,flags=re.M)
needed=set(re.findall(r'"([A-Za-z0-9_]+)"',prefix[prefix.index('dependencies: ['):]))
assert {a['name'] for a in assets}.issubset(needed)
frameworks=mpv/'Frameworks';frameworks.mkdir()
def install(a):
 archive=fetch(a['url'],cache/(a['name']+'.zip'),a['sha256'])
 with zipfile.ZipFile(archive) as z:
  info_name=next(n for n in z.namelist() if n.endswith('.xcframework/Info.plist') and n.count('/')==1)
  info=plistlib.loads(z.read(info_name));top=info_name.rsplit('/',1)[0]+'/'
  device=[v for v in info['AvailableLibraries'] if v['SupportedPlatform']=='ios' and not v.get('SupportedPlatformVariant') and 'arm64' in v['SupportedArchitectures']]
  assert len(device)==1,(a['name'],device)
  entry=device[0];slice_prefix=top+entry['LibraryIdentifier']+'/'
  dst=frameworks/(a['name']+'.xcframework');dst.mkdir()
  for n in z.namelist():
   if n.startswith(slice_prefix) and not n.endswith('/'):
    rel=n.removeprefix(top);p=dst/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(n))
    permissions=(z.getinfo(n).external_attr>>16)&0o777
    if permissions:p.chmod(permissions)
  info['AvailableLibraries']=device;(dst/'Info.plist').write_bytes(plistlib.dumps(info))
  assert (dst/entry['LibraryIdentifier']/entry['LibraryPath']).exists()
 print('Device framework verified:',a['name'],flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(install,assets))
binaries=''.join('        .binaryTarget(name: "'+a['name']+'", path: "Frameworks/'+a['name']+'.xcframework"),\n' for a in assets)
(mpv/'Package.swift').write_text(prefix+binaries+'    ]\n)\n')
(vendor/'PrismCore'/'Package.swift').write_text('''// swift-tools-version: 6.0
// TogetherPlayer offline distribution: upstream source unchanged; manifest limited to library.
import PackageDescription
let package=Package(name:"PrismCore",platforms:[.iOS(.v16)],products:[.library(name:"PrismCore",targets:["PrismCore"])],dependencies:[.package(path:"../MPVKit")],targets:[.target(name:"PrismCore",dependencies:[.product(name:"MPVKit",package:"MPVKit")],swiftSettings:[.swiftLanguageMode(.v5)])])
''')
manifest=root/'Package.swift';s=manifest.read_text()
s=s.replace('.package(url:"https://github.com/Wenzlik/PrismCore.git",revision:"36c841bc4c8e91fb83532860d2f2f04957d8c0e5")','.package(path:"Vendor/PrismCore")').replace('.package(url:"https://github.com/mpvkit/MPVKit.git",exact:"1.0.0")','.package(path:"Vendor/MPVKit")')
s=s.replace('displayVersion: "0.2.2", bundleVersion: "22"','displayVersion: "0.2.3", bundleVersion: "23"');manifest.write_text(s)
for f in (root/'Sources/AppModule').glob('*.swift'):f.write_text(f.read_text().replace('0.2.2','0.2.3'))
for f in root.rglob('Package.resolved'):f.unlink()
for f in [manifest,mpv/'Package.swift',vendor/'PrismCore/Package.swift']:
 assert '.package(url:' not in f.read_text() and '.binaryTarget(\n            name:' not in f.read_text()
(root/'OFFLINE-DEPENDENCIES.json').write_text(json.dumps({'frameworks':assets,'platform':'iOS arm64 devices only','sourceRevisions':{'PrismCore':'36c841bc4c8e91fb83532860d2f2f04957d8c0e5','MPVKit':'288527dffbc6d3e63cce147fc7b520c64a791603'},'manifestChanges':'Local dependencies and iOS-device slices; upstream Swift source unchanged'},indent=2))
(root/'READ-ME-FIRST.txt').write_text('TogetherPlayer iPad 0.2.3 offline-dependency trial\nAll package sources and iOS-device frameworks included; no GitHub connection at build time. Requires Swift6-capable Playgrounds. Simulator/Mac slices excluded.\nApple SDK compilation and real playback have not been verified here.\nCreate a room, open Baidu browser, authorize ONLY locally, choose MP4/MKV. Preview Play is local; apply source to Together for room controls. Friend still requires own authorized matching film.\nTarget: Dolby Vision P5 and DD+/EAC3 JOC Atmos, not TrueHD Atmos or complete P7 FEL.\nMKV preparation occurs on the device, loopback only. No video passes through Muse.\nLicense/notice copies accompany Vendor package sources and Licenses folder. PrismCore and MPVKit manifests are adapted for local packaging; all upstream Swift/C sources unchanged.\n')
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(root.rglob('*')):
  if p.is_file():z.write(p,str(p.relative_to(work)))
with zipfile.ZipFile(out) as z:assert z.testzip() is None
meta={'filename':out.name,'size':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'appleCompiled':False,'frameworks':len(assets),'offlineDependencies':True}
out.with_suffix('.json').write_text(json.dumps(meta,indent=2));print(json.dumps(meta),flush=True)
