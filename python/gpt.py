import anthropic
import openai
from typing import Optional


def ask(provider_cfg: dict, system_prompt: str, user_text: str,
        image_b64: Optional[str] = None) -> str:
    kind = provider_cfg["type"]

    if kind == "azure":
        client = openai.AzureOpenAI(
            api_key=provider_cfg["api_key"],
            azure_endpoint=provider_cfg["endpoint"],
            api_version=provider_cfg["api_version"],
        )
        if image_b64:
            user_content = [
                {"type": "text", "text": system_prompt},
                {"type": "image_url", "image_url": {
                    "url": f"data:image/png;base64,{image_b64}"
                }},
            ]
            messages = [{"role": "user", "content": user_content}]
        else:
            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_text},
            ]
        response = client.chat.completions.create(
            model=provider_cfg["deployment"],
            messages=messages,
        )
        return response.choices[0].message.content.strip()

    elif kind == "azure_anthropic":
        client = anthropic.Anthropic(
            api_key=provider_cfg["api_key"],
            base_url=provider_cfg["endpoint"],
            default_headers={"api-key": provider_cfg["api_key"]},
        )
        if image_b64:
            user_content = [
                {"type": "image", "source": {
                    "type": "base64", "media_type": "image/png",
                    "data": image_b64,
                }},
                {"type": "text", "text": system_prompt},
            ]
        else:
            user_content = user_text
        message = client.messages.create(
            model=provider_cfg["model"],
            max_tokens=1024,
            system=system_prompt if not image_b64 else "",
            messages=[{"role": "user", "content": user_content}],
            tools=[{"type": "web_search_20250305", "name": "web_search"}],
        )
        # Collect all text blocks (model may interleave tool use and text)
        parts = [b.text for b in message.content if hasattr(b, "text")]
        return "\n".join(parts).strip()

    elif kind == "anthropic":
        client = anthropic.Anthropic(api_key=provider_cfg["api_key"])
        if image_b64:
            user_content = [
                {"type": "image", "source": {
                    "type": "base64", "media_type": "image/png",
                    "data": image_b64,
                }},
                {"type": "text", "text": system_prompt},
            ]
        else:
            user_content = user_text
        message = client.messages.create(
            model=provider_cfg["model"],
            max_tokens=1024,
            system=system_prompt if not image_b64 else "",
            messages=[{"role": "user", "content": user_content}],
        )
        return message.content[0].text.strip()

    else:
        raise ValueError(f"Neznámý typ providera: {kind}")
