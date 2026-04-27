# Clip

Nástroj pro macOS, který zpracovává obsah schránky (text nebo obrázek) pomocí AI modelů. Stiskneš zkratku, vybereš akci — překlad, shrnutí, dotaz, extrakce klíčových informací — a výsledek se zobrazí přímo v overlay panelu nebo dialogu.

Existují dvě varianty — Python (rychlé nasazení, bez kompilace) a Swift (nativní macOS app, aktivně vyvíjená).

---

## Varianty

| | Python (`python/`) | Swift (`swift/`) |
|---|---|---|
| Spuštění | `python3 main.py` | Nativní .app (Xcode build) |
| Hotkey | double-tap Ctrl | Cmd+Shift+Space (konfigurovatelné) |
| UI | tkinter + osascript dialogy | Nativní SwiftUI overlay |
| Konfigurace | `myconfig.yaml` (vše vč. klíčů) | Keychain (klíče) + JSON soubory |
| Sync mezi zařízeními | ruční kopírování souboru | Složka na iDrive / OneDrive |
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

## Rychlý start – Swift (JZLLMContext)

1. Otevři `swift/JZLLMContext.xcodeproj` v Xcode, Build & Run
2. **Nastavení → Providery** → zadej API klíče (ukládají se do Keychain)
3. **Nastavení → Obecné → Složka konfigurace** → nastav na iDrive / OneDrive složku

Po nastavení složky se `agents.json` a `providers.json` čtou z ní a zapisují zpět — konfigurace je automaticky synchronizována mezi zařízeními.

Viz [swift/README.md](swift/README.md) pro podrobný návod.

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
└── swift/                          # Swift/SwiftUI varianta (JZLLMContext)
    ├── JZLLMContext.xcodeproj/
    ├── Sources/
    │   └── JZLLMContext/
    │       ├── Config/             # AppConfig, ConfigStore, KeychainStore…
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
| `swift/providers.json` (v iDrive složce) | ❌ gitignored | reálné endpointy |
| API klíče | ❌ nikdy | Keychain — žádný soubor |
| `~/Library/Application Support/JZLLMContext/config.json` | ❌ | lokální, mimo repo |
