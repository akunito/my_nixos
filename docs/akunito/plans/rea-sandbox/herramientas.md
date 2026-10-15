---
id: akunito.plans.rea-sandbox.herramientas
summary: Herramientas de REA con versiones nixpkgs vs requeridas, motores comerciales (Hopper, IDA, JEB) y cadena de suministro/actualizaciones
tags: [rea, ghidra, nix, hopper, ida, jeb, supply-chain]
date: 2026-10-14
status: draft
related_files:
  - docs/akunito/plans/rea-sandbox/README.md
---

# REA: herramientas

Parte del plan [REA en un sandbox](README.md).

## Herramientas

nixpkgs (`nixos-unstable` del `flake.lock` actual) frente a lo que exige REA, comprobado en `src/`.

| Herramienta | REA | nixpkgs | Acción | Fase |
|---|---|---|---|---|
| Ghidra | 12.1.x (12.1.4 verificada) | 12.1.4 ✓ | `withExtensions` para PSP | F1 |
| JDK / Node | 21 / `^24.11` | 21.0.12 ✓ / 24.21.0 ✓ | — | F1 |
| rea-agents | 6.4.0 | fork + `buildNpmPackage` | ver decisión 5 del README | F1 |
| objdump / Rizin | sin comprobación de versión | 2.46 / 0.9.1 ✓ | — | F1 |
| pwntools | 4.15.0 | 4.15.0 ✓ | — | F1 |
| WABT | **exige banner `1.0.42`** (`WabtArtifactProvider.ts:222-228`) | 1.0.41 ✗ | **hecho F4:** override a 1.0.42 (`env.nix`) | F4 ✓ |
| TShark + capinfos | major 4 | 4.6.9 ✓ | — | F1 |
| prlimit, ps | ruta absoluta / en PATH | util-linux, procps ✓ | variables | F1 |
| mitmproxy | 12.2.3 | 12.2.3 ✓ | — | F1 (grabados), F3 (en vivo) |
| jadx-headless-mcp | 0.7.1, sha256 en `src/android/JadxRelease.ts` | `fetchurl` | **hecho F4:** el mismo sha256; auditado (Fable): JAR del CI del autor, sin nativos, REA lo usa por stdio | F4 ✓ |
| Apktool | ≥ 2.7.0 | 3.0.3 ✓ | — | F1 |
| ilspycmd | — | 9.1 | — | F1 |
| Binwalk / Unblob | 3.1.0 / 26.6.4 | ✓ / ✓ | — | F1 |
| DIE, UPX, YARA, file | — | 3.21 / 5.2.1 / 4.5.7 | triaje | F1 |
| Chromium | Chrome-family | 155 | carril web | F3 |
| Wakaru | ^1.13 (1.14.0 verificada) | binario oficial | **hecho F4:** release del CI por hash + autoPatchelf; auditado (Fable): Rust, sin código de red | F4 ✓ |
| GDB + pwndbg | pwndbg 2026.09.15 (`55596aa6`), venv + `gdbinit.py` | 17.2 ✓; pwndbg no está en nixpkgs | **hecho F4:** input del flake fijado al commit de REA (uv2nix, su `uv.lock`); el adaptador de crashes también exige pyelftools 0.33 y unicorn 2.1.2 (overrides) | F4 ✓ |
| sigrok-cli | **exige `0.7.2`** (`SigrokRecordingProvider.ts:235-241`) | 0.8.0-unstable ✗ | **hecho F4:** tarball 0.7.2 sobre la libsigrok de nixpkgs (131 decoders) | F4 ✓ |
| Frida | 17.23.2 | npm opcional | derivación con prebuilt fijado por hash | F3 |
| adb + emulador | `REA_ADB_PATH` | android-tools 37.0.0 | **adb hecho F4**; emulador pendiente (KVM anidado, imagen del SDK no libre: decisión de Diego) | F4 |

