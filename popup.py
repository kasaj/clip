import os
import subprocess
import tkinter as tk
from AppKit import NSApp
import yaml

NSWindowCollectionBehaviorMoveToActiveSpace = 1 << 1
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "config.yaml")

BTN = dict(bg="#313244", fg="#cdd6f4", activebackground="#45475a",
           activeforeground="#ffffff", relief="flat",
           font=("SF Pro Display", 12), pady=6, cursor="hand2")


def _move_to_active_space(win):
    win.update_idletasks()
    for w in NSApp.windows():
        w.setCollectionBehavior_(NSWindowCollectionBehaviorMoveToActiveSpace)
    NSApp.activateIgnoringOtherApps_(True)


def _save_operations(operations: dict):
    with open(CONFIG_PATH) as f:
        cfg = yaml.safe_load(f)
    cfg["operations"] = {k: {"label": v["label"], "prompt": v["prompt"]} for k, v in operations.items()}
    with open(CONFIG_PATH, "w") as f:
        yaml.dump(cfg, f, allow_unicode=True, default_flow_style=False, sort_keys=False)


def _ask(prompt: str, default: str = "") -> str:
    """Native macOS text input dialog. Returns stripped value or '' on cancel."""
    safe_prompt = prompt.replace('"', '\\"')
    safe_default = default.replace('"', '\\"').replace("\n", "\\n")
    script = f'text returned of (display dialog "{safe_prompt}" default answer "{safe_default}" with title "Clip")'
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def _show_agent_dialog(root, operations: dict, rebuild_fn, key: str = None):
    """Edit existing (key given) or create new agent via native dialogs."""
    import threading
    editing = key is not None

    def run():
        default_label = operations[key]["label"] if editing else ""
        default_key = key if editing else ""
        default_prompt = operations[key]["prompt"] if editing else ""

        label = _ask("Název (label):", default_label)
        if not label:
            return
        new_key = _ask("Klíč (id):", default_key)
        if not new_key:
            return
        new_key = new_key.lower().replace(" ", "_")
        prompt = _ask("Prompt:", default_prompt)
        if not prompt:
            return

        if editing and key != new_key and key in operations:
            del operations[key]
        operations[new_key] = {"label": label, "prompt": prompt}
        _save_operations(operations)
        root.after(0, rebuild_fn)

    threading.Thread(target=run, daemon=True).start()


