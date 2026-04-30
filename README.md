# Clip

macOS nástroj pro zpracování obsahu schránky pomocí AI. Zkopíruješ text (nebo obrázek), stiskneš zkratku, vybereš akci — překlad, shrnutí, dotaz, extrakce klíčů — a výsledek se zobrazí přímo v plovoucím panelu.

![Clip 0.57](screen.png)

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
4. **Pravý klik na ikonu → Settings → Providers** → přidej API provider
5. **Settings → Actions** → použij výchozí akce níže nebo přidej vlastní
6. Volitelně: **Settings → General → Config folder** → vyber sdílenou složku pro synchronizaci mezi zařízeními

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
5. Výsledek se zobrazí v panelu → `⌘C` zkopíruje, `✕` nebo `Esc` zavře

---

## Klíčové funkce Swift varianty

- **Plovoucí panel** — zobrazí se přes všechny aplikace, neruší workflow
- **OCR** — pokud je ve schránce obrázek, automaticky se rozezná text
- **URL fetch** — pokud je ve schránce URL, stáhne obsah stránky před zpracováním
- **Providers** — Anthropic, OpenAI, Azure, vlastní OpenAI-compatible endpoint; klíče bezpečně v Keychain
- **Akce** — plně konfigurovatelné systémové prompty s proměnnými `{{datum}}`, `{{jazyk}}`, `{{kontext}}`
- **History** — přehled posledních výsledků, kliknutím znovu zobrazíš
- **Session log** — volitelné zaznamenávání do Markdown souborů (per den, kompatibilní s Obsidian)
- **Read aloud** — výsledek přečte TTS
- **Ignore clipboard** — spustí akci jen s promptem bez kontextu ze schránky
- **Config folder** — sdílení agentů a providerů přes iDrive / OneDrive
- **Spuštění při přihlášení** (Login Item)
- **Světlý/tmavý režim** — sleduje nastavení systému

---

## Výchozí konfigurace

Hotové JSON soubory ke stažení a použití rovnou jako výchozí bod. Zkopíruj je do své Config folder, vyplň API klíč a URL.

### providers.json — [stáhnout](swift/providers.example.json)

Definuje poskytovatele LLM. Příklad pro **custom OpenAI-compatible endpoint** (Azure OpenAI Responses API):

```json
[
  {
    "api_key": "YOUR_API_KEY",
    "base_url": "https://YOUR-RESOURCE.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview",
    "default": true,
    "enabled": true,
    "id": "CC83BAEA-C671-4D29-84CF-BA9673BD50F7",
    "model": "gpt-4o-mini",
    "name": "Azure OpenAI",
    "provider": "custom"
  }
]
```

> `id` musí být platné UUID — při přidání přes UI se vygeneruje automaticky. Pokud soubor vytváříš ručně, vygeneruj si UUID např. přes `uuidgen` v Terminálu.

### agents.json — [stáhnout](swift/agents.example.json)

Pět výchozích akcí. Pole `provider` musí odpovídat `id` z `providers.json`.

