---
id: akunito.plans.aion2-rpa-assistant
summary: Plan de implementación (sin implementar aún, v2 tras auditoría Fable) del asistente RPA para Aion 2 en DESK — bus de estado local (meter + evdev + frames por evento), orquestador aion-brain, asesor por notificaciones/voz, inyector uinput aion-assist con escalera sombra silenciosa→asistido→rutinas, dataset y entrenamiento de Kev en el NAS, presets de la 3090, fases R0-R6 con criterios medibles; objetivo de Diego: aprender RPA/asistentes, no un bot desatendido
tags: [aion2, rpa, uinput, evdev, meter, nas, rtx3090, kev, laya, clef, whisper, piper, plan]
tickets: [AINF-409, AINF-410, AINF-411, AINF-412, AINF-413, AINF-414, A2M-51, A2M-52]
date: 2026-10-14
status: draft
related_files:
  - docs/akunito/plans/aion2-capture-pipeline.md
  - docs/akunito/plans/nas-3090-ai-presets.md
  - system/app/aion2-meter-daemon.nix
  - system/app/ai-presets.nix
  - system/app/llama-server.nix
  - system/app/nas-services.nix
  - user/wm/sway/scripts/gamescope-wrapper.sh
  - user/wm/sway/session-env.nix
---

# Asistente RPA para Aion 2 — plan de implementación (v2, auditado)

Investigación previa: `aion2-capture-pipeline.md`. Decisión de Diego (2026-10-14): el riesgo del lado servidor se acepta, no habrá bot desatendido; el objetivo es **aprender RPA y asistentes** sobre un juego real. Este plan no implementa nada. La v1 fue auditada por Fable el 2026-10-14 (veredicto "aprobar con cambios"); esta v2 incorpora todas sus correcciones, resumidas en §6.

## 1. Arquitectura

```
DESK (NixOS, Sway, gamescope + Proton)                       NAS (RTX 3090)
──────────────────────────────────────────                   ──────────────────────────────
aion2-meter-daemon ──/run/aionmeter.sock──┐                  llama-server (docker-cuda, router)
aion-evdev (user svc, /dev/input ro) ─────┤  bus JSONL        ├ qwen3.5-9b (chat+VLM) · reasoner
aion-frames (grim por evento) ────────────┼─► aion-brain ◄──HTTP tailscale── kev-4b-aion (/v1/systemone)
aion-assist (uinput, socket) ◄────────────┘  (orquestador)    whisper-server (docker, puerto propio)
      ▲ abort directo (< 50 ms)                   │           aion-train.service (docker python, bajo demanda)
   evdev físico (KEY, REL > 8 px)      swaync + piper (voz)   /var/lib/aion-capture (sesiones, datasets)
```

Reglas de diseño:
- **Latencia baja = DESK** (bus, reflejos, inyección, notificaciones, TTS). El NAS solo sirve modelos y entrena. Si el NAS duerme, el asistente degrada a reglas + voz ("NAS dormido"), nunca se bloquea.
- **Un bus JSONL por sesión**; `aion-brain` es el único consumidor en vivo. **Dos caminos de abort**: el directo `aion-evdev → aion-assist` es el autoritativo (< 50 ms); la regla en `aion-brain` es respaldo.
- **Toda entrada inyectada se registra en el bus** con `src=assist` y el devnode del dispositivo virtual; el dataset excluye esas ventanas.
- **Nada de píxeles en el bucle rápido**; frames solo por evento (boss, muerte, menú) y bajo demanda.
- **Clave de unión = `w` (wall ms)** en todo el bus: evdev marca con CLOCK_REALTIME y el meter exporta `unixMs`; `t` (mono) solo para latencias dentro de un proceso.

## 2. Componentes y contratos

