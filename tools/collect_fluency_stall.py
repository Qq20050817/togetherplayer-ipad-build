"""Sample only a stalled synthetic CI test host; never control playback or retry tests."""
import pathlib
import subprocess
import sys
import time

console = pathlib.Path(sys.argv[1])
marker = "Test Case '-[TogetherPoCCoreTests.WholeFilmCloudBudgetTests test449CuesAreAllAnalyzedWithAtMostSixCloudCalls]' started."
seen_at = None
while True:
    text = console.read_text(errors="replace") if console.exists() else ""
    start = text.rfind(marker)
    if start >= 0:
        part = text[start:]
        if "test449CuesAreAllAnalyzedWithAtMostSixCloudCalls]' passed" in part or "test449CuesAreAllAnalyzedWithAtMostSixCloudCalls]' failed" in part:
            break
        if seen_at is None:
            seen_at = time.monotonic()
        if time.monotonic() - seen_at > 20:
            pid = subprocess.check_output(["pgrep", "-n", "-x", "TogetherPoC"], text=True).strip()
            if pid.isdigit():
                output = pathlib.Path("fluency-native-stall.sample.txt")
                result = subprocess.run(["sample", pid, "2", "-file", str(output)], capture_output=True, text=True, timeout=15)
                print("FLUENCY_STALL_SAMPLE", result.returncode, flush=True)
                if output.exists():
                    graph = output.read_text(errors="replace").split("Binary Images:")[0]
                    print(graph[:120_000], flush=True)
            break
    time.sleep(2)
