import subprocess,time,pathlib,re,hashlib,zipfile,json
old='dev.together.poc';preview='dev.together.poc.cleanup068'
def adb(*args):
 return subprocess.check_output(['adb',*args],text=True,stderr=subprocess.STDOUT).strip()
print(adb('install','-r','old/TogetherPlayer-Android-0.6.7-InstantControls.apk'))
adb('shell','run-as',old,'mkdir','-p','files')
adb('shell','run-as',old,'touch','files/parallel-data-preserved')
old_dump=adb('shell','dumpsys','package',old)
assert 'versionCode=67 ' in old_dump
old_uid=re.search(r'userId=(\d+)',old_dump).group(1)
print(adb('install','-r','parallel-universal.apk'))
new_dump=adb('shell','dumpsys','package',preview)
assert 'versionCode=68 ' in new_dump
new_uid=re.search(r'userId=(\d+)',new_dump).group(1)
assert new_uid!=old_uid
started=adb('shell','am','start','-W','-n',preview+'/dev.together.poc.MainActivity')
assert 'Status: ok' in started,started
for attempt in range(12):
 adb('shell','uiautomator','dump','/sdcard/parallel-window.xml')
 xml=adb('shell','cat','/sdcard/parallel-window.xml')
 if 'package="'+preview+'"' in xml and ('一起看' in xml or '房间 / 设置' in xml):break
 time.sleep(1)
else:raise AssertionError('Preview activity did not render real watch interface')
adb('shell','run-as',old,'cat','files/parallel-data-preserved')
assert re.search(r'userId=(\d+)',adb('shell','dumpsys','package',old)).group(1)==old_uid
assert 'versionCode=67 ' in adb('shell','dumpsys','package',old)
pathlib.Path('delivery').mkdir(exist_ok=True)
pathlib.Path('delivery/INSTALL-PARALLEL.txt').write_text('Actual emulator installation verified: original 0.6.7 and preview 0.6.8 coexist under separate UIDs; original private data marker preserved; preview launches and renders watch interface.\nPreview app ID: '+preview+'\nPreview label: TogetherPlayer预览\nJoin the room again in preview. The original app and its data are retained.\n')
print('PARALLEL INSTALL PASSED: separate UIDs, old version/data preserved, real preview UI rendered')