### 2.1 Bus y sesiones (`aion-capture`, DESK)
- `~/.local/share/aion-capture/<session_id>/`, `session_id = YYYYMMDD-HHMMSS-<char>`. **Apertura**: cambio de mtime de `state/summary.json` del meter con `character` presente (el socket no emite identidad), o primer `position` si tarda; **cierre**: 10 min sin `position`; al arrancar, toda sesión sin `meta.json.closed` se cierra con el último `w` de `events.jsonl`. Foco del juego por **Sway IPC** (`get_tree`, `app_id` de gamescope, como el wrapper): sin foco no se graban teclas.
- Ficheros: `events.jsonl`, `state.jsonl` (snapshots 5 Hz), `actions.jsonl`, `frames/` (evento `{src:frame,w_start,w_end,file}`), `meta.json` (char, server, versión del cliente y del meter, `keymap.json` tecla→slot, `questions.json` versión, `closed`).
- Evento: `{"w":<wall_ms>,"t":<mono_ns>,"src":"meter|evdev|frame|assist|brain","type":"...","d":{...}}`. Snapshot: `{"w","pos","zone","hp","hp_max","mp","target":{"id","name","hp_pct"},"combat","cd":{slot:ms},"buffs","bag_free"}`; hoy el meter solo da posición, combate/daño, objetivo y bosses; **hp/mp/cd/buffs son `null` hasta R6** y así se registra.
- Copia al NAS: escribir en el export NFS ya montado (no `rsync` por ssh: una unidad de usuario no hereda `SSH_AUTH_SOCK`), con la trampa conocida del NAS apagado (`reference_nfs_offline_nas_hang`): copia solo si el mount responde (`timeout 5 stat`), al cerrar sesión y cada hora. Retención: DESK 7 días; NAS eventos para siempre, frames 3 días salvo marcados.

### 2.2 `aion-evdev` (DESK, user service)
- `python3Packages.evdev` 1.9.3; abre en lectura los `/dev/input/event*` con KEY/REL (akunito ∈ `input`), sin `grab`, **con inotify en `/dev/input`** para reabrir en caliente (el UInput de `aion-assist` aparece después). Emite `key {code,val}` y `rel {dx,dy}` agregados a 100 Hz. **Virtual vs. físico por devnode**: `aion-assist` publica su `/dev/input/eventN` en el bus (los UInput de evdev traen `phys='py-evdev-uinput'`, no sirve como criterio) y además se crea con `bustype=BUS_VIRTUAL` y nombre fijo.
- **Kill switch**: solo `KEY` físicos y `REL` con |d| acumulado > 8 px en 50 ms (el ruido de 1 px no aborta); la tecla disparadora de `assist` se ignora 300 ms tras su key-up. Envía `abort` directo al socket de `aion-assist`.
- Solo graba con sesión abierta y foco en el juego. Coste objetivo: < 1 % de un core (`systemd-cgtop` sobre 1 h).

### 2.3 `aion-frames` (DESK, user service, flag aparte)
- `grim -o <monitor> -t jpeg -q 70 -s 0.5` **por evento** (boss-alert, muerte, apertura de menú, petición de voz), no continuo; cada captura se registra con `w_start/w_end` (grim a 4K tarda decenas de ms). Medir el impacto en FPS con `mangoapp` antes de ampliar; 1 fps continuo solo si cuesta ≤ 2 %.

