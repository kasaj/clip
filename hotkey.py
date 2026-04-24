import time
import threading
import subprocess
import base64
from typing import Optional, Tuple
from pynput import keyboard
from pynput.keyboard import Key, Controller
from AppKit import NSEvent, NSLeftMouseDownMask

from AppKit import (NSPasteboard, NSPasteboardTypePNG, NSPasteboardTypeTIFF,
                    NSBitmapImageRep, NSPNGFileType)

_kb = Controller()

_MODIFIER_MAP = {
    "cmd":   {Key.cmd, Key.cmd_l, Key.cmd_r},
    "ctrl":  {Key.ctrl, Key.ctrl_l, Key.ctrl_r},
    "shift": {Key.shift, Key.shift_l, Key.shift_r},
    "alt":   {Key.alt, Key.alt_l, Key.alt_r},
}

# fn key has no Key enum in pynput – detect by vk=63
_FN_VK = 63

# macOS ISO keyboard: vk → char when key.char is None (modifier held)
_VK_CHAR_MAP = {
    10: "<",
    50: "§",
}


def _clipboard_read() -> str:
    return subprocess.run("pbpaste", capture_output=True).stdout.decode("utf-8")


def _clipboard_image_b64() -> Optional[str]:
    pb = NSPasteboard.generalPasteboard()

    data = pb.dataForType_(NSPasteboardTypePNG)
    if data and len(data) > 0:
        return base64.b64encode(bytes(data)).decode("utf-8")

    data = pb.dataForType_(NSPasteboardTypeTIFF)
    if data and len(data) > 0:
        rep = NSBitmapImageRep.imageRepWithData_(data)
        if rep:
            png_data = rep.representationUsingType_properties_(NSPNGFileType, None)
            if png_data:
                return base64.b64encode(bytes(png_data)).decode("utf-8")

    return None


def get_selected_text() -> Tuple[str, str, Optional[str]]:
    img = _clipboard_image_b64()
    if img:
        return "", "image", img

    before = _clipboard_read()
    with _kb.pressed(Key.cmd):
        _kb.press("c")
        _kb.release("c")
    time.sleep(0.15)

    img = _clipboard_image_b64()
    if img:
        return "", "image", img

    after = _clipboard_read()
    if after != before:
        return after, "selection", None
    return before, "clipboard", None


def start_listener(hotkey_cfg: dict, callback):
    # ── double-tap mode ───────────────────────────────────
    double_tap_key = hotkey_cfg.get("double_tap")
    if double_tap_key:
        interval = hotkey_cfg.get("interval", 0.4)
        tap_keys = set(_MODIFIER_MAP.get(double_tap_key, set()))
        last_tap = [0.0]

        def on_press(key):
            if key in tap_keys:
                now = time.time()
                if now - last_tap[0] <= interval:
                    last_tap[0] = 0.0
                    callback()
                else:
                    last_tap[0] = now

        def on_release(key):
            pass

    # ── modifier + key mode ───────────────────────────────
    else:
        modifiers = hotkey_cfg.get("modifiers", [])
        trigger_chars = set(hotkey_cfg.get("keys", []))
        use_fn = "fn" in modifiers
        other_mods = [m for m in modifiers if m != "fn"]

        held = set()
        fn_held = False

        def on_press(key):
            nonlocal fn_held
            vk = getattr(key, "vk", None)
            if vk == _FN_VK:
                fn_held = True
                return
            held.add(key)
            fn_ok = (not use_fn) or fn_held
            mods_ok = all(
                any(k in held for k in _MODIFIER_MAP[m])
                for m in other_mods
            )
            char = getattr(key, "char", None) or _VK_CHAR_MAP.get(vk)
            if fn_ok and mods_ok and char in trigger_chars:
                callback()

        def on_release(key):
            nonlocal fn_held
            vk = getattr(key, "vk", None)
            if vk == _FN_VK:
                fn_held = False
            else:
                held.discard(key)

    shift_held = [False]
    _shift_keys = {Key.shift, Key.shift_l, Key.shift_r}

    orig_on_press = on_press
    orig_on_release = on_release

    def combined_on_press(key):
        if key in _shift_keys:
            shift_held[0] = True
        orig_on_press(key)

    def combined_on_release(key):
        if key in _shift_keys:
            shift_held[0] = False
        orig_on_release(key)

    def run():
        with keyboard.Listener(on_press=combined_on_press, on_release=combined_on_release):
            threading.Event().wait()

    threading.Thread(target=run, daemon=True).start()

    def _run_mouse():
        def handler(event):
            if shift_held[0]:
                callback()
        NSEvent.addGlobalMonitorForEventsMatchingMask_handler_(
            NSLeftMouseDownMask, handler
        )
        import AppKit
        AppKit.NSRunLoop.currentRunLoop().run()

    threading.Thread(target=_run_mouse, daemon=True).start()
