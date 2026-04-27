import subprocess
import tempfile
import threading
import os


def _reading_timeout(text: str) -> int:
    words = len(text.split())
    return max(5, min(30, round(words / 3)))


def show_bubble(root, text: str, say_proc=None):
    def run():
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False, encoding='utf-8') as f:
            f.write(text)
            tmp = f.name

        script = f'''
set f to open for access POSIX file "{tmp}"
set t to read f as «class utf8»
close access f
do shell script "rm " & quoted form of "{tmp}"
display dialog t buttons {{"OK"}} default button 1 with title "Clip"
'''
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
        if say_proc is not None:
            try:
                say_proc.terminate()
            except Exception:
                pass
        if r.returncode != 0:
            print(f"[clip] bubble chyba: {r.stderr.strip()}")
            try:
                os.unlink(tmp)
            except Exception:
                pass

    threading.Thread(target=run, daemon=True).start()
