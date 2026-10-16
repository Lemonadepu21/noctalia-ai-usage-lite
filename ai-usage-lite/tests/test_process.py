"""Exercise the actual installed process guards without calling the CLI or network."""
import subprocess
import tempfile
import time
from pathlib import Path

with tempfile.TemporaryDirectory() as directory:
    lock = str(Path(directory) / "query.lock")
    ready = Path(directory) / "ready"
    holder = subprocess.Popen([
        "flock", "-n", "-E", "75", lock, "timeout", "-k", "0.2s", "0.8s",
        "sh", "-c", 'touch "$1"; exec sleep 10', "test", str(ready),
    ])
    try:
        deadline = time.monotonic() + 2
        while not ready.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert ready.exists(), "lock holder failed to start"
        blocked = subprocess.run(["flock", "-n", "-E", "75", lock, "true"], check=False)
        assert blocked.returncode == 75, "a second process acquired the same lock"
        assert holder.wait(timeout=3) == 124, "hung process did not time out"
        assert subprocess.run(["flock", "-n", "-E", "75", lock, "true"], check=False).returncode == 0
    finally:
        if holder.poll() is None:
            holder.terminate()
            holder.wait(timeout=3)
print("PASS: real flock exclusion, real timeout, lock released after timeout; no CLI calls")