### 2.4 `aion-brain` (DESK, user service, python `asyncio`)
- Entradas: socket del meter (`overlay`, `position`, `fight-closed`, `boss-alert`; **reconexión con backoff**: un restart del daemon borra el socket), socket de `aion-evdev`, frames, push-to-talk. Salidas: `state.jsonl`, notificaciones, TTS, acciones a `aion-assist`, heartbeat a `aion-assist` **en su propio task** (nunca en el hilo de las llamadas HTTP).
- **Reglas (< 10 ms)**: YAML declarativo. v1 = 3 reglas con datos que existen hoy: boss (`boss-alert`), muerte (`fight-closed` + posición), bolsa llena (`inventory.json`). Pociones y cooldowns llegan con R6.
- **Decisión macro (50-200 ms, desde R4)**: `POST /v1/systemone` con timeout de conexión 1 s y total 0,3 s; preguntas de un `questions.json` versionado **compartido con el conversor** (`next_skill` choice = slots de `8c e2`/`00 39` en orden fijo, `target_priority` score 0-3, `retreat` noul). Bajo el umbral de confianza no propone.
- **Chat/planificación (2-5 s)**: `/v1/chat/completions` (Qwen3.5-9B con frame, o el razonador) + RAG propio: chunks del markdown de `~/Projects/aion2-guides` + embeddings (Pagefind del sitio es WASM para el navegador, no se consulta desde Python); ficha del personaje del JSON del meter.
- **Salida v1 = `notify-send` → swaync** (ya corre como unidad de usuario; verificar una vez que se ve sobre gamescope) + `piper-tts` 1.8.0 con voz `es_ES-*.onnx` de rhasspy/piper-voices (sha256 en un script como `hf-download.sh`). Overlay GTK propio: fuera de v1; la tarjeta del meter es la opción 2 vía ticket A2M.
- **Voz de entrada**: push-to-talk por hotkey → `pw-record` → whisper-server en el NAS; respaldo en DESK con el whisper.cpp de `meetingTranscribeEnable`, modelo `base` en **CPU** (Vulkan competiría con el juego).
- **Modos**: `off` · `advise` · `shadow` (**silencioso**: la propuesta va al bus, no a pantalla, para medir predicción y no aceptación) · `assist` (una tecla ejecuta la propuesta) · `routine <nombre>`. Hotkey + `aion-brain mode X`; el modo se ve en la notificación persistente.

### 2.5 `aion-assist` (DESK, user service, python)
- `evdev.UInput` (teclado + ratón relativo, `BUS_VIRTUAL`); publica su devnode en el bus al arrancar. Acceso: hoy la ACL `uaccess` viene de la regla udev de **Steam** (`60-steam-input.rules`) y akunito **no está en `uinput`** → añadir `uinput` a `extraGroups` tras el flag; no depender de la ACL.
- Socket `$XDG_RUNTIME_DIR/aion-assist.sock` (solo usuario): `{"op":"act","action":"skill","args":{"slot":3}}`, `{"op":"abort"}`, `{"op":"status"}`, `{"op":"heartbeat"}`.
- Acciones v1: `skill <slot>`, `target_next`, `move <dir> <ms>` (interrumpible a mitad del hold), `turn <dx>`, `interact`, `open <bag|warehouse>`, `close`. **Sin `click`** (ratón relativo sin lectura del cursor deriva; en modo cámara el cursor va capturado). Tiempos muestreados de la **distribución real** de `aion-evdev` (hold, gaps, overshoot), nunca constantes.
- Seguridad: cola de una acción; `abort` vacía la cola y emite key-up de todo lo pulsado + `SYN`; watchdog 2 s sin heartbeat = abort; límite de acciones/min; la rutina de `assist` arranca en el **key-up** de la tecla disparadora.
- Rutinas v1: **solo `capture_bag` y `capture_warehouse` (junto al NPC)**, verificables porque el meter re-manda el contenedor al abrirlo (`Seen[c].fullMs` en `inventory.json`). Quests y mercado no van por paquetes (quests = datos de cliente; mercado = HTTPS): fuera de v1, como mucho verificación por frame + Clef ("¿ventana de quest abierta?").

### 2.6 Modelos en el NAS
- **Decisión tomada para este plan: modo router de llama-server** (`--models-preset`, `--models-max 2`, sin `-m`) — se resuelve en R0 con la sesión que hizo F1, porque condiciona `llama-server.nix` y el widget. Sin router, un preset del gestor actual es **un** llama-server con **un** modelo, y `aion-advise` necesita dos.

