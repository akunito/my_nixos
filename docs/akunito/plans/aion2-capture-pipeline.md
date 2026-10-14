---
id: akunito.plans.aion2-capture-pipeline
summary: Cómo capturar una sesión de Aion 2 en DESK de forma eficiente (paquetes del meter + frames de la Elgato/DESK + entradas evdev, con un reloj común) para un asesor en vivo sobre la 3090 del NAS y para entrenar un modelo de decisión tipo Jev (Kev/Laya) con las propias partidas
tags: [aion2, nas, rtx3090, capture, elgato, evdev, meter, coach, decision-model, kev, laya, clef, training]
tickets: []
date: 2026-10-14
status: draft
related_files:
  - docs/akunito/plans/nas-3090-ai-presets.md
  - system/app/aion2-meter-daemon.nix
  - system/app/ai-presets.nix
  - system/app/llama-server.nix
  - system/app/llama-server/hf-download.sh
---

# Captura de Aion 2 → asesor en vivo → modelo que aprende a jugar

Investigación del 2026-10-14. Parte de lo que ya existe: Aion 2 corre en **DESK** (Proton + gamescope, red por el stack del host), el **meter daemon** (`aion2-meter-daemon`, A2M-48) ya decodifica los paquetes del juego en tiempo real y tiene un overlay layer-shell sobre el juego, la **Elgato 4K X** entra por USB al NAS (kernel ≥ 6.19, AINF-404) y la **3090** sirve hoy un razonador (Qwen3.8-27B) y cuatro modelos de decisión por `/v1/systemone` (Laya, Kev-9B, pplx-decider, Clef). Las referencias externas revisadas están al final.

## 1. Principio: tres fuentes, un reloj, nada por frame

Un LLM/VLM no puede ir al ritmo del juego (los surveys de agentes LLM en juegos coinciden: decisión por frame imposible, y meter píxeles a menudo empeora el juego). Lo eficiente es capturar **estado estructurado** barato todo el rato y **píxeles** solo muestreados o bajo demanda, y dejar que el modelo trabaje por **eventos**, no por frames.

| Fuente | Dónde | Qué da | Coste | Estado |
|---|---|---|---|---|
| **Paquetes** (meter daemon) | DESK, `/run/aionmeter/aionmeter.sock` + `--forward ip:port` | posiciones, heartbeats, skills lanzadas, daño, objetivos, field bosses, muertes, quest/mapa según lo que el meter decodifica | ~0 CPU, decenas de KB/s | **ya existe** (A2M-27 forward al NAS sin tocar código) |
| **Frames** | NAS vía Elgato (topología B) o DESK vía `grim`/pipewire hasta que AINF-404 esté | lo que el meter no sabe: UI, texto de misiones, mapa, inventario, chat | NVENC H.265 continuo ≈ 1-2 % de la 3090; JPEG muestreado a 1-2 fps ≈ 200 KB/frame | Elgato en casa, kernel pendiente |
| **Entradas** | DESK, lector evdev de `/dev/input/event*` (teclado + ratón) | teclas, deltas de ratón, timestamps | ~0 | no existe (pequeño servicio) |

Las tres escriben JSONL con `t_mono` (CLOCK_MONOTONIC del emisor) y `t_wall`; NAS y DESK sincronizan por NTP (ya), suficiente para alinear a ~10 ms. Un `session_id` por partida (lo abre el preset `aion-capture`, lo cierra el idle del meter).

**Dónde se guarda:** `/var/lib/aion-capture/<session>/` en la NVMe raíz del NAS (316 GB libres; clips 3 días, eventos para siempre, como se decidió en el plan de presets), luego al pool cuando acabe la migración.

**Por qué evdev y no el Pico para grabar:** el Pico 2 H es un HID de **salida** (el NAS teclea en DESK); para registrar lo que tú tecleas, leer evdev en DESK es gratis y exacto. El Pico queda para la fase de actuar.

## 2. Asesor en vivo (coach v1)

Bucle por eventos, latencia aceptable 2-5 s:

