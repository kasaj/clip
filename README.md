# Clip

Clip je macOS nástroj, který zachytí označený text nebo obsah schránky, pošle ho do AI (Claude / ChatGPT) a výsledek zkopíruje zpět do schránky.

---

## Funkce

- **Dvojité stisknutí Ctrl** spustí popup s výběrem operace
- Operace: překlad/oprava do **CZ / EN**, stručná odpověď **ASK**, extrakce klíčových informací **KEY**, shrnutí webové stránky **WEB**
- **Vlastní prompt** — napíšeš co chceš
- Podpora pro **obrázky** ze schránky (vision API)
- Automatické stažení obsahu URL před odesláním
- Přečtení výsledku nahlas (hlas Zuzana)
- Správa operací přímo v okně (přidat / upravit / smazat)
- Logování každé session do složky `session/`
- Podpora více AI providerů: Anthropic Claude, Azure OpenAI, Azure Claude

---

## Instalace

### Požadavky

- macOS
- Python 3.9+
- Povolení **Accessibility** v Nastavení systému → Soukromí a zabezpečení → Accessibility (pro zachytávání kláves)

### Instalace závislostí

```bash
pip install -r requirements.txt
```

### Konfigurace

```bash
cp config.example.yaml config.yaml
```

Otevři `config.yaml` a vyplň své API klíče a endpointy.

#### Typy providerů

| type | Popis |
|------|-------|
| `anthropic` | Přímé API Anthropic |
| `azure` | Azure OpenAI (GPT-4o apod.) |
| `azure_anthropic` | Claude přes Azure AI Foundry |

### Spuštění

```bash
python3 main.py
```

---

## Použití

1. Označ text v libovolné aplikaci (nebo zkopíruj obrázek do schránky)
2. Dvakrát stiskni **Ctrl**
3. V okně vyber providera, operaci nebo napiš vlastní prompt
4. Výsledek se zkopíruje do schránky a zobrazí v dialogu

---

# Clip (EN)

Clip is a macOS tool that captures selected text or clipboard content, sends it to an AI model (Claude / ChatGPT), and copies the result back to the clipboard.

---

## Features

- **Double-tap Ctrl** triggers the popup
- Operations: translate/correct to **CZ / EN**, short answer **ASK**, key info extraction **KEY**, web page summary **WEB**
- **Custom prompt** — type anything
- **Image** clipboard support (vision API)
- Automatic URL fetching before sending
- Text-to-speech readout (Zuzana voice)
- Manage operations directly in the popup (add / edit / delete)
- Session logging to the `session/` folder
- Multiple AI providers: Anthropic Claude, Azure OpenAI, Azure Claude

---

## Installation

### Requirements

- macOS
- Python 3.9+
- **Accessibility** permission in System Settings → Privacy & Security → Accessibility

### Install dependencies

```bash
pip install -r requirements.txt
```

### Configuration

```bash
cp config.example.yaml config.yaml
```

Open `config.yaml` and fill in your API keys and endpoints.

#### Provider types

| type | Description |
|------|-------------|
| `anthropic` | Direct Anthropic API |
| `azure` | Azure OpenAI (GPT-4o etc.) |
| `azure_anthropic` | Claude via Azure AI Foundry |

### Run

```bash
python3 main.py
```

---

## Usage

1. Select text in any app (or copy an image to clipboard)
2. Double-tap **Ctrl**
3. Choose a provider and operation, or type a custom prompt
4. The result is copied to clipboard and shown in a dialog
