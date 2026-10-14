---
id: akunito.plans.nas-3090-ai-presets
summary: Qué hacemos con la RTX 3090 del NAS — presets de IA bajo demanda (nada cargado por defecto), coach de Aion 2 por captura HDMI + voz + panel AkuWM, Pico 2 H como HID para capturar datos del juego, razonador/Hermes local aplazado
tags: [nas, gpu, rtx3090, ai, presets, aion2, pico, capture, elgato, hermes, whisper, infra-bot]
tickets: [AINF-404]
date: 2026-10-02
status: draft
related_files:
  - profiles/NAS_PROD-config.nix
  - system/hardware/nvidia.nix
  - system/app/nas-services.nix
  - system/app/infra-bot.py
  - docs/akunito/plans/nas-on-demand-services.md
  - docs/akunito/plans/desk-w11-meeting-captions.md
---

# RTX 3090 del NAS: presets de IA bajo demanda

Entrevista 2026-10-02 (DESK_W11). Hardware: 3090 instalada 2026-10-01 (reposo medido
7,5 W, 1 MiB VRAM, kernel 6.12.93); Elgato 4K X llega ~2026-10-03; Pico 2 H + Debug Probe
pedidos en Botland el 2026-10-01. Contexto previo: memorias `project_local_ai_box`,
`project_ai_hid_game_control`, `reference_nas_rtx3090_nvidia`.

## Decisiones

| Tema | Decisión |
|---|---|
| Modelo de uso | **Nada cargado por defecto.** Se elige un *preset* antes de empezar cualquier cosa; el preset carga sus modelos y descarga los del anterior |
| Horario NAS | Se mantiene S3 23:00→16:00; **elegir un preset despierta el NAS (WoL)** |
| Selector | CLI (`ai preset …`), Telegram, hotkey AHK en Windows, **panel de AkuWM** |
| Telegram | Presets = **topic "AI" en el foro de Infra** (comandos en `infra-bot`, mismo patrón que `/svc`). Hermes, cuando vuelva = **grupo/bot propio** |
| Razonador | Local solo como opción (preset); por defecto la nube donde se permita |
| Privacidad | **Aion 2: nube permitida** (Claude/DeepSeek para el análisis post-sesión). **Hermes: 100 % local** → solo existe con el preset razonador |
| Hermes | **Aplazado** |
| NVENC | No para Jellyfin (el iGPU ya hace VAAPI). **Sí para grabar sesiones** (H.265) |
| Coach v1 | Grabar + analizar sesiones · responder con las guías (RAG sobre aion2.akunito.com) · con la Pico: navegar la UI para capturar datos |
| Voz | Entrada Whisper + salida TTS en cascos, **inglés**; skills/items en **español** si el TTS los pronuncia bien, si no **todo español** |
| Salida | Voz + **panel AkuWM** + Telegram (resúmenes/avisos) |
| Datos Pico | Todo, **bajo demanda**: personaje (stats/equipo/stigmas/skills), inventario + almacén, mercado, quests + mapa |
| Retención | **Clips 3 días**; datos extraídos, eventos, análisis y screenshots seleccionados **para siempre** |
| Secundario | Extraer iconos de skills/items para las guías |

## Presets (borrador; VRAM ESTIMADA, medir en F1)

| Preset | Carga | VRAM est. |
|---|---|---|
| `off` (defecto) | nada | 0 |
| `aion-coach` | Qwen3-VL-8B (o Gemma 4 12B) + Whisper large-v3-turbo + TTS + embeddings + NVENC grabación | ~15-18 GB |
| `aion-pico` | `aion-coach` + controlador Pico (CPU) | igual |
| `reasoner` | **LIVE 2026-10-13**: Qwen3.8-27B abliterated (huihui-ai UD-Q4_K_XL 17,4 GB), `llama-server.nix` backend `docker-cuda`, `http://100.64.0.1:8090`, alias `qwen3.8-27b-abliterated` | **21,1 GB medidos** (1 slot × 128k, KV q8_0, 2026-10-14) |
| `hermes` | `reasoner` + Hermes (aplazado) | igual |
| `coder` | modelo de código para OpenCode | ~15-20 GB |
| `whisper` | solo Whisper (reuniones, `meeting-transcribe` M3) | ~4-5 GB |