1. **Disparadores** desde el flujo del meter: entrar en combate con un boss, HP < 30 %, muerte, nueva quest, 60 s sin movimiento, cambio de zona; y **voz** (Whisper, preset `aion-coach`) o un hotkey para preguntar.
2. **Estado en texto** (≤ 2 k tokens): últimos N eventos del meter + ficha del personaje (de la base de datos de la Pico cuando exista) + resultado de las preguntas a **Clef/decider** sobre el último frame (tipo de pantalla, ¿hay diálogo de quest?, ¿inventario lleno?, ¿qué enemigo?) — los modelos de decisión tardan 0,25-0,6 s y devuelven probabilidades, mucho más baratos que un VLM generando texto.
3. **RAG** sobre las guías (`aion2.akunito.com`) y respuesta del **razonador** (chat) o de un **VLM** con el frame cuando hace falta leer la UI (Qwen3.5-9B abliterated con su mmproj: 9,5 + 0,6 GB, cabe junto a Clef-Flash o Kev).
4. **Salida**: tarjeta en el overlay que ya tiene el meter (gtk4-layer-shell sobre gamescope, USR2 para mostrar/ocultar) + TTS en DESK. Nunca inyecta entradas.

VRAM del preset `aion-coach` (medido/estimado): Clef-Flash Q8 9,7 GB o Kev-9B 13,2 GB + Qwen3.5-9B VLM ~11 GB + Whisper turbo ~1,5 GB → Kev y Qwen3.5-9B juntos (24 GB) no caben con Whisper; combinación realista: **Qwen3.5-9B (VLM+chat) + Laya/Clef-Flash + Whisper ≈ 22 GB**, a medir. Con el modo router de llama-server (abajo) el cambio entre ellos es por nombre de modelo.

## 3. Datos para entrenar un modelo tipo Jev (que aprenda a jugar)

Un modelo de decisión (Kev/Laya/Clef) no genera texto: dado un **estado** y **preguntas tipadas** elige entre opciones con probabilidad calibrada. Eso encaja exactamente con "¿qué hago ahora?" en un MMO si las opciones son **acciones macro**, no teclas.

- **Etiquetas gratis desde los paquetes:** la skill lanzada, el objetivo elegido, el movimiento (posición t+1) y el resultado (daño, muerte) ya van en el flujo del meter. No hace falta keylogger para el 80 % del dataset; evdev añade lo que el servidor no ve (abrir menús, cámara, cancelaciones).
- **Registro = pares (estado_t → acción_t+Δ)**: estado = ventana de 5-10 s de eventos + stats + (opcional) salida de Clef sobre el frame; acción = `{skill_id | move(dir) | target(id) | loot | retreat | open(menu)}`. Un script offline convierte el JSONL de una sesión en el formato de `kev.train` (preguntas `choice` con la lista de skills, `noul` "¿retirarse?", `score` "prioridad del objetivo").
- **Tamaño:** la ficha de Kev dice que 400 registros no salen del ruido y que 1 000-5 000 ya mueven la aguja (Kev-4B pasó de 0,80 a 0,90 con 5 219). A 1 decisión cada 3-5 s de combate, **una semana de sesiones de 3 h da ~15-25 k registros**.
- **Qué modelo:** empezar por **Kev-4B** (adapter sobre Qwen3.5-4B, entrena en una 3090 en minutos-horas; `kev.train --init_from jaredpalmer/kev-4b`), pasar a Kev-9B si la precisión lo pide; Laya solo si hace falta < 50 ms por decisión. Entrenamiento = Python (peft/transformers) en docker sobre el NAS, **no** llama.cpp; el GGUF resultante se sirve igual que los de hoy.
- **Alternativa píxeles-solo** (behavioural cloning CNN/ViT sobre capturas, p. ej. Imitation-player): más genérica, mucho más dato (decenas de horas) y frágil ante parches de UI; la dejamos como plan B o para el modelo de percepción (detectar mobs/HP) si el meter no cubre algo.

**Riesgo que sigue igual:** grabar y aconsejar es pasivo; que el Pico actúe en el servidor público (NCGuard) es un bot con riesgo de ban. La fase de "jugar solo" se prueba primero en modo sombra (el modelo propone, tú ejecutas, se mide el acuerdo).

## 4. Qué tocar en la infraestructura (orden propuesto)

