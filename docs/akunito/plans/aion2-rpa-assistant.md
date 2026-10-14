---
id: akunito.plans.aion2-rpa-assistant
summary: Plan de implementación (sin implementar aún) del asistente RPA para Aion 2 en DESK — bus de estado local (meter + evdev + frames), orquestador aion-brain, asesor en overlay/voz, inyector uinput aion-assist con escalera sombra→asistido→rutinas, dataset y entrenamiento de Kev-4B en el NAS, presets de la 3090, tickets por fase; objetivo declarado de Diego: aprender RPA/asistentes, no un bot desatendido
tags: [aion2, rpa, uinput, evdev, meter, nas, rtx3090, kev, laya, clef, whisper, piper, plan]
tickets: []
date: 2026-10-14
status: draft
related_files:
  - docs/akunito/plans/aion2-capture-pipeline.md
  - docs/akunito/plans/nas-3090-ai-presets.md
  - system/app/aion2-meter-daemon.nix
  - system/app/ai-presets.nix
  - system/app/llama-server.nix
  - user/wm/sway/scripts/gamescope-wrapper.sh
---

# Asistente RPA para Aion 2 — plan de implementación

Investigación previa: `aion2-capture-pipeline.md`. Decisión de Diego (2026-10-14): el riesgo del lado servidor se acepta, no habrá bot desatendido; el objetivo es **aprender RPA y asistentes** sobre un juego real. Este plan no implementa nada: define componentes, contratos, fases y qué se mide para darlas por hechas. Lo audita Fable antes de tocar código.

## 1. Arquitectura

```
DESK (NixOS, Sway, gamescope + Proton)                      NAS (RTX 3090)
─────────────────────────────────────────                   ───────────────────────────
aion2-meter-daemon ──/run/aionmeter.sock──┐                 llama-server (docker-cuda)
aion-evdev (user svc, /dev/input ro) ─────┤  JSONL bus       ├ reasoner / qwen3.5-9b VLM
aion-frames (grim 1 fps, opcional) ───────┼─► aion-brain ◄──HTTP (tailscale)── kev-4b-aion / clef / laya
aion-assist (uinput, socket) ◄────────────┘  (orquestador)   whisper.cpp (docker)
      ▲                                          │            aion-train (docker python, bajo demanda)
   kill switch (evdev físico)         overlay/TTS (piper)     /var/lib/aion-capture (sesiones, datasets)
```

Reglas de diseño:
- **Todo lo que necesita latencia baja vive en DESK** (bus, reflejos, inyección, overlay, TTS). El NAS solo sirve modelos y entrena. Si el NAS duerme, el asistente degrada a reglas + overlay sin LLM, nunca se bloquea.
- **Un solo bus JSONL por sesión**, cada productor con `src` propio; `aion-brain` es el único consumidor en vivo y el único que escribe acciones. Ningún componente nuevo toca el meter; el meter solo gana un ticket (A2M) si falta un campo.
- **Toda entrada inyectada se registra en el mismo bus** con `src=assist`, así el dataset distingue humano/máquina y el modo sombra se mide solo.
- **Nada de píxeles en el bucle rápido.** Frames muestreados sirven al dataset y a preguntas bajo demanda.

## 2. Componentes y contratos

### 2.1 Bus y sesiones (`aion-capture`, DESK)
- Directorio `~/.local/share/aion-capture/<session_id>/` (NVMe de DESK), `session_id = YYYYMMDD-HHMMSS-<char>`. Abre cuando el meter informa del login (identity packet); cierra a 10 min sin posición ni paquetes. `rsync` al NAS (`/var/lib/aion-capture/`) al cerrar y cada hora (user timer); retención DESK 7 días, NAS: eventos para siempre, frames 3 días salvo marcados.
- Ficheros: `events.jsonl` (todo), `state.jsonl` (snapshots 5 Hz derivados), `actions.jsonl` (humanas y virtuales), `frames/<t_mono_ms>.jpg`, `meta.json` (char, server, versión del meter, hash de settings).
- Evento: `{"t":<mono_ns>,"w":<wall_ms>,"src":"meter|evdev|frame|assist|brain","type":"...","d":{...}}`. Snapshot: `{"t","pos":[x,y,z],"zone","hp","hp_max","mp","target":{"id","name","hp_pct"},"combat":bool,"cd":{skill_id:ms},"buffs":[...],"quest":{"id","step"},"bag_free":n}` — los campos que el meter no exponga quedan `null` y abren ticket A2M.

### 2.2 `aion-evdev` (DESK, user service)
- python-evdev 1.9.3 (nixpkgs); abre en lectura todos los `/dev/input/event*` con capacidad KEY/REL (akunito ∈ `input`), sin `grab`. Emite `key {code,val}` y `rel {dx,dy}` agregados a 100 Hz; marca `phys: true|false` por `device.phys` (los uinput no tienen `phys`). Hotkey global de **kill switch**: cualquier evento físico mientras `aion-assist` ejecuta una rutina → manda `abort` por el socket.
- Coste medido a alcanzar: < 1 % CPU de un core. Privacidad: solo graba con una sesión abierta (el meter dice que el juego está delante); fuera de sesión no abre dispositivos.

