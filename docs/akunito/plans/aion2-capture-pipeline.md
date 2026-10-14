---
id: akunito.plans.aion2-capture-pipeline
summary: Fork del plan de presets para Aion 2 ahora que el juego corre en DESK (NixOS/Proton) — dos partes complementarias sobre un mismo bus de estado (paquetes del meter + evdev + frames muestreados, un reloj) — A) captura + asesor pasivo, B) asistente/automatización con entradas virtuales uinput en el propio DESK; modelos de decisión Kev/Laya entrenados con las propias partidas; análisis de detección, latencias y modelo de 512k
tags: [aion2, nas, rtx3090, desk, proton, capture, uinput, evdev, meter, coach, decision-model, kev, laya, clef, training]
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

# Aion 2 en DESK (Linux): captura, asesor y asistente

**Fork (2026-10-14) del plan `nas-3090-ai-presets`**: aquel asumía el juego en Windows (DESK_W11), por eso la Elgato en el NAS y la Pico como HID externo. Aion 2 corre en **DESK NixOS** bajo Proton + gamescope (ProtonDB *platinum*, 67 informes, 2026-10-14) con la red por el stack del host, y el **meter daemon** (`aion2-meter-daemon`, A2M-48) ya decodifica el protocolo en vivo. Eso cambia tres cosas: la captura puede ser completa y local, las entradas virtuales se inyectan en el mismo equipo, y la Elgato/Pico pasan a opcionales (siguen valiendo para W11 o cualquier otra máquina). La 3090 del NAS sigue siendo el cerebro (razonador, VLM, modelos de decisión por `/v1/systemone`).

## 0. Qué cambia estando en Linux (detección y riesgo)

- **El anticheat del cliente vive dentro de Wine.** Bajo Proton no hay driver de kernel; lo que el cliente pueda comprobar lo hace en espacio de usuario dentro del prefijo. Todo lo nuestro corre **fuera**: libpcap en `bond0` (ya lo hace el meter), el lector evdev y el inyector uinput son objetos del kernel/host que el juego no puede enumerar. A nivel de cliente, un evento de `/dev/uinput` y uno del Keychron son indistinguibles (llegan por el mismo `libinput → Sway → gamescope → XWayland`).
- **Lo que NO cambia:** el servidor ve exactamente lo mismo que antes (timing de inputs, secuencias imposibles, horas seguidas sin pausas) y los ToS siguen prohibiendo automatizar. Grabar y aconsejar es pasivo; que el software pulse teclas es lo que puede acabar en sanción si parece un bot. Por eso la parte B se construye en **modo sombra → asistido con confirmación → macros cortas**, y la autonomía no está en el plan.
- **Leer memoria del proceso** (`/proc/<pid>/mem` del `AION2.exe` bajo Proton) también es invisible para el cliente, pero es lo más invasivo y lo más frágil ante parches; solo si los paquetes no cubren algo imprescindible. No empezar por ahí.

## 1. Bus de estado común (base de las dos partes)

Un LLM/VLM no puede ir al ritmo del juego (los surveys de agentes LLM coinciden: decidir por frame es imposible y meter píxeles a menudo empeora). Capturar **estado estructurado** barato todo el rato, **píxeles** solo muestreados o bajo demanda, y trabajar por **eventos**.

| Fuente | Dónde | Qué da | Coste | Estado |
|---|---|---|---|---|
| **Paquetes** (meter) | DESK, `/run/aionmeter/aionmeter.sock` + `--forward ip:port` (A2M-27) | posición, heartbeats, skills lanzadas, daño, objetivo, bosses, muertes; **inventario y almacén, equipo, stats (`49 36`), skills y barra (`00 51`/`00 39`/`8c e2`), Daevanion, logros/questlog (`83 56`/`84 56`), tienda, cofres de expedición** (ver memoria del meter: `reference_login_family_protocol`, `reference_live_player_state`); estado por personaje en JSON ≤ 5 s | ~0 | **existe** |
| **Entradas** | DESK, lector evdev de `/dev/input/event*` (akunito ya está en `input`) | teclas, deltas de ratón, timestamps | ~0 | falta (servicio pequeño) |
| **Frames** | DESK: `grim`/pipewire 1-2 fps JPEG, o gamescope `--capture`; opcional Elgato en el NAS | solo lo que no va en paquetes: diálogos, texto de misión en pantalla, chat, mapa/marcadores, cursores de UI | 200 KB/frame; NVENC continuo si se quiere vídeo | falta |

