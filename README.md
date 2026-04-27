# Clip

Nástroj pro macOS, který zpracovává obsah schránky (text nebo obrázek) pomocí AI modelů. Stiskneš zkratku, vybereš akci — překlad, shrnutí, dotaz, extrakce klíčových informací — a výsledek se zobrazí přímo v overlay panelu.

Existují dvě varianty — Python (rychlé nasazení, bez kompilace) a Swift (nativní macOS app, aktivně vyvíjená).

---

## Varianty

| | Python (`python/`) | Swift (`swift/`) |
|---|---|---|
| Spuštění | `python3 main.py` | Nativní .app (Xcode build nebo GitHub Release) |
| Hotkey | double-tap Ctrl | Cmd+Shift+Space (konfigurovatelné) |
| UI | tkinter + osascript dialogy | Nativní SwiftUI overlay |
| Konfigurace | `myconfig.yaml` (vše vč. klíčů) | Keychain (klíče) + JSON soubory |
| Sync mezi zařízeními | ruční kopírování souboru | Složka na iDrive / OneDrive |
| Session log | ne | volitelné — JSON soubory v session/ složce |
| Stav | legacy | aktivně vyvíjená |

Obě varianty lze provozovat současně — nemají konflikt hotkey (různé mechanismy).

---

## Rychlý start – Python

```bash
cd python
pip3 install -r requirements.txt
cp config.yaml myconfig.yaml   # vyplň API klíče a endpointy
python3 main.py
```

Viz [python/README.md](python/README.md) pro podrobný návod.

---

## Rychlý start – Swift (Clip.app)

### Nejrychlejší: GitHub Release (předkompilovaná .app)

1. Stáhni nejnovější `Clip-swift-*.zip` z [Releases](../../releases)
2. Rozbal → přesuň `Clip.app` do `/Applications`
3. Zkopíruj `Clip-config/` na iDrive / OneDrive (nebo libovolnou lokální složku)
4. Spusť Clip → **Nastavení → Obecné → Složka konfigurace** → vyber svou složku
5. Uprav `providers.json` dle vzoru `providers.example.json` (endpointy + API klíče)
6. Restart Clip — vše se načte automaticky

### Ze zdrojového kódu (Xcode):

```bash
open swift/JZLLMContext.xcodeproj
# Xcode: Product → Run  (⌘R)
```

Viz [swift/README.md](swift/README.md) pro podrobný návod.

---

## Klíčové funkce Swift varianty

- **Globální zkratka** (Cmd+Shift+Space) → přečte clipboard (text nebo OCR z obrázku)
- **Agenti / akce** — šest výchozích (CZ, EN, ASK, KEY, WEB, M365), plně editovatelné
- **Složka konfigurace** — synchronizace agentů a endpointů přes iDrive / OneDrive
- **Session log** — volitelné zaznamenávání operací do JSON souborů (`session/`)
- **Spuštění při přihlášení** (Login Item)
- **Podpora providerů**: Claude (Azure AI Foundry + direct), ChatGPT (Azure slot 1/2), OpenAI (direct), vlastní OpenAI-compatible

---

## Struktura repozitáře

```
clip/
├── README.md                       # tento soubor
├── .gitignore
│
├── python/                         # Python varianta
│   ├── main.py                     # vstupní bod
│   ├── popup.py                    # UI okno
│   ├── bubble.py                   # dialog s výsledkem
│   ├── gpt.py                      # volání AI providerů
│   ├── fetch.py                    # stahování URL obsahu
│   ├── hotkey.py                   # globální zkratka
│   ├── requirements.txt
│   ├── config.yaml                 # PUBLIC – šablona (placeholders)
│   └── myconfig.yaml               # GITIGNORED – reálné klíče a endpointy
│
└── swift/                          # Swift/SwiftUI varianta (Clip.app)
    ├── JZLLMContext.xcodeproj/
    ├── Sources/
    │   └── JZLLMContext/
    │       ├── Config/             # AppConfig, ConfigStore, SessionStore…
    │       ├── Providers/          # OpenAI, Anthropic, AzureAnthropic…
    │       ├── UI/                 # OverlayView, SettingsView…
    │       └── …
    ├── agents.json                 # PUBLIC – agenti / akce (žádné secrets)
    ├── providers.example.json      # PUBLIC – šablona endpointů
    └── README.md
```

---

## Co patří do gitu a co ne

| Soubor | Git | Důvod |
|---|---|---|
| `python/config.yaml` | ✅ | pouze placeholders |
| `python/myconfig.yaml` | ❌ gitignored | obsahuje reálné API klíče |
| `swift/agents.json` | ✅ | jen prompty a metadata, žádné secrets |
| `swift/providers.example.json` | ✅ | šablona s placeholders |
| `providers.json` (v iDrive složce) | ❌ mimo repo | reálné endpointy + API klíče |
| `session/*.json` (v iDrive složce) | ❌ mimo repo | logy operací |
| API klíče | ❌ nikdy | Keychain — žádný soubor v repo |
| `~/Library/Application Support/Clip/config.json` | ❌ | lokální, mimo repo |