Reglas: un preset activo a la vez (unidades systemd con `Conflicts=`); el preset impide el
sueño S3 mientras está activo (inhibitor) y se apaga solo tras N min sin uso; antes de S3
se paran todos los servicios de IA (NVIDIA + VRAM cargada + suspend = frágil).

## Fases

- **Hecho 2026-10-13 — preset `reasoner` a mano** (sin gestor aún): medido CUDA 1 326 pp / 40 tg tok/s; Vulkan sobre el ICD de NVIDIA 48 pp → descartado. Desplegado y medido durante el `zfs send` de la migración sin efecto en su presión de IO (~55 % antes y después).
- **Hecho 2026-10-14 — harness desde DESK** (commit f038ad2e): OpenCode proveedor `nas` (`opencode --model nas/qwen3.8-27b-abliterated`, tarea leer+editar en 23 s), `claude-nas` (Claude Code entero sobre el NAS vía su API Anthropic `/v1/messages`, mismo `~/.claude`; sin MCP por defecto: con los MCP el primer turno son 45-48k tokens y la tarea tarda 3 min 07 s, sin ellos 16,7k y 27 s) y `nas-ask` (una respuesta, stdin = contexto, para que Opus/Fable deleguen desde Bash; skill `nas-reasoner`). Hizo falta una plantilla de chat propia (`system/app/llama-server/templates/qwen3.8-system-anywhere.jinja`): Claude Code 2.1.296 manda su bloque "# Environment" como `role=system` tras el primer turno y la plantilla del GGUF lo rechazaba (HTTP 500 en todo). Ctx 32k → 64k → **1 slot × 128k con KV q8_0** (la KV son 64 KB/token en f16: 256k pedía 16 GB y dio OOM; 256k solo cabría con KV q4_0, descartado). Energía (medias de 30 s a P8): 7,5 W descargada vs 7,6 W cargada, contenedor 0,04 % CPU / 414 MB → **decisión 2026-10-14: ningún timer de descarga** (`llamaServerIdleTimeout = "infinity"`, commit e6af59e0); el modelo se queda hasta el S3 o hasta que el gestor de presets (F1) lo cambie.
- **Hecho 2026-10-14 — gestor de presets F1 (sesión dotfiles-69, `system/app/ai-presets.nix`, commits 264849ab/2eed604a) + 4 modelos de decisión** (API `/v1/systemone` de llama.cpp b11580, PRs 29818/29831/29969; devuelven probabilidades, no texto; chat → 501). Medido tras la carga (nvidia-smi) y con la prueba de humo (ticket de soporte: tema/urgencia/enfado; imagen: PNG rojo con cuadrado negro): `laya` (Convai, BF16 0,8 GB) carga 2,9 s, 1,0 GB, 0,15 s/petición, acierta tema `bug` 0,93 · `kev-9b` (Jared Palmer, Q8_0) 4,1 s, 13,2 GB, 0,18 s, `bug` 0,97 · `decider` (Perplexity pplx-decider v1.1 27B, GGUF Artemis de turintech + mmproj) 13,4 s, 17,5 GB, 0,40 s texto / 0,48 s imagen, `bug` 0,997, rojo 0,9999 · `clef` (Cloudflare 27B Q4_K_M + mmproj, `-ub 4096`) 17,4 s, 20,1 GB, 0,60 s / 0,25 s, `bug` 0,98, rojo 0,987. Ficheros en `/var/lib/llama-server/models/` vía `system/app/llama-server/hf-download.sh` (sha256). Entrenar Laya/Kev para Aion 2 es Python (peft/transformers), fase aparte: ver `docs/akunito/plans/aion2-capture-pipeline.md`.

