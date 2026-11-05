import subprocess, xml.etree.ElementTree as ET, time
subprocess.run(['adb','shell','am','force-stop','com.android.launcher3'],check=True)
subprocess.run(['adb','shell','uiautomator','dump','/sdcard/emulator-preflight.xml'],check=True)
raw=subprocess.check_output(['adb','exec-out','cat','/sdcard/emulator-preflight.xml'])
try:
    root=ET.fromstring(raw)
except ET.ParseError:
    # A deliberately stopped launcher has no accessibility root before an app
    # opens. App visibility is asserted separately after launch.
    print('No active accessibility window before app launch')
    raise SystemExit(0)
if any("Quickstep isn't responding" in n.get('text','') for n in root.iter('node')):
    close=next(n for n in root.iter('node') if n.get('resource-id')=='android:id/aerr_close')
    import re
    x1,y1,x2,y2=map(int,re.findall(r'\d+',close.get('bounds')))
    subprocess.run(['adb','shell','input','tap',str((x1+x2)//2),str((y1+y2)//2)],check=True)
    time.sleep(1)
    print('Dismissed emulator Quickstep ANR')
