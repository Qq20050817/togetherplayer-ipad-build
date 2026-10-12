"""Retry SwiftPM's binary artifact cache collision, without hiding other failures."""
import pathlib,re,shutil,subprocess,sys
cache=pathlib.Path.home()/"Library/Caches/org.swift.swiftpm/artifacts"
for attempt in range(3):
 result=subprocess.run(["xcodebuild","-resolvePackageDependencies",*sys.argv[1:]],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 print(result.stdout,flush=True)
 if result.returncode==0:sys.exit(0)
 paths=re.findall(r"(/[^\s']+/org\.swift\.swiftpm/artifacts/[^\s']+) already exists in file system",result.stdout)
 if not paths or attempt==2:sys.exit(result.returncode)
 for raw in set(paths):
  p=pathlib.Path(raw)
  if not p.resolve().is_relative_to(cache.resolve()):raise RuntimeError("Unexpected SwiftPM cache path")
  if p.is_dir():shutil.rmtree(p)
  elif p.exists():p.unlink()
 print("Retrying dependency resolution after removing only conflicting SwiftPM artifacts",flush=True)
