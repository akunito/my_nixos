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
| `reasoner` | Qwen3.8-27B Q4 (o el mejor ≤22 GB del momento) | ~17-20 GB |
| `hermes` | `reasoner` + Hermes (aplazado) | igual |
| `coder` | modelo de código para OpenCode | ~15-20 GB |
| `whisper` | solo Whisper (reuniones, `meeting-transcribe` M3) | ~4-5 GB |

Reglas: un preset activo a la vez (unidades systemd con `Conflicts=`); el preset impide el
sueño S3 mientras está activo (inhibitor) y se apaga solo tras N min sin uso; antes de S3
se paran todos los servicios de IA (NVIDIA + VRAM cargada + suspend = frágil).

## Fases

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
