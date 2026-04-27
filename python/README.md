# Clip – Python varianta

Jednoduchá varianta bez kompilace. Spouští se přímo z terminálu, UI je kombinace tkinter okna a osascript dialogů.

---

## Požadavky

- macOS + Python 3.9+
- API klíč alespoň jednoho providera

---

## Instalace

```bash
cd python
pip3 install -r requirements.txt
cp config.yaml myconfig.yaml
```

Otevři `myconfig.yaml` a vyplň:
- API klíče pro providery, které chceš používat
- endpointy (pro Azure providery)
- `default_provider` — výchozí provider v UI

---

## Spuštění

```bash
python3 main.py
```

Aplikace běží na pozadí a čeká na globální zkratku (výchozí: double-tap Ctrl).

---

## Konfigurace (`myconfig.yaml`)

Soubor obsahuje vše na jednom místě — providers, agenty i hotkey. Je **gitignored** (obsahuje reálné API klíče). V repozitáři je pouze `config.yaml` se šablonou (placeholders).

### Providery

```yaml
providers:
  Claude (Azure):
    type: azure_anthropic
    api_key: YOUR_AZURE_KEY
    endpoint: https://YOUR_RESOURCE.services.ai.azure.com/anthropic
    model: claude-sonnet-4-6

  Claude:
    type: anthropic
    api_key: YOUR_ANTHROPIC_KEY
    model: claude-sonnet-4-6

  ChatGPT (Azure):
    type: azure
    api_key: YOUR_AZURE_KEY
    endpoint: https://YOUR_RESOURCE.cognitiveservices.azure.com
    deployment: gpt-4o
    api_version: 2025-01-01-preview

default_provider: Claude (Azure)
```

Typy providerů: `azure_anthropic`, `anthropic`, `azure`, `openai`.

### Hotkey

```yaml
hotkey:
  double_tap: ctrl   # double-tap Ctrl
  interval: 0.4      # max. interval mezi tappy (sekundy)
```

### Agenti (operace)

```yaml
operations:
  cz:
    label: CZ
    prompt: "Jsi editor textu. ..."
  en:
    label: EN
    prompt: "You are a text editor. ..."
```

Každý agent má `label` (zobrazovaný název) a `prompt` (systémový prompt).

---

## Použití

1. Zkopíruj text nebo obrázek do schránky
2. Stiskni globální zkratku (double-tap Ctrl)
3. Otevře se popup okno:
   - Vyber provider (lišta nahoře)
   - Zapni/vypni **Speech** (přečtení nahlas) a **Clipboard** (použít obsah schránky)
   - Klikni na agenta nebo použij **+** pro přidání komentáře
4. Výsledek se zobrazí v dialogu (tlačítko OK zavře)

### Bez kontextu ze schránky

Odškrtni **Clipboard** — agent dostane pouze tvůj dotaz, bez obsahu schránky. Hodí se pro přímé dotazy.

### Vlastní prompt

Tlačítko **PROMPT** otevře pole pro libovolný prompt poslaný přes vybraný provider.

---

## Nasazení na nový Mac

1. `git clone https://github.com/kasaj/clip`
2. `cd clip/python && pip3 install -r requirements.txt`
3. Zkopíruj svůj `myconfig.yaml` (např. z iDrive nebo zálohovaného umístění)
4. `python3 main.py`

`myconfig.yaml` není v gitu — uchovávej ho na bezpečném místě (iDrive, šifrovaný backup).

---

## Rozdíly oproti Swift variantě

| | Python | Swift |
|---|---|---|
| Instalace | pip + python3 | Xcode build |
| UI | tkinter + osascript | nativní SwiftUI |
| API klíče | v YAML souboru (gitignored) | Keychain (bezpečnější) |
| Sync | ruční kopírování myconfig.yaml | iDrive složka (agents.json + providers.json) |
| OCR | přes Vision API v cloudu | lokální Vision framework |
| Hotkey | double-tap Ctrl | Cmd+Shift+Space (konfigurovatelné) |
| Vývoj | legacy, opravy chyb | aktivní vývoj |
