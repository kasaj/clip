import subprocess
import threading


def _reading_timeout(text: str) -> int:
    words = len(text.split())
    return max(5, min(30, round(words / 3)))


def show_bubble(root, text: str):
    timeout = _reading_timeout(text)
    safe = text.replace('"', '\\"').replace("'", "\\'")
    script = f'display dialog "{safe}" buttons {{"OK"}} default button 1 giving up after {timeout} with title "ClipGPT"'
    threading.Thread(
        target=lambda: subprocess.run(["osascript", "-e", script], capture_output=True),
        daemon=True,
    ).start()
