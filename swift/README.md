# JZLLMContext (Swift varianta)

Nativní macOS menu bar aplikace. Zkopíruješ text nebo obrázek, stiskneš globální zkratku a vybraná akce (překlad, shrnutí, dotaz, …) zpracuje obsah přes AI a vrátí výsledek v overlay panelu.

---

## Požadavky

- macOS 13 Ventura nebo novější
- Xcode 15+
- API klíč alespoň jednoho providera

---

## Instalace a sestavení

```bash
open swift/JZLLMContext.xcodeproj
# Xcode: Product → Run  (⌘R)
```

Aplikace se spustí jako menu bar ikona. Při prvním spuštění požádá o přístup k systémovým klávesovým zkratkám.

---

## Konfigurace

### 1. API klíče (Keychain)

Otevři **Nastavení → Providery** a zadej klíče pro providery, které chceš používat:

| Provider | Co zadat |
|---|---|
| Claude (Azure AI Foundry) | API klíč + endpoint URL |
| Claude (direct) | API klíč (api.anthropic.com) |
| ChatGPT (Azure) slot 1/2 | API klíč + deployment URL |
| OpenAI (direct) | API klíč (api.openai.com) |

API klíče se ukládají do **macOS Keychain** — nikdy do souboru ani do iDrive.

### 2. Agenti (akce)

Aplikace obsahuje výchozí agenty: **CZ, EN, ASK, KEY, WEB, M365**.

Upravuj je v **Nastavení → Akce**. Každý agent má vlastní:
- název, systémový prompt, provider, model
- teplotu (0.0–2.0) a max. počet tokenů
- volbu auto-copy+close

Export / import agentů: tlačítka dole v záložce Akce. Formát je `agents.json` — tento soubor je bez secrets a lze ho sdílet přes git nebo iDrive.

### 3. Složka konfigurace (iDrive / OneDrive / lokální)

**Nastavení → Obecné → Složka konfigurace**

Když nastavíš složku (např. `~/iDrive/Clip/`), aplikace:
- čte agenty z `{složka}/agents.json`
- čte endpointy z `{složka}/providers.json`
- zapisuje změny zpět do těchto souborů
- vytvoří `{složka}/session/` pro budoucí perzistenci

**Výhoda:** Na novém Macu stačí nastavit stejnou iDrive složku — agenti a endpointy jsou okamžitě k dispozici. API klíče zadáš znovu přes Nastavení → Providery (Keychain je lokální).

---

## Struktura konfiguračních souborů

```
~/iDrive/Clip/             ← konfigurace (volitelné, mimo repo)
├── agents.json            ← agenti (prompty, provider, model) — bez API klíčů
├── providers.json         ← endpointy Azure / custom — bez API klíčů
└── session/               ← session data (auto-vytvořeno)

~/Library/Application Support/JZLLMContext/
└── config.json            ← lokální nastavení (hotkey, preferences, cesta ke složce)
```

`providers.json` šablona je v repozitáři jako `swift/providers.example.json`.

---

## Nasazení na nový Mac

1. Stáhni a sestav aplikaci z `swift/JZLLMContext.xcodeproj`
2. Spusť aplikaci
3. **Nastavení → Obecné → Složka konfigurace** → nastav na iDrive / OneDrive složku
   - Agenti a endpointy se načtou automaticky z `agents.json` a `providers.json`
4. **Nastavení → Providery** → zadej API klíče (jen jednou na každém zařízení)
5. Hotovo

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
│   ├── HistoryStore.swift     # in-memory historie výsledků
│   └── ModelFetcher.swift     # fetch dostupných modelů z API
├── Providers/
│   ├── LLMProvider.swift      # protocol + LLMError
│   ├── AzureAnthropicProvider.swift  # Claude via Azure (SSE streaming)
│   ├── AnthropicProvider.swift       # Claude direct (SSE streaming)
│   ├── OpenAIProvider.swift          # OpenAI / Azure OpenAI (SSE streaming)
│   └── ProviderFactory.swift         # vytváří providera pro danou akci
├── UI/
│   ├── OverlayView.swift      # hlavní overlay panel (clipboard, akce, výsledek)
│   ├── SettingsView.swift     # nastavení (obecné, akce, providery)
│   └── …
├── Context/
│   └── ContextResolver.swift  # čte clipboard (text / OCR z obrázku)
└── Engine/
    └── ActionEngine.swift     # řídí streaming a stav odpovědi
```

**Tok dat:**
1. Hotkey → `ContextResolver` přečte clipboard
2. Uživatel vybere akci v `OverlayView`
3. `ProviderFactory` vytvoří správného providera
4. Provider streamuje odpověď přes SSE → `ActionEngine` akumuluje chunks
5. `OverlayView` zobrazuje výsledek průběžně

**Config folder sync** (ConfigStore):
- `init`: načti `config.json` → pokud `configFolderPath` nastaven, overlay z `agents.json` + `providers.json`
- `update(_:)`: ulož `config.json` + synchronizuj folder soubory

---

## Hotkey konfigurace

Výchozí: **Cmd+Shift+Space**. Měníš v Nastavení → Obecné → Globální zkratka.

Python varianta používá double-tap Ctrl — tyto dvě zkratky se navzájem nevylučují.
