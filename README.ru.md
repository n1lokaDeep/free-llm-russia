# free-llm-russia

**Бесплатные LLM и нейросети из России: что работает без VPN, что без карты, что без того и другого.**

Все существующие списки «free LLM APIs» написаны для Запада. В них нет главного:
**можно ли вообще достучаться до сервиса из РФ** и **примут ли российскую карту**.
Этот список закрывает именно этот пробел.

Проверено на живой машине в РФ, октябрь 2026.

---

## Кому это нужно

Если вы искали что-то из этого — вы по адресу:

- бесплатные нейросети с API без карты и без верификации
- как получить API-ключ, если нет зарубежной карты
- почему `403 Access denied by security policy` и что с этим делать
- как обойти блокировку Cloudflare по IP
- бесплатный доступ к ChatGPT, Claude, Gemini, DeepSeek, Qwen из России
- API ChatGPT без VPN, Claude API без VPN, Gemini API без VPN
- прокси для OpenRouter, OpenAI, Anthropic
- настройка VLESS / Reality / sing-box / Xray
- бесплатные LLM с тарифом free tier навсегда
- OpenAI-совместимые бесплатные эндпоинты
- что делать, если WARP не работает
- ошибки `ConnectFail`, `Authentication Fails`, `Not found for account`
- как отличить блокировку по IP от неверного ключа
- бесплатные API для программирования и агентов (Cursor, VS Code, OpenCode)

**Ключевые слова:** бесплатные нейросети api, api без карты, нейросети без vpn,
chatgpt без впн, claude api, gemini api, обход блокировки, cloudflare 403,
access denied security policy, прокси для openai, vless конфиг, sing-box настройка,
free llm api, free ai api, no credit card, no vpn, geoblock bypass,
censorship circumvention, OpenAI-compatible free endpoint.

---

## Три разные проблемы, которые постоянно путают

| Препятствие | Как выглядит | Чем лечится |
|---|---|---|
| **Геоблокировка по IP** | `403 Access denied by security policy` | прокси |
| **Нужна зарубежная карта** | регистрация не проходит | сервис без карты |
| **Заблокирован сам сайт** | страница не открывается | только для браузера |

**API и сайт блокируются по-разному.** `openrouter.ai` может не открываться в браузере,
но API работает с правильного IP.

---

## Что работает без VPN

| Сервис | Нужна карта | Лимит | Модели |
|---|---|---|---|
| **Z AI (Zhipu)** | нет | 1 запрос параллельно | GLM-4.7-Flash, GLM-4.6V-Flash |
| **ModelScope** | нет, нужна верификация | 2000/день | Qwen3.5 |
| **SiliconFlow** | нет, нужна верификация | 1000 RPM | Qwen3-8B |
| **Mistral** | нет | ~$10/мес | Mistral Medium 3.5 |
| **OVHcloud AI** | **ключ не нужен** | 2 RPM | Qwen3.5-397B, gpt-oss-120b |

---

## Что работает только через прокси

| Сервис | Нужна карта | Лимит |
|---|---|---|
| **OpenRouter** | нет | **50/день на модель** |
| **Groq** | нет | 30 RPM, 1000 RPD |
| **Cloudflare Workers AI** | нет | 10 000 нейронов/день |
| **Google Gemini** | нет | 15 RPM, 1500 RPD |
| **NVIDIA NIM** | регистрация | 40 RPM, 10 000 RPD |
| **Ollama Cloud** | нет | не опубликованы |
| **Kilo Code** | **ключ не нужен** | 200/час |
| **LLM7.io** | нет | 60 RPM, 250/час |

---

## Что НЕ работает из РФ

| Сервис | Причина |
|---|---|
| **ChatGPT / OpenAI** | полная блокировка по региону |
| **Claude / Anthropic** | полная блокировка по региону |
| **Cloudflare WARP** | эндпоинты `:894` заблокированы провайдером |

### Почему WARP не помогает

Совет «поставь WARP» в РФ **не работает**:

```
188.114.97.170:894         →  заблокирован
api.cloudflareclient.com   →  timeout
```

Регистрация не проходит → в клиентах ошибка:

```
netip.ParsePrefix("/24"): ParseAddr(""): unable to parse IP
```

**Ирония:** WARP выдаёт адрес Cloudflare, а блокирует вас тоже Cloudflare.

---

## Как отличить блокировку от проблемы с ключом

```
403 + Access denied by security policy  →  блок по IP, ключ ни при чём
401 + Authentication Fails              →  ключ неверный или не от того сервиса
404 + Not found for account             →  модель недоступна аккаунту
429                                     →  лимит исчерпан
```

**Проверка одной командой:**

```powershell
Invoke-RestMethod https://api.ipify.org
```

**Смена ключа при 403 не помогает.** Проверено: два разных ключа дали одинаковый
`403` с одного IP.

---

## Скрипты

| Файл | Назначение |
|---|---|
| `scripts/start-proxy.ps1` | поднять прокси на `127.0.0.1:18888` |
| `scripts/proxy.ps1` | управление: start / stop / restart / status |
| `scripts/check-configs.py` | отобрать живые конфиги из публичного списка |
| `scripts/verify-live.py` | проверить реальным запросом, какие работают |

### Порядок

```powershell
# 1. Отобрать кандидатов
python scripts/check-configs.py --top 80

# 2. Проверить их реальным запросом
$env:SINGBOX = "C:\path\to\sing-box.exe"
python scripts/verify-live.py

# 3. Поднять прокси на рабочих
powershell -File scripts/start-proxy.ps1

# 4. Проверить
powershell -File scripts/proxy.ps1 status
```

### Реальность публичных конфигов

Замер: **из 5681 конфига живыми оказались 2.** TCP-порт может быть открыт,
а рукопожатие Reality — не проходить. Поэтому `verify-live.py` сравнивает выходной
IP с вашим собственным: если совпали — трафик шёл напрямую, а не через прокси.

---

## Ошибка, которую совершают все

**Не прописывайте прокси глобально:**

```powershell
# ТАК НЕ НАДО
[Environment]::SetEnvironmentVariable('HTTPS_PROXY','http://127.0.0.1:18888','User')
```

Игры и лаунчеры начнут ходить через прокси и падать с `ConnectFail`.
Прокси задаётся **только внутри процесса**:

```powershell
$env:HTTPS_PROXY = 'http://127.0.0.1:18888'
& myapp.exe
```

Проверено: глобальные переменные ломали Roblox.

---

## Лицензия

MIT