### 2.3 `aion-frames` (DESK, user service, opcional por flag)
- `grim -o DP-1 -t jpeg -q 70 -s 0.5` a 1 fps (≈ 150 KB, 1920×1080 desde 4K) → `frames/`. Medir el impacto en FPS del juego con `mangoapp` antes de dejarlo fijo; si > 2 % se baja a 0,5 fps o se mueve a captura por evento (boss, muerte, menú). Vídeo continuo: no en v1 (wf-recorder VAAPI es la opción si hace falta, Elgato solo si se quiere sin coste en DESK).

### 2.4 `aion-brain` (DESK, user service, python)
- Entradas: cliente del socket del meter (`overlay`, `position`, `fight-closed`, `boss-alert` a 5 Hz/1 Hz), socket de `aion-evdev`, directorio de frames, hotkey/voz. Salidas: `state.jsonl`, overlay, TTS, acciones a `aion-assist`.
- **Reglas (reflejos, < 10 ms):** tabla declarativa en YAML (`when: hp_pct < 0.3 and combat → say("pot")`, `when: assist.running and evdev.phys → assist.abort`). Sin modelo.
- **Decisión macro (50-200 ms):** `POST /v1/systemone` al NAS con el estado de los últimos 5-10 s como `state` y preguntas fijas: `next_skill` (choice sobre skills equipadas), `target_priority` (score 0-3), `retreat` (noul), `open_menu` (choice). Umbral de confianza configurable; por debajo, no propone.
- **Planificación/charla (2-5 s):** `/v1/chat/completions` (razonador o Qwen3.5-9B con frame) con RAG sobre las guías (índice `_src/search` de `docs/aion2-site`, ya construido para la web) y la ficha del personaje (JSON del meter).
- **Salida:** overlay propio GTK4 layer-shell mínimo (una tarjeta de texto, `above_fullscreen` como el meter; toplevel si Diego quiere moverla) y `piper-tts` 1.8.0 (voz es-ES, nixpkgs). Voz de entrada: whisper.cpp 1.9.5 en el NAS (preset) o en DESK CPU si el NAS duerme.
- **Modos:** `off` · `advise` (parte A) · `shadow` (propone y mide acuerdo con lo que haces) · `assist` (una tecla ejecuta la propuesta) · `routine <nombre>` (menús). Se cambian por hotkey y por `aion-brain mode X`; el modo actual se ve en la tarjeta.

### 2.5 `aion-assist` (DESK, user service, python)
- `evdev.UInput` crea un teclado y un ratón **relativo** virtuales (akunito tiene `rw` en `/dev/uinput` por ACL de logind, medido 2026-10-14). Socket unix `$XDG_RUNTIME_DIR/aion-assist.sock`, JSON por línea: `{"op":"act","action":"skill","args":{"slot":3}}`, `{"op":"abort"}`, `{"op":"status"}`.
- Acciones macro v1: `skill <slot>`, `target_next`, `move <fwd|back|left|right> <ms>`, `turn <dx>`, `interact`, `open <bag|map|quest|warehouse>`, `close`, `click <x,y rel>`. Cada una se expande a eventos con tiempos muestreados de la **distribución real** de `aion-evdev` (hold de tecla, gaps, overshoot del ratón); nunca tiempos fijos.
- Seguridad: cola de una acción; `abort` vacía la cola y suelta todas las teclas (`SYN` + key-up de todo lo pulsado); watchdog 2 s sin heartbeat de `aion-brain` = abort; límite de acciones/min configurable; todo evento inyectado se publica en el bus con `src=assist`.
- Rutinas v1 (parte "navegar la UI para capturar datos" que antes era de la Pico): `capture_bag`, `capture_warehouse`, `capture_quests`, `capture_market_search <item>` — abren el menú, esperan el paquete del meter que confirma el contenido (el meter re-manda el contenedor entero al abrirlo), cierran. Éxito = el JSON del meter se actualizó; fallo = timeout → abort.

### 2.6 Modelos en el NAS
| Preset | Modelos | VRAM | Uso |
|---|---|---|---|
| `aion-advise` | Qwen3.5-9B abliterated + mmproj (chat/VLM) + Laya o Kev-4B + whisper.cpp | ~11 + 5 (Kev-4B Q8) + 1,5 ≈ 18 GB (estimado, medir) | asesor + decisión macro |
| `aion-train` | nada cargado en llama-server; `aion-train` docker (peft/transformers) usa toda la tarjeta | hasta 24 GB | entrenar Kev-4B |
| `kev-4b-aion` | el Kev afinado, GGUF, `/v1/systemone` | ~5 GB | decisión macro en producción |
Con el modo router (`--models-max 2`) `aion-advise` son dos modelos cargados a la vez; sin router, un preset compuesto. Decidir con dotfiles-69 (F1 v2).