```json
[
  {
    "name": "CZ",
    "systemPrompt": "Jsi profesionální editor textu. Oprav gramatiku nebo přelož do češtiny. Zachovej původní význam, styl, tón a strukturu vět. Výstup bez formátování, odrážek, tučného písma, komentářů, úvodů, emoji ani otázek. ",
    "provider": "CC83BAEA-C671-4D29-84CF-BA9673BD50F7",
    "model": "", "maxTokens": 4096, "temperature": 0.7,
    "autoCopyClose": "useGlobal", "enabled": true,
    "id": "25AD72BC-BE98-4404-A3EC-341388EDEAE0"
  },
  {
    "name": "EN",
    "systemPrompt": "You are a professional copyeditor. Correct the English grammar or translate it into English. Preserve the original meaning, style, tone, and sentence structure. The output should contain only the final text—no comments, formatting, or explanations.",
    "provider": "CC83BAEA-C671-4D29-84CF-BA9673BD50F7",
    "model": "", "maxTokens": 4096, "temperature": 0.7,
    "autoCopyClose": "useGlobal", "enabled": true,
    "id": "C9A43498-2BD1-4FF8-B8B8-6A2E616E08F4"
  },
  {
    "name": "ASK",
    "systemPrompt": "Jsi odborný vykladač vstupních dat. Vysvětluješ význam slov a termínů, odpovídáš na faktické dotazy s pochopením kontextu. Odpovědi jsou neutrální, bez zaujetí, iluzí a hodnocení. Využíváš ověřené zdroje. Výstup bez formátování, odrážek, tučného písma, komentářů, úvodů, emoji ani otázek. ",
    "provider": "CC83BAEA-C671-4D29-84CF-BA9673BD50F7",
    "model": "", "maxTokens": 4096, "temperature": 0.7,
    "autoCopyClose": "useGlobal", "enabled": true,
    "id": "CFAAADF8-349D-47D1-9B05-BB0F87D5B473"
  },
  {
    "name": "KEY",
    "systemPrompt": "Jsi extraktor informací ze vstupních dat (text, obrázek, web). Na první řádek napiš jednověté shrnutí ve formátu: Shrnutí: <text> per vstupní data (text, url, etc.). Pokud je vstup rozsáhlý, pokračuj odstavcem s rozšířeným shrnutím hlavních myšlenek. Poté vypiš každou klíčovou informaci (fakta, čísla, hodnoty, data, názvy, URL adresy, závěry) na samostatný řádek. Čísla a hodnoty zachovej přesně dle originálu. Výstup bez formátování, odrážek, tučného písma, komentářů, úvodů, emoji ani otázek. ",
    "provider": "CC83BAEA-C671-4D29-84CF-BA9673BD50F7",
    "model": "", "maxTokens": 4096, "temperature": 0.7,
    "autoCopyClose": "useGlobal", "enabled": true,
    "id": "BF59579D-A3C7-411A-BE56-DCC1E098D10F"
  },
  {
    "name": "SUM",
    "systemPrompt": "Jsi summarizační agent. Ze vstupních dat extrahuj klíčové a zajímavé informace jako ucelenou pravdivou odpověď ve formě shrnutí (koncetrát). Výstup tvoří pouze odrážky bez dalšího formátování, tučného písma, emoji, úvodů ani komentářů.",
    "provider": "CC83BAEA-C671-4D29-84CF-BA9673BD50F7",
    "model": "", "maxTokens": 4096, "temperature": 0.7,
    "autoCopyClose": "useGlobal", "enabled": true,
    "id": "D2CBBDBD-3AF0-471D-AC09-5A096C0B2335"
  }
]
```

> Akce s `"model": ""` dědí model z providera. Chceš-li pro konkrétní akci jiný model, vyplň ho zde (např. `"gpt-4o"`).

---

## Konfigurace přes sdílenou složku

Pokud nastavíš **Config folder** (Settings → General), Clip při startu načte:

| Soubor | Obsah |
|---|---|
| `providers.json` | Endpointy a API klíče providerů |
| `agents.json` | Definice akcí / agentů |

Tím lze synchronizovat konfiguraci mezi více Macy přes iDrive, OneDrive nebo jiný cloud.

Session logy (pokud zapnuto) se zapisují do **Session folder** jako `YYYY-MM-DD.md` — každý výsledek jako sekce `## HH:MM — Agent`. Kompatibilní s Obsidian.

---

## Struktura repozitáře

```
clip/
├── README.md
├── screen.png                          # screenshot aplikace
├── Clip.app.zip                        # nejnovější release build
│
├── python/                             # Python varianta (legacy)
│   ├── main.py
│   ├── config.yaml                     # šablona (placeholders)
│   └── myconfig.yaml                   # GITIGNORED – reálné klíče
│
└── swift/                              # Swift/SwiftUI varianta
    ├── Clip.xcodeproj/
    ├── providers.example.json          # šablona providers.json
    ├── agents.example.json             # šablona agents.json (výchozí akce)
    └── Sources/Clip/
        ├── Config/                     # AppConfig, ConfigStore, SessionStore, KeychainStore
        ├── Context/                    # ContextResolver (text + OCR)
        ├── Engine/                     # ActionEngine, WebFetcher, SpeechPlayer
        ├── Providers/                  # AnthropicProvider, OpenAIProvider, ProviderFactory
        └── UI/                         # OverlayView, SettingsView, OverlayWindowController
```

---

## Co patří do gitu a co ne

| Soubor | Git | Důvod |
|---|---|---|
| `python/config.yaml` | ✅ | pouze placeholders |
| `python/myconfig.yaml` | ❌ gitignored | reálné API klíče |
| `Clip.app.zip` | ✅ | release build |
| `providers.example.json` | ✅ | šablona bez secrets |
| `agents.example.json` | ✅ | výchozí akce bez secrets |
| `providers.json` (v Config folder) | ❌ mimo repo | reálné endpointy + klíče |
| Session logy (v Session folder) | ❌ mimo repo | osobní záznamy |
| API klíče | ❌ nikdy | uloženy v Keychain |