| Preset / unidad | Modelos | VRAM | Fase |
|---|---|---|---|
| `aion-advise` | Qwen3.5-9B abliterated + mmproj (chat/VLM) y, desde R4, `kev-4b-aion`; whisper-server aparte | ~11 + 6-7 (Kev-4B f16 ctx 16k, **medir**) + 1,5 ≈ 19-20 GB | R2 (solo Qwen3.5-9B), R4 |
| `aion-train.service` | `ai preset set off` + contenedor pytorch/peft (CDI como `llama-server.nix`, `Conflicts=sleep.target`); imagen (~10 GB) se trae **a mano** una vez, nunca dentro del job | hasta 24 GB | R4 |
| `kev-4b-aion` | Kev afinado, GGUF, `/v1/systemone` | medir | R4+ |
- Firewall tailscale0 hoy: 8090 (llama) y 8093 (estado de presets); añadir el puerto de whisper-server. Unidad propia para whisper y train, no compose (`nasRootDockerProjects` es lista cerrada).
- **Inhibidor de S3**: `nas-suspend` dispara a las 23:00 y nada impide dormir en mitad de una sesión; `aion-brain` manda un inhibidor (`systemd-inhibit` por ssh o endpoint del gestor de presets) mientras la sesión está abierta, y WoL del NAS no funciona hoy → R2 "con el NAS despierto" se juega antes de las 23:00 hasta que F1 resuelva el despertar.

### 2.7 Dataset y entrenamiento (`aion-train`, NAS docker)
- **Antes de entrenar (gate)**: convertir el Kev-4B base publicado a GGUF con nuestro flujo (fundir LoRA con `merge_and_unload` + `convert_hf_to_gguf`) y comprobar que `GET /v1/models` lo anuncia como `output_modalities: ["decisions"]` y responde igual que `ggml-org/Kev-4B-GGUF` a la prueba de humo. Si no, nada de R4 se sirve.
- Conversor `session → kev.jsonl`: ventanas de 2 s en combate y cada acción humana → `{state_text ≤ 600 tokens, questions (de questions.json), answers}`; respuesta = skill lanzada (paquete) o tecla→slot (`keymap.json`) en los 1,5 s siguientes; **se excluyen** ventanas con acción `assist` en ±1,5 s y las sesiones en modo `shadow` visible. Split **por sesión**; temperatura calibrada en held-out; ECE reportado.
- Métricas de cierre: top-1 ≥ 0,70 en held-out por sesión, Brier < base, y **sombra silenciosa** 3 sesiones: propuesta ≥ 0,5 s antes de la acción humana con el mismo skill ≥ 0,6. Línea base única: la de la ficha de Kev-4B (verificar id HF y cifra antes de R4; descargar con `hf-download.sh`).

## 3. Fases y criterios de cierre (tickets creados 2026-10-14: R0 AINF-409 · R1 AINF-410 · R2 AINF-411 · R3 AINF-412 · R4 AINF-413 · R5 AINF-414 · R6a A2M-51 · R6b A2M-52)

| Fase | Entregable | Hecho cuando (medible) |
|---|---|---|
| **R6a** (primero, en paralelo con R0) | REA → `opcodes.json` → parsers del meter para HP/MP, cooldowns, buffs | `opcodes.json` + replay en el gate del meter (`build.sh`, tests + login pcap) con asserts de HP/MP/cooldown |
| **R0** | Bus + sesiones: flags, `aion-evdev`, cliente del socket del meter en `aion-brain`, `state.jsonl`, copia al NAS por NFS | 1 h de sesión; 20 skills pulsadas a mano, cada una con su paquete ≤ 300 ms después en el bus; `aion-evdev`+`aion-brain` < 1 % de un core en `systemd-cgtop`; la sesión está en el NAS |
| **R1** | 3 reglas (boss, muerte, bolsa llena) → swaync + piper | cada disparo guarda su snapshot; hotkey "mal" de Diego; FP ≤ 5 % sobre ≥ 50 disparos en 2 sesiones |
| **R2** | Asesor: preset `aion-advise` (solo Qwen3.5-9B), RAG propio, voz, inhibidor S3 | p90 < 5 s en 20 preguntas (`ptt_down` → `tts_start` en el bus); con el NAS apagado las reglas siguen y la voz dice "NAS dormido" ≤ 2 s |
| **R3** | `aion-assist` + kill switch + modo sombra silencioso | banco fuera del juego (`wev`/kitty en DP-2): 100 acciones, conjunto de teclas pulsadas vacío ≤ 100 ms tras cada una; abort < 50 ms (evdev físico → último key-up en el bus); 1 000 eventos inyectados, 100 % marcados virtuales por devnode |
| **R4** | Gate GGUF, dataset, Kev-4B v1, sombra silenciosa | métricas de §2.7 |
| **R5** | `assist` + rutinas `capture_bag`/`capture_warehouse` | `Seen[c].fullMs` sube 10/10; timeout → abort con teclas sueltas comprobadas por `aion-evdev` |
| **R6b** | Resto de opcodes (party, inspect) y lo que R1-R5 hayan pedido | replay + asserts en el meter |