**F4 (2026-10-14), probado con `rea-claude --ask` en nivel 1:**
- `inspect_wasm_artifact`: WABT 1.0.42;
- `recover_javascript_sources`: Wakaru detectó webpack5, 3 módulos;
- `inspect_signal_decoders`: 131 decoders;
- `inspect_adb_client`;
- `start_gdb_session` y `gdb_console`;
- JADX sobre un APK libre de F-Droid (`inspect_android_package`, `search_android_classes`, `inspect_android_class`);
- `inspect_recorded_crash` con el contexto de pwndbg sobre un *core* propio.

**Arreglos de la misma tanda:**
- **`REA_OBJDUMP` no existe**: la variable buena es `REA_OBJDUMP_COMMAND`.
- **Salidas grandes de REA:** Claude Code guarda las que superan unos 80k caracteres en `~/.claude-rea/projects/<caso>/…/tool-results/`, y el sandbox de Bash no podía leerlas. Ahora puede leer solo el directorio de ese caso.

## Motores comerciales (investigado 2026-10-14)

Qué pide REA a cada uno, según su código, y la vía legal más barata. Diego es un particular y el uso es personal y no comercial. Las cuentas y las compras las hace Diego; Claude no se registra ni compra nada.

| Motor | Qué necesita REA | Gratis | Límites de lo gratis | Vía de pago más barata |
|---|---|---|---|---|
| **Hopper** | Build Linux 6.4.2 demo; REA lo lanza en un Xvfb privado y pulsa "demo" (`LinuxHopper.ts`, `scripts/hopper-demo-x11.py`). Sin licencia | Demo | Sesiones de 30 min, no guarda ni exporta, sin depurador. Funciona sin red | **Personal 99 €, perpetua**: VMs permitidas, uso comercial libre, sin límite de sesión, offline |
| **IDA** | `ida-pro-mcp` (IDA Pro ≥ 8.3; headless con idalib) **o** el puente nativo `ida-free-mcp`, que funciona con IDA Free 9.x pero solo con la GUI abierta. REA lo verificó con IDA Free 9.4 en Linux (`docs/testing.md:779`) | IDA Free (cuenta My Hex-Rays + `.hexlic`) | Solo x86/x64, sin IDAPython ni idalib, no comercial. **El decompilador es en la nube**: sin red solo desensambla, y con red envía código a Hex-Rays | IDA Home 365 $/año (idalib, una familia de procesador, decompilador también en la nube). IDA Pro Essential desde 1.099 €/año |
| **JEB** | Cliente JEB sirviendo MCP en `127.0.0.1:8425` (5.41+). REA lo verificó con JEB 5.48 con licencia | Community Edition (x86/x64, API completa, uso no profesional) | **No se sabe si CE incluye el servidor MCP**: sus términos solo aparecen al instalar. Clave ligada a cuenta y máquina (hay "clave manual" offline). La EULA prohíbe dar el *output* a terceros, lo que con un LLM en la nube es zona gris | Android 140 $/mes o Pro 2.000 $/año: no merece la pena para uso personal |

Ningún programa educativo aplica: IDA Classroom es solo para instituciones.

**Decisión propuesta (F6):**
1. **Hopper demo primero.** Gratis, offline y REA ya la automatiza. Va en la imagen o la VM como segundo motor nativo. Hay que comprobar que el build Linux funciona en NixOS: con `buildFHSEnv`, o con `requireFile` si la descarga exige aceptar algo a mano. Si se usa a menudo, **Hopper Personal (99 €)** es la única compra que vale la pena.
2. **JEB CE: integrada (2026-10-15).**
   - **Paquete:** el zip 5.48 (no pide registro) está en el store por hash (`jeb.nix`, `requireFile`). Trae el servidor MCP (`jeb.jar -c --mcp`, `--interface`, `--port`, `--config=FICHERO`).
   - **Activación:** solo en casos `rea-case new … --jeb` (niveles 1 y 2, sin `--web`). Corre sin interfaz dentro de la microVM (servicio `rea-jeb`, JVM de 2 GiB; la VM pasa a 8 GiB) y REA lo usa con `REA_JEB_MCP_URL=http://127.0.0.1:8425/mcp`.
   - **EULA:** JEB sin interfaz pide aceptarla por la entrada estándar y se cierra si no recibe "yes"; la acepta `.EulaAccepted = true` en su `--config`. Esa aceptación es de Diego: `--jeb` se niega hasta que existe `~/.config/rea/jeb-eula-accepted`, que crea él después de leer `pnfsoftware.com/jeb/LICENSE.TXT`.
   - **Restricción legal (EULA rev. 2026-02-04):** no se puede *"disclose, or make available to third parties any output generated"* por JEB. Pasar su salida a un modelo en la nube es, como poco, una zona gris. Usarla con binarios nuestros, o con el modelo local.