Las tres escriben JSONL con `t_mono` + `t_wall` y `session_id`; DESK y NAS van por NTP (ya), ~10 ms de alineación. Almacén `/var/lib/aion-capture/<session>/` en la NVMe raíz del NAS (316 GB libres; clips 3 días, eventos para siempre).

**Paquetes vs. píxeles:** lo que el meter ya decodifica no se OCR-ea nunca (es exacto, instantáneo y gratis). La pregunta "¿pasamos imágenes a texto para posición, HP, MP, misión?" se contesta campo a campo: posición, stats, skills, inventario y questlog **ya vienen por paquetes**; HP/MP propios y del objetivo en combate: comprobar en el meter si el heartbeat/`00 8d` los trae (probable) y si no, decodificar el opcode (trabajo en el proyecto del meter, no OCR). Píxeles solo para texto de UI que el servidor no manda o que no merece ingeniería inversa; y para eso Clef/decider con preguntas tipadas (0,25-0,6 s) antes que un VLM generando texto.

**Optimizar la captura de paquetes:** (1) `--forward` al colector del NAS en vez de releer pcaps; (2) ampliar el decodificador con los opcodes pendientes del meter (`50 36` inspect, `1c 92` party, kills) y los de combate que falten (HP/MP, buffs, cooldowns) — cada uno es una tarde con el bucle `export pcap → análisis python` ya documentado; (3) escribir el estado derivado (no el hex) en el JSONL: `{t, pos, hp, mp, target, skills_cd, quest_active, zone}`; (4) muestrear a 5-10 Hz para el dataset aunque los paquetes vayan más rápido.

**REA (Reverse Engineer Anything, `~/Projects/rea`, MCP de morluto) como motor del decodificador.** Hasta ahora cada opcode se ha deducido de capturas propias (bucle `export pcap → python`). REA añade dos vías sistemáticas: (1) **análisis nativo** de `AION2-Win64-Shipping.exe` (PE, Unreal 5) con Ghidra/Hopper por MCP: pseudocódigo, strings y xrefs → localizar el *dispatch* de opcodes y las funciones de (de)serialización, y de ahí **la tabla completa de opcodes con sus layouts** en vez de adivinar campo a campo; (2) **paquetes grabados**: TShark con reglas `decode-as` sobre los pcaps que ya exporta el meter, campos seleccionados y valores repetidos, para contrastar el layout estático con el tráfico real. Salida esperada: un `opcodes.json` (id → nombre, campos, tipos) del que el meter genera parsers, y la lista de qué estado existe en el protocolo (HP/MP, buffs, cooldowns, quest activa, party, inspect) sin OCR. Límites: el binario Shipping está *stripped* y pesa cientos de MB (horas de Ghidra y mucha RAM: hacerlo en el NAS o la VPS, no en DESK mientras se juega); si el ejecutable va empaquetado/cifrado por el anticheat hará falta un volcado desde memoria del proceso bajo Proton (es el único caso en que tocar `/proc/<pid>/mem` compensa); REA es Node ≥ 22 → por la regla de "nada de toolchains en el host" corre en docker/`rbuild`, no con `npx` en DESK. Vive en el proyecto del meter (A2M), no aquí.

## 2. Parte A — captura + asesor (pasiva)

Bucle por eventos, latencia aceptable 2-5 s:
1. **Disparadores** del bus: boss, HP < 30 %, muerte, nueva quest, 60 s parado, cambio de zona; **voz** (Whisper) o hotkey para preguntar.
2. **Estado en texto** (≤ 2 k tokens): últimos N eventos + ficha del personaje (ya en JSON) + respuestas de **Clef/decider** sobre el último frame cuando haga falta (tipo de pantalla, ¿diálogo abierto?, ¿inventario lleno?).
3. **RAG** sobre `aion2.akunito.com` + **razonador** (texto) o **Qwen3.5-9B VLM** cuando hay que leer la UI.
4. **Salida**: tarjeta en el overlay layer-shell del meter (ya existe, USR2 mostrar/ocultar) + TTS. Nunca inyecta entradas.