### 2.7 Dataset y entrenamiento (`aion-train`, NAS docker)
- Conversor `session → kev.jsonl`: por cada ventana de 2 s en combate (y por cada acción humana) un registro `{state_text, questions{next_skill: choice[...], target_priority: score, retreat: noul}, answers}`; la respuesta = lo que hizo Diego en los 1,5 s siguientes (del bus: paquete de skill lanzada o evdev). Estado en texto compacto (≤ 600 tokens): snapshot + últimos 5 eventos + cooldowns.
- Entrenamiento: `kev.train --init_from jaredpalmer/kev-4b` con split por sesión (nunca por registro), calibración de temperatura en held-out, exporta GGUF (`convert_hf_to_gguf` del repo de Kev o el flujo de ggml-org) → `/var/lib/llama-server/models/kev-4b-aion-<fecha>.gguf`.
- Métricas que cierran la fase: acuerdo top-1 en held-out ≥ 0,70 (Kev-4B base está en ~0,5 en dominios nuevos según su ficha), Brier mejor que la base, y en **modo sombra en vivo** acuerdo ≥ 0,6 durante 3 sesiones antes de activar `assist`.

## 3. Fases y tickets (crear en Plane al aprobar; AINF para dotfiles, A2M para el meter)

| Fase | Entregable | Hecho cuando | Ticket |
|---|---|---|---|
| R0 | Bus + sesiones: `aion-capture` (flag `aionCaptureEnable`), `aion-evdev`, cliente del socket del meter en `aion-brain` escribiendo `events/state.jsonl`; rsync al NAS | una sesión de 1 h grabada, `state.jsonl` con pos/hp/target/cd rellenos (o tickets A2M por cada `null`), < 1 % CPU | AINF-nuevo, A2M-nuevo (campos) |
| R1 | Reglas + overlay + TTS (`advise` sin LLM) | 5 reglas útiles (pociones, boss, bolsa llena, cooldown largo, muerte) sonando en juego, 0 falsos positivos en 2 sesiones | AINF |
| R2 | Asesor con modelos: preset `aion-advise`, RAG guías, voz | pregunta por voz → respuesta hablada < 5 s con el NAS despierto; degradación limpia dormido | AINF |
| R3 | `aion-assist` + modo sombra + kill switch | 100 acciones inyectadas sin un solo key stuck; abort < 50 ms; evdev distingue 100 % virtual/físico | AINF |
| R4 | Dataset + Kev-4B v1 + sombra en vivo | métricas de 2.7 | AINF (train), A2M (export) |
| R5 | `assist` y rutinas de captura de UI (bolsa, almacén, quests, mercado) | las 4 rutinas actualizan el JSON del meter 10/10 veces | AINF, A2M |
| R6 | REA → tabla de opcodes → parsers del meter (HP/MP, buffs, cooldowns, party, inspect) | `opcodes.json` + tests de replay en el meter | A2M |

R6 corre en paralelo desde R0 (es el proyecto del meter). Cada fase: medir, anotar en este doc, memoria, commit; el widget de Waybar se actualiza cuando cambian presets (regla 2026-10-14) y antes de cada despliegue se pregunta por otras sesiones.

## 4. Riesgos y decisiones abiertas

- **Campos ausentes en el meter** (HP/MP propios, cooldowns, buffs): bloquean las reglas de R1 y el dataset de R4. Mitigación: R0 lo descubre en la primera sesión; REA (R6) es la vía sistemática; OCR solo como parche puntual.
- **FPS**: `grim` a 1 fps y el overlay GTK sobre gamescope tienen coste; medir con `mangoapp` en R0 y fijar presupuesto (≤ 2 % FPS).
- **Horario del NAS** (S3 23:00-16:00): el asesor con LLM solo con el NAS despierto; `aion-brain` debe poder despertarlo (WoL, pendiente de F1) y vivir sin él.
- **Distribución de inputs**: un jitter mal muestreado se nota (y aprende mal); el muestreo viene del propio registro evdev, nunca de constantes.
- **Modo router vs presets compuestos** (F1 v2): decidir antes de R2.
- **Parches del juego**: opcodes y UI cambian; el bus guarda la versión del cliente en `meta.json` y el dataset se etiqueta por versión.
- **Seguridad de `aion-assist`**: socket solo para el usuario, sin red; watchdog y límite de acciones; el `abort` físico siempre gana.

## 5. Lo que NO se hace

Autonomía en combate sin sombra previa; captura de vídeo continua en v1; leer memoria del proceso salvo que REA lo exija para desempaquetar; dependencias instaladas fuera de nix/docker; modificar el meter desde este repo (solo tickets A2M).
