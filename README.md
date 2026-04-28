# Clip

macOS nástroj pro zpracování obsahu schránky pomocí AI. Zkopíruješ text (nebo obrázek), stiskneš zkratku, vybereš akci — překlad, shrnutí, dotaz, extrakce klíčů — a výsledek se zobrazí přímo v plovoucím panelu.

Existují dvě varianty — **Python** (rychlé nasazení, bez kompilace) a **Swift** (nativní macOS app, aktivně vyvíjená).

---

## Varianty

| | Python (`python/`) | Swift (`swift/`) |
|---|---|---|
| Spuštění | `python3 main.py` | Nativní .app |
| Hotkey | double-tap Ctrl | Cmd+Shift+Space (konfigurovatelné) |
| UI | tkinter dialogy | Nativní SwiftUI overlay |
| Konfigurace | `myconfig.yaml` | Keychain (klíče) + JSON soubory |
| Sync | ruční kopírování | Složka na iDrive / OneDrive |
| Session log | ne | volitelné — Markdown soubory per den |
| Stav | legacy | aktivně vyvíjená |

---

## Rychlý start – Swift (Clip.app)

### GitHub Release (doporučeno)

1. Stáhni nejnovější `Clip.app.zip` z [Releases](../../releases)
2. Rozbal → přesuň `Clip.app` do `/Applications`
3. Spusť Clip — ikona se objeví v menu baru
4. **Nastavení (⚙) → Providers** → přidej API provider (Anthropic / OpenAI / Azure / vlastní)
5. **Nastavení → Actions** → uprav akce nebo přidej nové
6. Volitelně: **Nastavení → General → Config folder** → vyber sdílenou složku (iDrive / OneDrive) pro synchronizaci mezi zařízeními

### Ze zdrojového kódu

```bash
open swift/Clip.xcodeproj
# Xcode: Product → Run (⌘R)
```

---

## Použití

1. Zkopíruj text (`⌘C`) nebo obrázek
2. Stiskni globální zkratku (výchozí: `Cmd+Shift+Space`)
3. Overlay se otevře s obsahem schránky
4. Zvol akci tlačítkem nebo klávesou `1`–`9`
5. Výsledek zobrazí v panelu → `⌘C` zkopíruje, `✕` nebo `Esc` zavře

---

## Klíčové funkce Swift varianty

- **Plovoucí panel** — zobrazí se přes všechny aplikace, neruší workflow
- **OCR** — pokud je ve schránce obrázek, automaticky se rozezná text
- **URL fetch** — pokud je ve schránce URL, stáhne obsah stránky před zpracováním
- **Inline nastavení** — ⚙ otevře nastavení v tom samém panelu
- **Providers** — Anthropic (direct + Azure), OpenAI (direct + Azure), vlastní OpenAI-compatible endpoint; klíče bezpečně v Keychain
- **Akce** — plně konfigurovatelné systémové prompty s proměnnými `{{datum}}`, `{{jazyk}}`, `{{kontext}}`
- **Session log** — volitelné zaznamenávání do Markdown souborů (per den, kompatibilní s Obsidian)
- **Read aloud** — výsledek přečte TTS (preferuje českou kvalitu Premium/Enhanced)
- **Ignore clipboard** — spustí akci jen s promptem bez kontextu ze schránky
- **Config folder** — sdílení agentů a providerů přes iDrive / OneDrive (providers.json + agents.json)
- **Spuštění při přihlášení** (Login Item)
- **Světlý/tmavý režim** — sleduje nastavení systému

---

## Konfigurace přes sdílenou složku

Pokud nastavíš **Config folder**, Clip při startu načte:

| Soubor | Obsah |
|---|---|
| `providers.json` | Endpointy a API klíče providerů |
| `agents.json` | Definice akcí / agentů |

Tím lze synchronizovat konfiguraci mezi více Macy. Vzor: `providers.example.json` v repozitáři.

Session logy (pokud zapnuto) se zapisují do **Session folder** jako `YYYY-MM-DD.md` — každý výsledek jako sekce `## HH:MM — Agent`.

---

## Struktura repozitáře

```
clip/
├── README.md
├── Clip.app.zip                    # nejnovější release build
│
├── python/                         # Python varianta (legacy)
│   ├── main.py
│   ├── config.yaml                 # šablona (placeholders)
│   └── myconfig.yaml               # GITIGNORED – reálné klíče
│
└── swift/                          # Swift/SwiftUI varianta
    ├── Clip.xcodeproj/
    └── Sources/Clip/
        ├── Config/                 # AppConfig, ConfigStore, SessionStore, KeychainStore
        ├── Context/                # ContextResolver (text + OCR)
        ├── Engine/                 # ActionEngine, WebFetcher, SpeechPlayer
        ├── Providers/              # AnthropicProvider, OpenAIProvider, ProviderFactory
        └── UI/                     # OverlayView, SettingsView, OverlayWindowController
```

---

## Co patří do gitu a co ne

| Soubor | Git | Důvod |
|---|---|---|
| `python/config.yaml` | ✅ | pouze placeholders |
| `python/myconfig.yaml` | ❌ gitignored | reálné API klíče |
| `Clip.app.zip` | ✅ | release build |
| `providers.example.json` | ✅ | šablona bez secrets |
| `providers.json` (v Config folder) | ❌ mimo repo | reálné endpointy + klíče |
| Session logy (v Session folder) | ❌ mimo repo | osobní záznamy |
| API klíče | ❌ nikdy | uloženy v Keychain |
