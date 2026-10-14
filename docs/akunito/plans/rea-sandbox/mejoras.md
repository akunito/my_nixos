---
id: akunito.plans.rea-sandbox.mejoras
summary: Segundo plan de REA — qué ya existe en open source para medir y mejorar Ghidra (DecBench, extensiones de nixpkgs, firmas abiertas, refinado con IA local) y cómo incorporarlo al sandbox sin clonar herramientas comerciales
tags: [rea, ghidra, decompiler, benchmark, decbench, signatures, fid, bsim, llm4decompile, research]
tickets: [AINF-408]
date: 2026-10-14
status: draft
related_files:
  - docs/akunito/plans/rea-sandbox/README.md
  - user/app/rea/image.nix
---

# REA: mejoras a partir de lo que ya existe

Parte del plan [REA en un sandbox](README.md). Investigación del 2026-10-14 (tres subagentes, solo lectura; datos de GitHub y Hugging Face de ese día). **Regla: no clonar ni descompilar herramientas comerciales.** Se compara solo su salida (Directiva 2009/24/CE, art. 5.3: observar y estudiar el funcionamiento de un programa que se usa legítimamente; el art. 8 hace nula la cláusula que lo prohíba). Nada de firmas ni tipos derivados de IDA.

## Qué hay ya en nuestro setup (auditoría)

- **Ghidra 12.1.4 de nixpkgs ya trae:**
  - FID de MSVC (vs2012–2019, x86/x64);
  - GDT (`generic_clib`, `windows_vs12`, `mac_osx`, `golang_1.15–1.23`, `rust-common`);
  - BSim con servidor (H2/PostgreSQL/Elastic);
  - Go 1.15–1.25;
  - el analizador de Objective-C nuevo de 12.1 y `RecoverClassesFromRTTIScript`.
- **Le falta:**
  - **extensiones** (la imagen usa el Ghidra pelado);
  - **firmas** de libc, musl, libstdc++, OpenSSL, zlib y Rust std;
  - **ninguna forma de medir** si un cambio mejora o empeora la salida.
- **Ghidra 12.2 ya salió** (octubre de 2026) y **exige JDK 25**. REA 6.4.0 verifica 12.1.x. **Mantener 12.1.x fijado** hasta que nixpkgs y REA la soporten. `rea-update` lo comprueba.

## Candidatos (verificados el 2026-10-14)

### Medir: banco de comparación

| Proyecto | Licencia | Estado | Qué aporta | Pegas |
|---|---|---|---|---|
| **DecBench** (Noelo-Lab/decbench) | MIT en `pyproject` (sin fichero LICENSE); dataset BSD-2 en HF | Activo | GED del CFG frente al fuente, tipos frente a DWARF, recompilación. `decbench improvements -b X -t ghidra` lista función a función dónde pierde Ghidra. Harnesses: angr, Ghidra, IDA, Binja, dewolf, Kuna. El dataset incluye salidas **ya publicadas** de IDA/Binja | "Experimental"; solo C/ELF; no acepta contribuciones autónomas por IA; la misma organización hace Kuna |
| **sailr-eval** (mahaloz) | BSD-2 | Parado desde 2024-11 | Métricas de estructuración: gotos, nesting, booleanos | Código de paper |
| **Decompiler Explorer** (dogbolt) | MIT | Activo | Runners Docker de angr, Boomerang, Ghidra, Kuna, RecStudio, Reko, RetDec, rev.ng, Snowman | No puntúa: es un visor |
| DecompileBench (vul337) | Sin licencia | 2025-10 | Recompilación + cobertura OSS-Fuzz; concluye que la salida de LLM es un **52 % menos correcta** aunque se lea mejor | Pesado; sin licencia |
| HumanEval-Decompile (LLM4Decompile) | MIT | 2026-02 | Re-ejecutabilidad con tests | Funciones de juguete |

### Mejorar Ghidra

| Proyecto | Licencia | ¿12.1.4? | Qué aporta |
|---|---|---|---|
| `ghidra-extensions.ghidra-golanganalyzerextension` 1.4.0 | MIT (nixpkgs) | Sí, en nixpkgs | Go 1.6–1.27: nombres, tipos, strings |
| `ghidra-extensions.kaiju` 260910 | BSD (SEI) | Sí, en nixpkgs | Fn2Hash/Fn2YARA, mejoras de desensamblado, importador de OOAnalyzer (C++) |
| `ghidra-extensions.findcrypt` 3.1.10 | GPL-3 | Sí, en nixpkgs | Constantes criptográficas |
| `ghidra-extensions.wasm` 2.4.0, `ghidra-firmware-utils` | — | Sí, en nixpkgs | Loader de WASM, formatos de firmware |
| **rizin sigdb** (rizinorg) | LGPL-3 | Datos | Firmas FLIRT generadas con `rz-sign` (abierto): musl, libc6, libstdc++ 5–12, libc++, OpenSSL, zlib, libsodium, VS2008–2022 |
| **capa sigs** (mandiant) | Apache-2.0 | Datos | Firmas de CRT MSVC, ATL/MFC |
| SigAnalyzer (blend-tea) | MIT | Recompilar (build para 12.0.4) | Aplica `.sig` FLIRT como analizador, también en headless. 7★, inmaduro |
| FIDBs / BSim de ATR (advanced-threat-research) | Apache-2.0 | Por probar | openssl, zlib, libsodium, libgcrypt, boost, golang… multi-arquitectura |
| ghidra-nativeaot (Washi1337) | MIT | Recompilar | .NET NativeAOT |
| DelphiReSym | BSD-3 | Script PyGhidra | Delphi |
| **Kuna** (Noelo-Lab) | Apache-2.0 | Probado en 12.1.2 | Fork en Rust del decompilador de Ghidra, para usarlo como **motor alternativo**. Varias releases al día; incompleto |

