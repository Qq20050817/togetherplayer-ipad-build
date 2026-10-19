"""Sample only a stalled synthetic CI test host; never control playback or retry tests."""
import pathlib
import re
import subprocess
import sys
import time

console = pathlib.Path(sys.argv[1])
events = re.compile(r"Test Case '(-\[TogetherPoCCoreTests\.[^\]]+\])' (started|passed|failed)")
seen_at = None
active = None
while True:
    text = console.read_text(errors="replace") if console.exists() else ""
    found = list(events.finditer(text))
    current = found[-1] if found else None
    name = current.group(1) if current and current.group(2) == "started" else None
    if name != active:
        active = name
        seen_at = time.monotonic() if active else None
    if active:
        if seen_at is None:
            seen_at = time.monotonic()
        if time.monotonic() - seen_at > 20:
            pid = subprocess.check_output(["pgrep", "-n", "-x", "TogetherPoC"], text=True).strip()
            if pid.isdigit():
                output = pathlib.Path("fluency-native-stall.sample.txt")
                result = subprocess.run(["sample", pid, "2", "-file", str(output)], capture_output=True, text=True, timeout=15)
                print("FLUENCY_STALL_SAMPLE", active, result.returncode, flush=True)
                if output.exists():
                    graph = output.read_text(errors="replace").split("Binary Images:")[0]
                    print(graph[:120_000], flush=True)
            break
    time.sleep(2)
