# Clip — Swift varianta

Nativní macOS menu bar aplikace. Zkopíruješ text nebo obrázek, stiskneš globální zkratku a vybraná akce (překlad, shrnutí, dotaz, …) zpracuje obsah přes AI a vrátí výsledek v overlay panelu.

---

## Požadavky

- macOS 15 Sequoia nebo novější
- Xcode 16+ (pro sestavení ze zdrojů)
- API klíč alespoň jednoho providera

---

## Instalace a sestavení

### Možnost A — předkompilovaná .app (GitHub Release)

1. Stáhni nejnovější `Clip-swift-*.zip` z [Releases](https://github.com/kasaj/clip/releases)
2. Rozbal ZIP — obsahuje:
   - `Clip.app` — spustitelná aplikace
   - `Clip-config/agents.json` — výchozí agenti
   - `Clip-config/providers.example.json` — šablona připojení
3. Přesuň `Clip.app` do `/Applications`
4. Pokračuj krokem 2 v sekci **Konfigurace**

### Možnost B — sestavení ze zdrojového kódu

```bash
open swift/JZLLMContext.xcodeproj
# Xcode: Product → Run  (⌘R)
# nebo: Product → Archive → Distribute → Copy App
```

Aplikace se spustí jako menu bar ikona. Při prvním spuštění požádá o přístup k systémovým klávesovým zkratkám.

---

## Konfigurace

### 1. Složka konfigurace (iDrive / OneDrive / lokální)

**Nastavení → Obecné → Složka konfigurace**

Nejprve nastav složku pro sdílení konfigurace. Aplikace v ní bude číst a ukládat:
- `agents.json` — agenti (prompty, provider, model)
- `providers.json` — endpointy a API klíče
- `session/` — logy operací (volitelné)

Složku umísti na iDrive nebo OneDrive pro automatický sync mezi zařízeními.

### 2. API klíče a endpointy

**Možnost A — přes Nastavení → Providery** (GUI):

Zadej klíče a endpointy pro providery, které chceš používat. Klíče se uloží do macOS Keychain. Pokud máš nastavenou složku konfigurace, klíče se také zapíší do `providers.json`.

**Možnost B — přes providers.json** (doporučeno při iDrive sync):

Zkopíruj a vyplň šablonu:
```bash
cp Clip-config/providers.example.json ~/iDrive/Clip-config/providers.json
# Vyplň endpointy a API klíče
```

Při příštím spuštění Clip načte `providers.json` a automaticky uloží klíče do Keychain.

| Provider | Co zadat |
|---|---|
| Claude (Azure AI Foundry) | API klíč + endpoint URL |
| Claude (direct) | API klíč (api.anthropic.com) |
| ChatGPT (Azure) slot 1/2 | API klíč + deployment URL |
| OpenAI (direct) | API klíč (api.openai.com) |
| Vlastní OpenAI-compatible | Base URL (+ volitelný klíč) |

### 3. Agenti (akce)

Výchozí agenti: **CZ, EN, ASK, KEY, WEB, M365**.

Upravuj v **Nastavení → Akce**. Každý agent má vlastní:
- název, systémový prompt, provider, model
- teplotu (0.0–2.0) a max. počet tokenů
- volbu auto-copy+close

Export / import agentů: tlačítka dole v záložce Akce. Formát je `agents.json` — tento soubor neobsahuje secrets a lze ho sdílet přes git nebo iDrive.

---

## Session log (zaznamenávání operací)

**Nastavení → Obecné → Zaznamenávat operace (session log)**

Když je tato volba zapnuta, každá úspěšně dokončená operace se uloží jako JSON soubor:

```
{configFolder}/session/2026-04-27_23-50-00_CZ.json
```

Pokud není nastavena složka konfigurace, soubory se ukládají do:
```
~/Library/Application Support/Clip/session/
```

**Formát záznamu:**
```json
{
  "agent": "CZ",
  "durationSeconds": 2.3,
  "input": "vstupní text...",
  "model": "claude-sonnet-4-6",
  "output": "výsledný text...",
  "provider": "azure_anthropic",
  "timestamp": "2026-04-27T23:50:00Z"
}
```

Session log je **volitelný** — ve výchozím stavu je vypnutý. Umožňuje audit operací, analýzu využití nebo přehled toho, co aplikace zpracovala.

---

## Struktura konfiguračních souborů

```
~/iDrive/Clip-config/          ← konfigurace (volitelné, mimo repo)
├── agents.json                ← agenti (prompty, provider, model) — bez API klíčů
├── providers.json             ← endpointy + API klíče — PRIVÁTNÍ (není v gitu)
└── session/                   ← JSON záznamy operací (auto-vytvořeno, volitelné)
    ├── 2026-04-27_10-30-00_CZ.json
    ├── 2026-04-27_10-31-15_EN.json
    └── …

~/Library/Application Support/Clip/
└── config.json                ← lokální nastavení (hotkey, preferences, cesta ke složce)
```

`providers.json` šablona je v repozitáři jako `swift/providers.example.json`.

---

## Nasazení na nový Mac

### Pokud máš iDrive složku (`Clip-config/`) z předchozího zařízení:

1. Sestav nebo nainstaluj aplikaci
2. Spusť aplikaci
3. **Nastavení → Obecné → Složka konfigurace** → vyber svou `Clip-config/` složku na iDrive
4. Hotovo — agenti, endpointy i API klíče se načtou automaticky z `providers.json`

### První instalace (bez iDrive složky):

1. Sestav nebo nainstaluj aplikaci
2. Spusť aplikaci
3. **Nastavení → Providery** → zadej API klíče a endpointy
4. **Nastavení → Obecné → Složka konfigurace** → nastav iDrive složku (např. `~/Library/Mobile Documents/com~apple~CloudDocs/Clip-config/`)
5. Aplikace okamžitě zapíše `agents.json` a `providers.json` (vč. klíčů) do té složky
6. Na dalším Macu stačí bod 1–3

---

## Podporované providery

| Provider | Typ | Poznámka |
|---|---|---|
| `azure_anthropic` | Claude via Azure AI Foundry | Anthropic API formát, `api-key` header |
| `anthropic` | Claude direct | api.anthropic.com, `x-api-key` header |
| `azure_openai` | ChatGPT via Azure | slot 1 |
| `azure_openai_2` | ChatGPT via Azure | slot 2 |
| `openai` | OpenAI direct | api.openai.com |
| `custom_openai` | Vlastní OpenAI-compatible | Ollama, LM Studio, … |

---

## Architektura (pro vývojáře)

```
Sources/JZLLMContext/
├── Config/
│   ├── AppConfig.swift        # datové modely (Action, ProviderType, ProvidersConfig)
│   ├── ConfigStore.swift      # singleton, load/save config.json + folder sync
│   ├── KeychainStore.swift    # CRUD pro API klíče v Keychain
│   ├── HistoryStore.swift     # in-memory historie výsledků (overlay panel)
│   ├── SessionStore.swift     # zápis session logů na disk (volitelné)
│   └── ModelFetcher.swift     # fetch dostupných modelů z API
├── Providers/
│   ├── LLMProvider.swift              # protocol + LLMError
│   ├── AzureAnthropicProvider.swift   # Claude via Azure (SSE streaming)
│   ├── AnthropicProvider.swift        # Claude direct (SSE streaming)
│   ├── OpenAIProvider.swift           # OpenAI / Azure OpenAI (SSE streaming)
│   └── ProviderFactory.swift          # vytváří providera pro danou akci
├── UI/
│   ├── OverlayView.swift      # hlavní overlay panel (clipboard, akce, výsledek)
│   ├── SettingsView.swift     # nastavení (obecné, akce, providery)
│   ├── AboutView.swift        # O aplikaci
│   ├── HotkeyRecorderView.swift
│   └── OverlayWindowController.swift
├── Context/
│   └── ContextResolver.swift  # čte clipboard (text / OCR z obrázku)
└── Engine/
    └── ActionEngine.swift     # řídí streaming, stav odpovědi a session log
```

**Tok dat:**
1. Hotkey → `ContextResolver` přečte clipboard
2. Uživatel vybere akci v `OverlayView`
3. `ProviderFactory` vytvoří správného providera
4. Provider streamuje odpověď přes SSE → `ActionEngine` akumuluje chunks
5. `OverlayView` zobrazuje výsledek průběžně
6. Po dokončení: `SessionStore` zapíše záznam (pokud je `recordSessions = true`)

**Config folder sync** (ConfigStore):
- `init`: načti `config.json` → pokud `configFolderPath` nastaven, overlay z `agents.json` + `providers.json`
- `update(_:)`: ulož `config.json` + synchronizuj folder soubory

---

## Hotkey konfigurace

Výchozí: **Cmd+Shift+Space**. Měníš v Nastavení → Obecné → Globální zkratka.

Python varianta používá double-tap Ctrl — tyto dvě zkratky se navzájem nevylučují.

---

## Verze

| Verze | Co přibylo |
|---|---|
| 0.23 | Session log — volitelné zaznamenávání operací do JSON souborů |
| 0.22 | Claude via Azure AI Foundry, Složka konfigurace, přejmenování na Clip |
| 0.21 | Podpora modelů, import/export agentů, Login Item |