def show_popup(root, operations: dict, providers: dict, default_provider: str, on_select, on_cancel):
    win = tk.Toplevel(root)
    win.title("Clip")
    win.resizable(False, False)
    win.attributes("-topmost", True)
    win.configure(bg="#1e1e2e", padx=20, pady=16)

    sw = win.winfo_screenwidth()
    sh = win.winfo_screenheight()

    provider_var = tk.StringVar(value=default_provider)
    speech_var = tk.BooleanVar(value=False)
    clipboard_var = tk.BooleanVar(value=True)

    # ── Provider ──────────────────────────────────────────
    tk.Label(win, text="Provider:", bg="#1e1e2e", fg="#6c7086",
             font=("SF Pro Display", 10)).pack(anchor="w")
    pf = tk.Frame(win, bg="#1e1e2e")
    pf.pack(fill="x", pady=(2, 4))
    for key in providers:
        tk.Radiobutton(pf, text=key, variable=provider_var, value=key,
                       bg="#1e1e2e", fg="#cdd6f4", selectcolor="#313244",
                       activebackground="#1e1e2e", activeforeground="#cdd6f4",
                       font=("SF Pro Display", 11)).pack(side="left", padx=(0, 12))

    cf = tk.Frame(win, bg="#1e1e2e")
    cf.pack(anchor="w", pady=(2, 8))
    tk.Checkbutton(cf, text="♪ Přečíst nahlas", variable=speech_var,
                   bg="#1e1e2e", fg="gray", selectcolor="#313244",
                   activebackground="#1e1e2e", activeforeground="gray",
                   font=("SF Pro Display", 11), cursor="hand2").pack(side="left", padx=(0, 12))
    tk.Checkbutton(cf, text="≡ Use clipboard", variable=clipboard_var,
                   bg="#1e1e2e", fg="gray", selectcolor="#313244",
                   activebackground="#1e1e2e", activeforeground="gray",
                   font=("SF Pro Display", 11), cursor="hand2").pack(side="left")

    tk.Frame(win, bg="#313244", height=1).pack(fill="x", pady=(0, 10))

    # ── Operations ────────────────────────────────────────
    tk.Button(win, text="— Agents —", bg="#1e1e2e", disabledforeground="gray",
              relief="flat", bd=0, highlightthickness=0,
              font=("SF Pro Display", 10), state="disabled").pack(fill="x")
    agents_lf = tk.Frame(win, bg="#2d2d42", padx=8, pady=8)
    agents_lf.pack(fill="x", pady=(0, 8))
    ops_frame = agents_lf

    def pick(key, prompt):
        win.destroy()
        on_select(key, prompt, provider_var.get(), speech_var.get(), clipboard_var.get())

    def delete_op(key, row_frame):
        if len(operations) <= 1:
            return
        del operations[key]
        _save_operations(operations)
        row_frame.destroy()

    def rebuild_ops():
        for w in ops_frame.winfo_children():
            w.destroy()
        for key, op in operations.items():
            _build_op_row(key, op)

    ICON_BTN = dict(bg="#2d2d42", fg="gray", relief="flat",
                    font=("SF Pro Display", 12), pady=6, cursor="hand2", padx=6)

    def _pick_with_comment(key, base_prompt):
        import threading
        def run():
            comment = _ask(f"Přidat komentář k {operations[key]['label']}:", "")
            combined = base_prompt + ("\n\nDodatečný kontext od uživatele: " + comment if comment else "")
            root.after(0, lambda: (win.destroy(), on_select(key, combined, provider_var.get(), speech_var.get(), clipboard_var.get())))
        threading.Thread(target=run, daemon=True).start()

    def _build_op_row(key, op):
        row = tk.Frame(ops_frame, bg="#2d2d42")
        row.pack(fill="x", pady=2)
        tk.Button(row, text="✕",
                  command=lambda k=key, r=row: delete_op(k, r),
                  **ICON_BTN).pack(side="left", padx=(0, 2))
        tk.Button(row, text=op["label"],
                  command=lambda k=key, p=op["prompt"]: pick(k, p),
                  padx=12, **BTN).pack(side="left", fill="x", expand=True)
        tk.Button(row, text="+",
                  command=lambda k=key, p=op["prompt"]: _pick_with_comment(k, p),
                  **ICON_BTN).pack(side="left", padx=(2, 0))
        tk.Button(row, text="✎",
                  command=lambda k=key: _show_agent_dialog(root, operations, rebuild_ops, k),
                  **ICON_BTN).pack(side="left", padx=(2, 0))

    for key, op in operations.items():
        _build_op_row(key, op)

    def open_custom_prompt():
        import threading
        def run():
            prompt = _ask("Vlastní prompt:")
            if prompt:
                prov = provider_var.get()
                sp = speech_var.get()
                use_cb = clipboard_var.get()
                root.after(0, lambda: (win.destroy(), on_select("custom", prompt, prov, sp, use_cb)))
        threading.Thread(target=run, daemon=True).start()

    # ── Bottom bar ────────────────────────────────────────
    tk.Frame(win, bg="#313244", height=1).pack(fill="x", pady=(10, 6))
    bottom = tk.Frame(win, bg="#1e1e2e")
    bottom.pack(fill="x")
    tk.Button(bottom, text="+ agent",
              command=lambda: _show_agent_dialog(root, operations, rebuild_ops),
              bg="#1e1e2e", fg="#a6e3a1", activebackground="#1e1e2e",
              activeforeground="#a6e3a1", relief="flat",
              font=("SF Pro Display", 11), cursor="hand2").pack(side="left")
    tk.Button(bottom, text="PROMPT", command=open_custom_prompt,
              padx=12, **BTN).pack(side="right")

    def cancel(event=None):
        win.destroy()
        on_cancel()

    win.bind("<Escape>", cancel)
    win.protocol("WM_DELETE_WINDOW", cancel)
    _move_to_active_space(win)
    win.update_idletasks()
    w = win.winfo_width()
    h = win.winfo_height()
    sw = win.winfo_screenwidth()
    sh = win.winfo_screenheight()
    win.geometry(f"+{(sw - w) // 2}+{(sh - h) // 2}")
    win.lift()
    win.focus_force()