**Trampas de licencia:**
- **No** usar los `.sig` de IDA ni sets sin licencia (`push0ebp/sig-database`, `Maktm/FLIRTDB`).
- **No** usar `NyaMisty/ghidra_ida_til` (TIL de IDA).
- **No** usar el Lumina público de Hex-Rays.
- Los GDT generados del Windows SDK heredan su licencia: no se publican.
- GPL-3 (findcrypt) solo afecta si se publica un fork.

### IA local (3090 del NAS)

| Proyecto | Licencia código / pesos | Qué hace | Medido |
|---|---|---|---|
| **LLM4Decompile-Ref 9B-v2** | MIT / base Yi-Coder (Apache, inferido) | Refina el pseudocódigo **de Ghidra** a C | HumanEval-Decompile: Ghidra 20,1 % → 64,9 % re-ejecutable (funciones de juguete). GGUF de la comunidad (~6–10 GB) |
| **DAILA + VarBERT** | BSD-2 | Nombres de variables (BERT, CPU); DAILA soporta Ghidra ≥ 12.0 y LiteLLM | 54,5 % de acierto en Ghidra O2 |
| GhidrAssist, GhidraGPT, OGhidra | MIT / Apache / BSD-3 | Renombrar y explicar con cualquier endpoint OpenAI | Sin métricas |
| ReSym, SK²Decompile, DIRTY | varias | Nombres, tipos y structs | Entrenados con salida de IDA: no reproducibles con Ghidra |

**Conclusión:** la salida de IA sirve como **anotación** (nombres, comentarios, vista alternativa), **nunca para sustituir** el pseudocódigo de Ghidra. Además, todo hay que medirlo con nuestro banco.

## Plan de mejoras (M)

**M0 — ya, si la auditoría independiente lo aprueba (cambio pequeño): extensiones de nixpkgs en la imagen.**
- `ghidra.withExtensions (e: [ e.ghidra-golanganalyzerextension e.kaiju e.findcrypt e.wasm ])` en `user/app/rea/image.nix`.
- **Prueba:** `rea doctor` en verde con la misma versión 12.1.4; un binario Go propio con nombres recuperados frente a sin extensión; la vault de F1 sigue saliendo igual.
- **Riesgo:** las extensiones corren dentro de Ghidra con el binario hostil, así que son más superficie de ataque. Van dentro de `krun` y la microVM, igual que Ghidra.

**M1 — banco de medida (tras F2).**
- Fork de DecBench a `akunito/decbench`, ejecutado **dentro del sandbox** (contenedor `krun`, sin red) con angr + Ghidra, más su dataset con salidas publicadas de IDA/Binja como referencia.
- Añadir las métricas de gotos de sailr-eval.
- Corpus propio: C, C++, Rust y Go compilados con varios compiladores y niveles `-O`, construido con derivaciones Nix y con DWARF guardado aparte como ground truth.
- **Salida:** la tabla "dónde pierde Ghidra", por métrica.

**M2 — firmas abiertas.**
- rizin sigdb + capa sigs con SigAnalyzer recompilado para 12.1.4 (`buildGhidraExtension`).
- FIDB de ATR.
- FID/BSim propios de glibc, musl y Rust std generados desde nixpkgs.
- **Medido con M1:** porcentaje de funciones identificadas antes y después.

**M3 — motores alternativos.** Kuna como decompilador alternativo en headless, comparado con el nativo en M1. Nunca lo sustituye. Opcional: RetDec y Reko desde los runners de dogbolt.

**M4 — IA local como anotación.**
- LLM4Decompile-Ref 9B-v2 en el router de `llama-server` del NAS, y DAILA/VarBERT para nombres.
- Integración: una herramienta (fuera de REA, en `rea-cli` o en un MCP propio) que manda el pseudocódigo de una función y guarda la propuesta **como comentario**.
- **Medido con M1** y a mano en 20–30 funciones de binarios conocidos.
- **VRAM:** el 9B Q4 (~6 GB) y el Qwen 27B (~17 GB) apenas caben juntos en 24 GB. El router carga un preset u otro.

**M5 — aportar upstream.** Lo que mejore en M2/M3 va como PR a Ghidra (Apache) o a REA (MIT) desde el fork. DecBench no acepta PRs autónomos de IA: ahí solo issues escritos por Diego.

## Huecos que nadie cubre (posible trabajo propio)

- Hopper no está en ningún harness.
- Nadie mide **Ghidra + agente MCP (REA)** frente a Ghidra solo.
- Nadie hace regresión por versión de Ghidra.
- La cobertura de C++, Rust, PE/MSVC y ARM en el scoring es floja.