Primer resultado útil (un asesor que dice algo verdadero en juego) = R0 → R1 con las 3 reglas de hoy → R2. Cada fase: medir, anotar aquí y en la memoria del proyecto que toque (meter → `aion2-dps-meter`), commit; widget de Waybar al día cuando cambian presets; antes de desplegar, preguntar por otras sesiones.

## 4. Convenciones a respetar en la implementación
- Flags en `lib/defaults.nix` a `false`: `aion2AssistantEnable`, `aion2AssistantEvdevEnable`, `aion2AssistantFramesEnable`, `aion2AssistantAssistEnable`, `aion2AssistantMonitor` (default `"DP-1"` como `aion2MeterOverlayMonitor`), `aion2AssistantNasUrl`, `aion2AssistantWhisperUrl`; nunca `DP-1` ni `100.64.0.1` literales en módulos; documentar en `docs/profile-feature-flags.md`.
- Módulos en `user/app/aion2-assistant/` (no en `user/wm/sway/`); unidades de usuario con `PartOf=sway-session.target` + `EnvironmentFile=%t/sway-session.env`; un solo gestor de ciclo de vida.
- Sin toolchains en el host: `python3Packages.{evdev,pyyaml,requests}` de nixpkgs; sin PyGObject/GTK; entrenamiento solo en docker en el NAS.
- Despliegue: DESK `./deploy.sh --profile DESK`; NAS `install.sh … -s -d`; toda unidad nueva del NAS con GPU lleva `Conflicts=sleep.target`.

## 5. Lo que NO se hace en v1
Autonomía en combate sin sombra previa; vídeo continuo; `click` por ratón relativo; rutinas de quests/mercado; overlay GTK propio; leer memoria del proceso salvo que REA lo exija para desempaquetar; dependencias fuera de nix/docker; modificar el meter desde este repo (solo tickets A2M).

## 6. Auditoría Fable 2026-10-14 — qué cambió de v1 a v2
Errores de hecho corregidos: apertura de sesión por `state/summary.json` (el socket no emite login); virtual/físico por devnode (los UInput sí traen `phys`); grupo `uinput` en vez de confiar en la ACL de Steam; `aion-train` como unidad propia y `aion-advise` exige router (un preset = un llama-server con un modelo; no hay whisper en el NAS); RAG propio (no existe `_src/search`, el sitio usa Pagefind WASM); rutinas limitadas a bolsa/almacén (quests y mercado no van por paquetes); una sola línea base de Kev y VRAM de Kev-4B "a medir". Fallos de diseño arreglados: kill switch con umbral (no aborta por 1 px), rutina en key-up + 300 ms de gracia, inotify para ver el dispositivo virtual, heartbeat en task propio con timeouts cortos, unión por wall-clock, foco por Sway IPC, sombra silenciosa y exclusión de ventanas `assist` del dataset, `questions.json` compartido, abort directo autoritativo, sin `click`. Piezas añadidas: inhibidor de S3, firewall de whisper, copia por NFS, reconexión al socket, cierre tras crash, gate de export GGUF, imagen de entrenamiento a mano, voces piper, push-to-talk con respaldo CPU, `keymap.json`, decisión router en R0. Reordenado: R6a (HP/MP/cooldowns) delante de R1; Kev/Laya fuera de R2; frames por evento; overlay GTK fuera de v1. Criterios de cierre reescritos para ser medibles.