- **Hecho 2026-10-14 — F1 mínimo (gestor de presets)** (commits 264849ab, 3481f130): `system/app/ai-presets.nix` + `ai preset list|status|set|sync` en el NAS; `llama-server.nix` construye los argumentos al arrancar desde `/var/lib/llama-server/preset.env` (sin fichero = la config Nix); `off` para socket + proxy + backend; estado en `/var/lib/ai-presets/current`, re-aplicado al arrancar; `GET /status` en tailscale0:8093; sudo solo para `ai preset set`. DESK: widget Waybar `custom/nas-llm` (preset, VRAM, temperatura; "zz" si el NAS duerme, sin WoL) + menú rofi. **Medido** (cambio por ssh + petición de 200 tokens): reasoner-128k q8_0 21,1 GB 40 tok/s; reasoner-256k q4_0 22,0 GB 39 tok/s; **coder Qwen3.6-35B-A3B UD-IQ4_XS 256k q8_0 20,3 GB, 126 tok/s**; cambio + carga 6 s en caliente, 40 s en frío. `-c` es el TOTAL repartido entre slots (`-c 131072 -np 2` → 64k por slot): 2×128k = `-c 262144 -np 2`. Pendiente de F1: WoL (no funciona hoy), Telegram, hotkey AHK, temps/API para AkuWM.
- **F0 — base (al llegar la Elgato):** AINF-404 kernel ≥6.19 en el NAS; Elgato por USB 3
  al NAS (comprobar Gen 1 vs Gen 2 con `lsusb -t`), 1080p60 por UVC; Samsung pasa a HDMI
  2.1 a través de la 4K X — probar VRR + HDR en los 30 días de devolución; 20+ ciclos S3
  con el driver NVIDIA cargado.
- **F1 — gestor de presets:** script `ai` + unidades systemd por preset, API de estado
  (preset, VRAM, temps), WoL desde VPS/W11, comandos Telegram en el topic AI, hotkey AHK.
  Medir VRAM real de cada preset.
- **F2 — coach v1:** captura continua (ffmpeg NVENC H.265, anillo 3 días, screenshots a
  petición), RAG sobre las guías, preguntas por voz EN, prueba del glosario ES en TTS,
  panel AkuWM (WebSocket desde el NAS), análisis post-sesión con Claude → datos permanentes.
- **F3 — Pico:** firmware HID compuesto (teclado + ratón absoluto) + UART desde la Debug
  Probe, kill switch BOOTSEL, dead-man heartbeat; rutinas de navegación de menús bajo demanda
  que recorren cada pantalla, capturan y extraen a la base de datos.
- **F4 — quests/leveo + modelo propio (estilo Jev local):** ver "Riesgos". Entrenar con
  grabaciones propias; campo de pruebas = servidor L2 propio antes que Aion 2.
- **F5 — razonador local + Hermes** (aplazado).
- **F6 — iconos para las guías** (secundario).

## Riesgos y límites

- **Leveo/quests autónomos en Aion 2 = bot** en un servidor público con NCGuard: riesgo de
  ban de la cuenta principal y va contra el ToS. Diego aceptó el riesgo solo para input de menús (2026-10-01); para leveo **pendiente de confirmar**. **No se hace
  ningún trabajo para evadir la detección del anticheat**. El mercado periódico es lo más
  detectable de F3.
- Kernel 6.19 en el NAS de almacenamiento: probar ZFS (módulo compatible con ese kernel) antes de nada.
- TTS mixto EN + nombres ES: probable mala pronunciación → fallback todo español.
- Grabar 3-4 h/día ≈ 2-4 GB/h (estimado) → anillo de 3 días ≈ 40 GB en `extpool`.