3. **IDA Free: solo nivel 0**, con red hacia Hex-Rays y GUI. Su decompilador sube el código a su nube, así que no se usa con binarios de terceros ni en un sandbox sin red. IDA Home solo si algún día hace falta headless y se acepta la nube.
4. **Sin red, solo Ghidra y Hopper descompilan.** Para los niveles 1 y 2, Ghidra sigue siendo el motor principal.

Los motores comerciales son software propietario que se ejecuta dentro del sandbox. Su telemetría (la EULA de IDA recoge datos de uso, §4.2(g)) solo sale si el carril tiene red.

**Estado F6 (2026-10-14): demo de Hopper 6.4.2 en la microVM (niveles 1 y 2, no en la web), probada con `rea-claude --ask` sobre `vault`.** REA lanzó Hopper en su Xvfb privado, pulsó "demo" y devolvió el pseudocódigo del validador.
- **Paquete oficial `.pkg.tar.xz`, fijado por el SHA-1 que REA pone en `LinuxHopper.ts`:**
  - el servidor contesta 403 si la petición no lleva las cabeceras de REA (`accept: application/json`, `user-agent: rea-installer`); medido;
  - **sin patchelf ni strip** (`dontFixup`), porque REA compara el sha256 del lanzador (`0294ced1…`, coincide);
  - corre con **`nix-ld`** dentro del invitado, que aporta Qt6, X11/Xrender, libbsd, glvnd, libstdc++, zlib y gmp.
- **Rutas fijas que exige REA**, creadas con tmpfiles:
  - `/opt/hopper` y `/usr/bin/{Xvfb,xauth,unshare}`;
  - `/usr/bin/python3` es un envoltorio que da a `ctypes` las rutas de libX11 y libXtst (el glibc de nixpkgs no tiene ruta de sistema) y conserva `argv[0]` con `exec -a`, porque REA compara la línea de comando del proceso que lanza.
- **Fuera del nivel 0**: la imagen no lo lleva; para nuestros binarios basta Ghidra.
- **Pendiente de Diego:** aceptar el EULA de JEB (`touch ~/.config/rea/jeb-eula-accepted`) e IDA Free (licencia creada el 2026-10-15; ver más abajo). Hopper Personal (99 €) solo si la demo se queda corta.

## Cadena de suministro y actualizaciones

- Imagen desde **nuestro fork en un tag fijado**. Dependencias por `package-lock.json` (`npmDepsHash`); descargas con sha256.
- Para actualizar se ejecuta `rea-update`:
  1. `git fetch upstream`.
  2. Leer el CHANGELOG (BREAKING).
  3. Revisión del diff por un agente: red, procesos, ficheros fuera del caso, telemetría y nuevos `fetch(`.
  4. Mover el tag.
  5. Construir.
  6. **Repetir las pruebas de seguridad de F1**, no solo las funcionales.
  7. Cambiar el tag de la imagen.

  Lo mismo al actualizar Claude Code, porque también cambia la semántica de sus flags (`--strict-mcp-config` cambió en 2.1.246). Nada se actualiza solo.
- Nunca `rea setup`, `rea update`, `npx rea-agents` ni Hopper.