| Paso | Qué | Dónde |
|---|---|---|
| C0 | `aion2MeterDaemonForward` apuntando al NAS + colector JSONL en el NAS (`aion-capture` service, socket UDP/TCP del forward) | `system/app/aion2-meter-daemon.nix`, nuevo `system/app/aion-capture.nix` |
| C1 | Lector evdev en DESK (user service, grupo `input`) que manda JSONL al mismo colector | nuevo módulo DESK |
| C2 | Frames: hasta AINF-404, `grim -o DP-1` a 1 fps a JPEG → NAS; con la Elgato, `ffmpeg -f v4l2` NVENC H.265 anillo 3 días + JPEG muestreado | NAS |
| C3 | Conversor sesión → dataset Kev (`choice/noul/score`), primer entrenamiento Kev-4B, evaluación en modo sombra | docker python en el NAS |
| C4 | Coach v1: disparadores + Clef/decider sobre el frame + RAG + overlay/TTS | preset `aion-coach` |

## 5. Modelos de contexto largo para el asesor (pregunta del 2026-10-14)

KV por token (f16) = 2 × capas_atención_completa × kv_heads × head_dim × 2 B. Medido/calculado con los `config.json` oficiales:

| Modelo | Capas full-attn | KV/token f16 | 512k con KV q8_0 | Pesos | Total |
|---|---|---|---|---|---|
| Qwen3.8-27B (razonador actual) | 16 × 4 heads | 64 KB | 16 GB | 17,4 GB | **no cabe** (256k ya necesita KV q4_0) |
| **Qwen3.5-9B** (abliterated, con visión) | 8 × 4 | 32 KB | 8 GB | 9,5 GB Q8_0 | **~18,5 GB, cabe** |
| Qwen3.6-35B-A3B (coder, MoE) | 10 × 2 | 20 KB | 5 GB | 17 GB IQ4_XS | ~22,5 GB, justo |

Los tres están entrenados a **262 144**; 512k exige YaRN ×2 (`--rope-scaling yarn --rope-scale 2 --yarn-orig-ctx 262144`), con pérdida de precisión en recuerdo a larga distancia. Recomendación: preset `reasoner-9b-512k` = Huihui-Qwen3.5-9B-abliterated Q8_0 + mmproj (ya en `hf-download.sh`), 1 slot, KV q8_0, YaRN ×2, `--reasoning-effort medium --reasoning-budget 16384`. Es razonador (Qwen3.5 piensa) y ve imágenes, ~2× más rápido que el 27B. Sirve para "mucho contexto"; para "mucha calidad" sigue el 27B a 128-256k.

## 6. Un solo servidor: modo router de llama-server

`llama-server --models-preset presets.ini --models-max 1 --models-dir /var/lib/llama-server/models` (disponible en la imagen b11580) carga el modelo que nombra cada petición y descarga el anterior; `GET /models` lista todos con estado `loaded/unloaded`. Consecuencias: el selector `/model` de Claude Code (alias Opus/Sonnet/Haiku/Fable → nombres de preset distintos), la lista de OpenCode y el widget de Waybar hablan todos del mismo nombre de modelo y **cambiar desde cualquiera cambia el modelo cargado**; el gestor `ai preset` queda como capa fina (escribe el INI, `load-on-startup`). Decisión pendiente con la sesión que hizo F1.

## Referencias

- llama.cpp `tools/server/README.md` (router mode, presets INI, `/v1/systemone`, sleeping on idle) y blog "New in llama.cpp: Decision Models" (ggml-org).
- Fichas: `jaredpalmer/kev` README y `docs/model-cards/kev-9b.md` (fine-tune, tamaños de dataset), `convaiinnovations/laya` (0,36 zero-shot vs 0,77 fine-tuned), `turintech/pplx-decider-27B-Artemis-GGUF`, `ggml-org/Clef-GGUF`.
- "A Survey on LLM-Based Game Agents" (arXiv 2404.02039); "Augmentations for Robust and Efficient Imitation Learning in Streamed Video Games" (arXiv 2607.14200, IEEE CoG 2026); Imitation-player (github PedroM2626, BC/DAgger/GAIL sobre capturas).
- Memorias: `project_ai_hid_game_control`, `project_desk_proton_aion-2`, `project_desk_meter_daemon_service`, `reference_nas_decision_models_systemone`.
