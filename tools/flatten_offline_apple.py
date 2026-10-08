#!/usr/bin/env python3
"""Flatten vendor packages into the App Playground package; preserve SDK binaries."""
import pathlib,sys,json,zipfile,re,shutil,hashlib
base=pathlib.Path(sys.argv[1]);work=pathlib.Path(sys.argv[2]);out=pathlib.Path(sys.argv[3]);work.mkdir(parents=True,exist_ok=True)
root=work/'TogetherPoC.swiftpm'
if root.exists():shutil.rmtree(root)
with zipfile.ZipFile(base) as z:z.extractall(work)
manifest=root/'Package.swift';s=manifest.read_text();prefix=s[:s.index(' dependencies: [')]
prefix=prefix.replace('displayVersion: "0.2.3", bundleVersion: "23"','displayVersion: "0.2.4", bundleVersion: "24"')
assets=json.loads((root/'OFFLINE-DEPENDENCIES.json').read_text())['frameworks'];names=[a['name'] for a in assets]
frameworks=['AVFoundation','CoreAudio','AudioToolbox','CoreVideo','CoreFoundation','CoreMedia','Metal','VideoToolbox'];libraries=['bz2','iconv','expat','resolv','xml2','z','c++']
linker=', '.join('.linkedFramework("'+n+'")' for n in frameworks)+', '+', '.join('.linkedLibrary("'+n+'")' for n in libraries)
s=prefix+' targets: [\n'
s+='  .executableTarget(name:"AppModule", dependencies:["PrismCore","Libavutil"],path:"Sources/AppModule"),\n'
s+='  .target(name:"PrismCore",dependencies:['+','.join('"'+n+'"' for n in names)+'],path:"Vendor/PrismCore/Sources/PrismCore",swiftSettings:[.swiftLanguageMode(.v5)],linkerSettings:['+linker+']),\n'
for n in names:s+='  .binaryTarget(name:"'+n+'",path:"Vendor/MPVKit/Frameworks/'+n+'.xcframework"),\n'
s+=' ],\n swiftLanguageVersions:[.v5]\n)\n';manifest.write_text(s)
for p in (root/'Vendor').rglob('Package.swift'):p.unlink()
for p in (root/'Sources/AppModule').glob('*.swift'):p.write_text(p.read_text().replace('0.2.3','0.2.4'))
(root/'READ-ME-FIRST.txt').write_text('TogetherPlayer iPad 0.2.4 single-package offline trial\nNo package dependencies: PrismCore is an internal Swift target, all 28 SDK components are local binary targets in the SAME App Playground. No GitHub download during build. Requires Swift6-capable Playgrounds and a real iPad/iPhone.\nAvoids the user-confirmed Playgrounds prohibition of local package dependencies. Empty MPVKit C shim targets are not built. Existing native SDK/system framework link dependencies retained.\nApple SDK build and real MKV/Dolby playback remain unverified. No claim of successful device compilation.\nKeep Vendor folder intact. Open TogetherPoC.swiftpm in Playgrounds, create a room, open Baidu source browser, authorize on device and preview MP4/MKV. Token is never shared.\nTarget: Dolby Vision P5 and DD+/EAC3 JOC Atmos. TrueHD Atmos and full P7 FEL are NOT preserved. Friend still needs an independently authorized matching film.\nLicenses/notice copies accompany Vendor and Licenses. Upstream Swift/C sources and SDK binaries unchanged; manifests adapted/flattened for distribution.\n')
assert len(list(root.rglob('Package.swift')))==1
assert '.package(' not in s and '.product(' not in s
for p in re.findall(r'path:\s*"([^"]+)"',s):assert (root/p).exists(),p
imports={m for p in (root/'Vendor/PrismCore/Sources/PrismCore').rglob('*.swift') for m in re.findall(r'^import (Lib[A-Za-z0-9_]+)',p.read_text(),re.M)};assert imports.issubset(set(names))
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(root.rglob('*')):
  if p.is_file():z.write(p,str(p.relative_to(work)))
with zipfile.ZipFile(out) as z:assert z.testzip() is None
meta={'filename':out.name,'size':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'packages':1,'packageDependencies':0,'binaryTargets':len(names),'appleCompiled':False};out.with_suffix('.json').write_text(json.dumps(meta,indent=2));print(json.dumps(meta),flush=True)
