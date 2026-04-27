#!/usr/bin/env python3
import warnings
warnings.filterwarnings("ignore")
"""
Clip – macOS helper
Hotkey → get selected text → choose provider + operation → AI → print result
"""

import queue
import threading
import os
import re
import tkinter as tk
import subprocess
import yaml
from datetime import datetime

import hotkey
import gpt
import fetch
import popup
import bubble


def _strip_markdown(text: str) -> str:
    text = re.sub(r'\*\*(.*?)\*\*', r'\1', text, flags=re.DOTALL)
    text = re.sub(r'__(.*?)__', r'\1', text, flags=re.DOTALL)
    text = re.sub(r'\*(.*?)\*', r'\1', text, flags=re.DOTALL)
    text = re.sub(r'_(.*?)_', r'\1', text, flags=re.DOTALL)
    text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
    return text


def load_config():
    base = os.path.dirname(__file__)
    cfg_path = os.path.join(base, "myconfig.yaml")
    if not os.path.exists(cfg_path):
        cfg_path = os.path.join(base, "config.yaml")
    with open(cfg_path) as f:
        return yaml.safe_load(f)


_queue: queue.Queue = queue.Queue()

SESSION_FILE: str = ""


def init_session():
    global SESSION_FILE
    session_dir = os.path.join(os.path.dirname(__file__), "session")
    os.makedirs(session_dir, exist_ok=True)
    ts = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    SESSION_FILE = os.path.join(session_dir, f"{ts}.md")
    with open(SESSION_FILE, "w") as f:
        f.write(f"# Clip session – {ts}\n\n")
    print(f"[session] {SESSION_FILE}")


def log_session(op_key: str, provider_key: str, source: str,
                input_text: str, result: str, image_b64=None):
    ts = datetime.now().strftime("%H:%M:%S")
    with open(SESSION_FILE, "a") as f:
        f.write(f"## [{ts}] {op_key} / {provider_key} ({source})\n\n")
        if image_b64:
            import base64
            img_name = f"{ts.replace(':', '-')}.png"
            img_path = os.path.join(os.path.dirname(SESSION_FILE), img_name)
            with open(img_path, "wb") as img:
                img.write(base64.b64decode(image_b64))
            f.write(f"**Input:** ![screenshot]({img_name})\n\n")
        else:
            f.write(f"**Input:**\n{input_text.strip()}\n\n")
        f.write(f"**Output:**\n{result.strip()}\n\n")
        f.write("---\n\n")




def on_hotkey():
    text, source, image_b64 = hotkey.get_selected_text()
    print(f"[hotkey] zdroj={source} text: {repr(text[:80])}")
    _queue.put(("show_popup", text, source, image_b64))


def process_gpt(provider_cfg, provider_key, op_key, prompt, text, source, speech, image_b64):
    if not image_b64 and fetch.is_url(text):
        print(f"[fetch] stahuji {text.strip()[:60]}...")
        try:
            text = fetch.fetch_text(text)
            print(f"[fetch] staženo {len(text)} znaků")
        except Exception as e:
            print(f"[fetch] chyba: {e}")

    # Když není žádný kontext, pošli prompt jako user message
    if not text.strip() and not image_b64:
        user_text = prompt
        system = ""
    else:
        user_text = text
        system = prompt

    print(f"[clip] volám {provider_cfg['type']} (image={'ano' if image_b64 else 'ne'})...")
    try:
        result = gpt.ask(provider_cfg, system, user_text, image_b64)
    except Exception as e:
        result = f"Chyba: {e}"
        print(f"[clip] chyba: {e}")

    result = _strip_markdown(result)
    subprocess.run("pbcopy", input=result.encode("utf-8"), check=True)
    log_session(op_key, provider_key, source, text, result, image_b64)
    print(f"\n{'─'*60}\n{result}\n{'─'*60}\n")
    say_proc = None
    if speech:
        say_proc = subprocess.Popen(["say", "-v", "Zuzana", result])
    _queue.put(("show_bubble", result, say_proc))


def main():
    cfg = load_config()
    providers = cfg["providers"]
    default_provider = cfg.get("default_provider", list(providers.keys())[0])
    operations = cfg["operations"]
    hotkey_cfg = cfg.get("hotkey", {"modifiers": ["cmd"], "keys": ["1", "+"]})

    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)

    init_session()
    if "double_tap" in hotkey_cfg:
        keys_str = f"double {hotkey_cfg['double_tap']}"
    else:
        keys_str = "+".join(hotkey_cfg.get("modifiers", [])) + " + [" + ", ".join(hotkey_cfg.get("keys", [])) + "]"
    print(f"Clip běží. Zkratka: {keys_str}  |  default provider: {default_provider}")
    hotkey.start_listener(hotkey_cfg, on_hotkey)

    def poll():
        try:
            msg = _queue.get_nowait()
        except queue.Empty:
            root.after(50, poll)
            return

        if msg[0] == "show_popup":
            text, source, image_b64 = msg[1], msg[2], msg[3]

            if not text.strip() and not image_b64:
                print("[popup] clipboard prázdný, přeskakuji")
                root.after(50, poll)
                return

            if image_b64:
                print("[hotkey] clipboard obsahuje obrázek – posílám do vision API")

            def on_select(op_key, prompt, provider_key, speech, use_clipboard=True):
                print(f"[popup] operace={op_key} provider={provider_key} speech={speech} clipboard={use_clipboard}")
                provider_cfg = providers[provider_key]
                ctx_text = text if use_clipboard else ""
                ctx_image = image_b64 if use_clipboard else None
                threading.Thread(
                    target=process_gpt,
                    args=(provider_cfg, provider_key, op_key, prompt, ctx_text, source, speech, ctx_image),
                    daemon=True,
                ).start()

            def on_cancel():
                print("[popup] zrušeno")

            popup.show_popup(root, operations, providers, default_provider, on_select, on_cancel)

        elif msg[0] == "show_bubble":
            bubble.show_bubble(root, msg[1], msg[2] if len(msg) > 2 else None)

        root.after(50, poll)

    root.after(50, poll)
    root.mainloop()


if __name__ == "__main__":
    main()
