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
| WABT | **exige banner `1.0.42`** (`WabtArtifactProvider.ts:222-228`) | 1.0.41 ✗ | override a 1.0.42 | F1 |
| TShark + capinfos | major 4 | 4.6.9 ✓ | — | F1 |
| prlimit, ps | ruta absoluta / en PATH | util-linux, procps ✓ | variables | F1 |
| mitmproxy | 12.2.3 | 12.2.3 ✓ | — | F1 (grabados), F3 (en vivo) |
| jadx-headless-mcp | 0.7.1, sha256 en `src/android/JadxRelease.ts` | `fetchurl` | JAR de un tercero (`1013503897`), no de morluto: revisarlo antes | F1 |
| Apktool | ≥ 2.7.0 | 3.0.3 ✓ | — | F1 |
| ilspycmd | — | 9.1 | — | F1 |
| Binwalk / Unblob | 3.1.0 / 26.6.4 | ✓ / ✓ | — | F1 |
| DIE, UPX, YARA, file | — | 3.21 / 5.2.1 / 4.5.7 | triaje | F1 |
| Chromium | Chrome-family | 155 | carril web | F3 |
| Wakaru | 1.14.0 | npm | derivación propia | F4 |
| GDB + pwndbg | MI2/MI3, sin versión | 17.2 ✓, pwndbg por su flake | — | F4 |
| sigrok-cli | **exige `0.7.2`** (`SigrokRecordingProvider.ts:235-241`) | 0.8.0-unstable ✗ | override a 0.7.2 + libsigrokdecode | F4 |
| Frida | 17.23.2 | npm opcional | derivación con prebuilt fijado por hash | F3 |
| adb + emulador | — | android-tools 37.0.0 | en la microVM | F3 |

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
2. **JEB CE: probarla.** Diego crea la cuenta y la instala; después se mira si ofrece el servidor MCP. Si sí, es el mejor decompilador x86 gratis con API. Por su EULA, solo con modelo local (`claude-nas`) o con binarios nuestros.
3. **IDA Free: solo nivel 0**, con red hacia Hex-Rays y GUI. Su decompilador sube el código a su nube, así que no se usa con binarios de terceros ni en un sandbox sin red. IDA Home solo si algún día hace falta headless y se acepta la nube.
4. **Sin red, solo Ghidra y Hopper descompilan.** Para los niveles 1 y 2, Ghidra sigue siendo el motor principal.

Los motores comerciales son software propietario que se ejecuta dentro del sandbox. Su telemetría (la EULA de IDA recoge datos de uso, §4.2(g)) solo sale si el carril tiene red.

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