## 3. Parte B — asistente / automatización (activa, para aprender)

- **Inyección**: `/dev/uinput` (akunito ya tiene `rw` por ACL de logind en DESK; `python-evdev UInput` o `ydotool`) crea un teclado+ratón virtuales; gamescope los recibe como cualquier otro. Ratón **relativo** (cámara) y clics; nada de coordenadas absolutas raras. Servicio `aion-assist` en DESK con un socket local: recibe acciones macro (`skill 3`, `target_next`, `move fwd 800ms`, `open_bag`) y las traduce a eventos con **jitter humano** (distribución de tiempos tomada del propio registro evdev de la parte A — es el mismo dataset).
- **Escalera de autonomía**: (1) *sombra*: el modelo propone en el overlay, tú pulsas; se mide el acuerdo; (2) *asistido*: una tecla "hazlo" ejecuta la propuesta; macros de 1-3 acciones; (3) *rutinas*: navegación de menús para capturar datos (bolsa, almacén, mercado, questlog) — lo que antes iba a hacer la Pico; (4) autonomía en combate: **no planificado**, y nunca sin modo sombra previo.
- **Kill switch**: cualquier tecla física real cancela la rutina (el lector evdev ve la diferencia: dispositivo físico vs. virtual).

## 4. Qué modelo para respuestas rápidas

Tres velocidades, como en el diseño del 2026-09-28, pero ahora todo local:

| Capa | Latencia | Quién | Entrenar |
|---|---|---|---|
| Reflejos (interrumpir, esquivar, parar la rutina) | < 10 ms | reglas sobre el bus de paquetes | no |
| Decisión macro ("¿qué skill/objetivo ahora?", "¿retirarse?") | 50-200 ms | **Kev-4B** (0,1 s estimado; Kev-9B 0,18 s medido) o **Laya** (0,15 s medido en GPU, ~30 ms afinando el batch) | **sí**, con las propias partidas |
| Planificación y charla | 2-5 s | razonador 27B o Qwen3.5-9B | no |

**Recomendación:** entrenar **Kev-4B** primero (adapter sobre Qwen3.5-4B, entrena en la 3090 en minutos-horas con `kev.train --init_from jaredpalmer/kev-4b`, preguntas `choice` con la lista de skills, `noul` "¿retirarse?", `score` "prioridad del objetivo"); subir a Kev-9B si la precisión lo pide; Laya solo si hacen falta < 50 ms. Etiquetas gratis desde los paquetes (skill lanzada, objetivo, resultado); evdev añade lo que el servidor no ve. La ficha de Kev: 400 registros no salen del ruido, 1 000-5 000 ya mueven la aguja (Kev-4B 0,80 → 0,90 con 5 219); a 1 decisión cada 3-5 s de combate, una semana de sesiones de 3 h ≈ 15-25 k registros. Entrenamiento = Python (peft/transformers) en docker sobre el NAS, no llama.cpp; el GGUF resultante se sirve como los de hoy. Plan B píxeles-solo (behavioural cloning tipo Imitation-player): más genérico, mucho más dato, frágil ante parches de UI.

## 5. Pasos (orden propuesto)

| Paso | Qué | Dónde |
|---|---|---|
| C0 | `aion2MeterDaemonForward` → colector JSONL en el NAS (`aion-capture.service`) + estado derivado a 5-10 Hz | `system/app/aion2-meter-daemon.nix`, nuevo `system/app/aion-capture.nix` |
| C1 | Lector evdev en DESK (user service) → mismo colector; marca físico/virtual | nuevo módulo DESK |
| C2 | Frames muestreados desde DESK (`grim` 1 fps) → NAS; vídeo NVENC opcional (Elgato opcional) | DESK/NAS |
| C3 | Conversor sesión → dataset Kev; primer Kev-4B; evaluación en sombra | docker python en el NAS |
| C4 | Asesor v1 (parte A): disparadores + Clef/decider + RAG + overlay/TTS | preset `aion-coach` |
| C5 | `aion-assist` (parte B): uinput + jitter + kill switch; sombra → asistido → rutinas de menús | DESK |

## 6. Modelos de contexto largo (pregunta del 2026-10-14)

KV por token (f16) = 2 × capas de atención completa × kv_heads × head_dim × 2 B, de los `config.json` oficiales:

| Modelo | Capas full-attn | KV/token f16 | 512k con KV q8_0 | Pesos | Total |
|---|---|---|---|---|---|
| Qwen3.8-27B (razonador actual) | 16 × 4 | 64 KB | 16 GB | 17,4 GB | **no cabe** (256k ya necesita q4_0) |
| **Qwen3.5-9B** abliterated, con visión | 8 × 4 | 32 KB | 8 GB | 9,5 GB Q8_0 | **~18,5 GB, cabe** |
| Qwen3.6-35B-A3B (coder, MoE) | 10 × 2 | 20 KB | 5 GB | 17 GB IQ4_XS | ~22,5 GB, justo |

Los tres están entrenados a 262 144; 512k exige YaRN ×2 (`--rope-scaling yarn --rope-scale 2 --yarn-orig-ctx 262144`) con pérdida en recuerdo lejano. Preset propuesto `reasoner-9b-512k`: Huihui-Qwen3.5-9B-abliterated Q8_0 + mmproj (en `hf-download.sh`), 1 slot, KV q8_0, YaRN ×2, `--reasoning-effort medium --reasoning-budget 16384`. Para "mucha calidad" sigue el 27B a 128-256k. **Medido 2026-10-14 (preset `reasoner-9b-512k`, sesión dotfiles-69):** 20,6 GB, carga 4,6 s, 77 tok/s en prompt corto; prueba de aguja con 411 734 tokens (README ×12, tres frases al 8/50/92 %): las tres exactas, prefill 292 s (1 409 tok/s), generación 28,5 tok/s a ese contexto. La plantilla de Qwen3.5 también rechazaba el `system` a mitad de turno de Claude Code → `qwen3.5-system-anywhere.jinja`.

## 7. Un solo servidor: modo router de llama-server

`llama-server --models-preset presets.ini --models-max 1 --models-dir /var/lib/llama-server/models` (en la imagen b11580) carga el modelo que nombra cada petición y descarga el anterior; `GET /models` lista todos con `loaded/unloaded`. El selector `/model` de Claude Code (alias → nombres de preset distintos), la lista de OpenCode y el widget de Waybar hablan del mismo nombre y cambiar desde cualquiera cambia el modelo cargado; `ai preset` queda como capa fina. Decisión pendiente (afecta a F1).

## Referencias

- llama.cpp `tools/server/README.md` (router mode, presets INI, `/v1/systemone`, sleeping on idle); blog "New in llama.cpp: Decision Models" (ggml-org).
- Fichas: `jaredpalmer/kev` README + `docs/model-cards/kev-9b.md`; `convaiinnovations/laya` (0,36 zero-shot vs 0,77 afinado); `turintech/pplx-decider-27B-Artemis-GGUF`; `ggml-org/Clef-GGUF`.
- Valve Steamworks (anticheat en espacio de usuario bajo Proton; kernel no soportado); ProtonDB 3393110 = platinum (67 informes, 2026-10-14).
- "A Survey on LLM-Based Game Agents" (arXiv 2404.02039); "Augmentations for Robust and Efficient Imitation Learning in Streamed Video Games" (arXiv 2607.14200); Imitation-player (BC/DAgger/GAIL sobre capturas).
- Memorias: `project_ai_hid_game_control`, `project_desk_proton_aion-2`, `project_desk_meter_daemon_service`, `reference_nas_decision_models_systemone`; meter: `reference_login_family_protocol`, `reference_live_player_state`.
