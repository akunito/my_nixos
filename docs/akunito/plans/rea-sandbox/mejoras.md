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
- **Ghidra 12.2 está anunciada para octubre de 2026 y exigirá JDK 25.** El último tag publicado es `Ghidra_12.1.4_build`, y `master` ya es 12.3-DEV. REA 6.4.0 verifica 12.1.x. **Mantener 12.1.x fijado** hasta que nixpkgs y REA soporten la 12.2. `rea-update` lo comprueba.

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
| `ghidra-extensions.wasm` 2.4.0 | GPL-3 | **No: broken para 12.1.4 en nixpkgs** | Loader de WASM |
| `ghidra-firmware-utils`, `machinelearning` (detector de inicios de función), `ghidra-delinker-extension` | — | Sí, en nixpkgs | Firmware; funciones en binarios stripped; delinker |
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

**M0 — aplicado tras la auditoría independiente (2026-10-14). Veredicto: aplicar con cambios.**
- **Cambios que impuso la auditoría:**
  - `wasm` está marcado `broken` para 12.1.4 en nixpkgs.
  - **`GHIDRA_INSTALL_DIR` no se toca.** `withExtensions` es un `symlinkJoin` que solo contiene `Extensions/` y wrappers, y REA necesita `support/analyzeHeadless`, `application.properties` y el decompilador nativo dentro del directorio de instalación. Las extensiones se cargan con `NIX_GHIDRAHOME=${ghidraExt}/lib/ghidra/Ghidra`: el parche de nixpkgs añade esa raíz, y REA pasa todo el entorno a la JVM que lanza.
  - **`kaiju` queda fuera** hasta M2/M3. Sus analizadores van activos por defecto y cambian el desensamblado de todos los binarios, con un arranque limitado a 330 s.
- **Aplicado:** `ghidra-golanganalyzerextension` + `findcrypt` (`user/app/rea/image.nix`).
- **Medido contra la imagen de F1 sin extensiones:** `doctor` en verde (12.1.4, headless, decompilador nativo); tiempo igual (~43 s).

  | Binario de prueba | Sin extensiones (F1) | Con M0 |
  |---|---|---|
  | Go sin símbolos (`-s -w`) | no encuentra `checkLicense` ni `main.main` | `main.checkLicense`, `main.main` |
  | C con la S-box de AES | `DAT_00102020[…]` | `CRYPT_AES_Encryption_SBox[…]` |
- **Gotcha:** `NIX_GHIDRAHOME=` vacío **no** desactiva las extensiones. El control tiene que ser otra imagen.
- **Seguridad, revisado por la auditoría:** ni la extensión de Go ni findcrypt tienen red, `Runtime.exec` ni auto-actualización. findcrypt es GPL-3, sin obligaciones mientras la imagen no se distribuya.
- **Pendiente:** medir los analizadores de Go nativos y los de la extensión juntos. Si se pisan, decidir cuál queda.

**M1 — banco de medida.** Un **M1 mínimo puede adelantarse ya:** contar funciones con nombre, errores del decompilador y tiempo sobre los binarios de prueba propios. El M1 completo va tras F2.
- **Legal (auditoría):** la EULA de Hex-Rays prohíbe a **sus licenciatarios** publicar benchmarks sin invitar a Hex-Rays. Las salidas de IDA y Binja del dataset de DecBench son **solo referencia de métrica**: nunca entran en M2 (firmas), en M4 (prompts o entrenamiento) ni en sesiones de REA, y los resultados van a `workbench/`, no a docs públicas.
- **Cadena de suministro:** DecBench necesita pip (angr, lief…), Joern (JVM, no está en nixpkgs) y el dataset de Hugging Face. Se empaqueta como derivación Nix (nixpkgs tiene `angr`, `lief` y `retdec`) y el dataset va por `fetchurl` con hash. Así corre dentro del sandbox sin red.
- Fork de DecBench a `akunito/decbench`, ejecutado **dentro del sandbox** (contenedor `krun`, sin red) con angr + Ghidra, más su dataset con salidas publicadas de IDA/Binja como referencia.
- Añadir las métricas de gotos de sailr-eval.
- Corpus propio: C, C++, Rust y Go compilados con varios compiladores y niveles `-O`, construido con derivaciones Nix y con DWARF guardado aparte como ground truth.
- **Salida:** la tabla "dónde pierde Ghidra", por métrica.

**M2 — firmas abiertas.** **Ojo (auditoría):** SigAnalyzer lee las firmas de `<UserSettingsDir>/signatures/<Processor>/*.sig`, y REA crea un `XDG_CONFIG_HOME` vacío en cada sesión. Hay que parchearlo (o escribir un analizador propio) para que lea las firmas del directorio de la extensión, y recompilarlo para 12.1.4.
- Cobertura real de rizin sigdb: solo ELF x86-64; libc++ 7–15, libgcc 7–12, VS2005–2022; nada de Rust; estancado desde 2023-08.
- capa sigs: generadas por Mandiant con FLAIR (herramienta de Hex-Rays) a partir de datos propios, no derivadas de las firmas de IDA. Usarlas o no lo decide Diego.
- FIDB de ATR: 171 ficheros de junio de 2024 (~Ghidra 11.1); el esquema FID `VERSION = 6` no ha cambiado de 10.0 a 12.1.4, así que deberían cargar (por esquema, sin probar).
- Para glibc, musl y Rust std, Ghidra trae `CreateMultipleLibraries.java`, que genera FID desde los `.a` de nixpkgs.
- rizin sigdb + capa sigs con SigAnalyzer recompilado para 12.1.4 (`buildGhidraExtension`).
- FIDB de ATR.
- FID/BSim propios de glibc, musl y Rust std generados desde nixpkgs.
- **Medido con M1:** porcentaje de funciones identificadas antes y después.

**Estado M1 (2026-10-14): hecho.** Hay dos formas de lanzarlo:
- `rea-bench` mide la imagen de REA tal como corre (nivel 0, krun, sin red);
- `bench/bench.nix` hace la misma medida como derivación de Nix, con extensiones opcionales, para probar candidatos. **Reproduce exactamente** los números de la imagen de REA.

Detalles:
- **Corpus propio** (`bench/corpus.nix`): C, C++, Rust y Go; gcc y clang, `-O0` y `-O2`, glibc dinámico y estático, y musl estático. Una derivación por cadena de compilación: un cc de musl dentro de un stdenv de glibc enlazaba `glibc.static` y fallaba (medido).
- **Verdad de referencia:** los símbolos `FUNC` e `IFUNC` del binario sin *strip*, con todos los alias de cada dirección.
- **Métricas:** inicios de función encontrados; nombres correctos y equivocados; `FID_conflict` y *thunks* contados aparte; fallos de decompilación y tiempo.
- **Línea base** (resultados completos en `workbench/rea-bench/`):

| Binario | Nombres correctos |
|---|---|
| Go | 98 % (extensión golang) |
| C/C++/Rust estáticos | 0–0,7 % |
| inicios de función | 86–100 % |

- **Fallo real de Ghidra que mide el banco:** una función que termina con un salto a `strcmp` se toma por un *thunk* y se llama `strcmp`.

**Estado M2 (2026-10-14): activo en REA** (imagen de nivel 0 y VMs), tras la auditoría independiente y sus cambios. `rea-bench` sobre la imagen reproduce exactamente la medición candidata. En la VM, el agente aislado nombró `calloc`, `fopen`, `strtol`, `printf`… en un binario musl estático sin símbolos y distinguió "análisis" de "importado".
- **Bases Function ID de Ghidra** generadas en el sandbox de Nix desde las librerías estáticas de nixpkgs:
  - glibc, libm, musl y libgcc/libgcc_eh;
  - libstdc++, para gnu y para musl;
  - core/alloc/std de Rust;
  - todo en dos versiones (unstable y stable).
- **Empaquetado:** como extensión de Ghidra con `data/*.fidbf`. Ghidra carga los `.fidbf` de cualquier módulo, mientras que un `.fidb` "de usuario" no lo vería la configuración vacía de REA.
- **Sin firmas de IDA ni conjuntos de terceros.** Licencias sin problema: son datos locales y el repo solo guarda la receta.
- **Resultado** (nombres correctos; los equivocados quedan en torno al 1 %, más los conflictos que marca Ghidra):

| Binario | Misma versión | Otra versión (caso real) |
|---|---|---|
| glibc estático | 58,8 % | 14,2 % |
| musl estático | 63,8 % | 17,4 % |
| C++ estático | 44,8 % | 7,8 % |
| Rust | 27,5–41,9 % | 11,5 % |

- **Cambios exigidos por la auditoría, aplicados:**
  - puntuador corregido;
  - filtro de nombres basura de libstdc++;
  - libgcc y libm añadidos;
  - aviso al agente de que un nombre con `source: analysis` es una suposición de FID.
- **Medido:** construir las bases a la vez agotó la memoria de DESK (un Ghidra de hasta 6 GB por librería). Siempre con `--max-jobs` 1 o 2.
- **Ampliado el 2026-10-15 con Debian 12, Ubuntu 24.04 y Alpine 3.20** (`bench/fid/distro.nix`).
  - **Bases:** desde los paquetes oficiales (`libc6-dev`, `libstdc++-dev`, `libgcc-dev`, `musl-dev`, `gcc`), fijados por hash.
  - **Corpus "ajeno":** los mismos programas, compilados con la cadena de cada distribución en Docker rootless (`workbench/rea-bench/foreign-corpus`).
  - **Medido en ese corpus:**

| Binario estático | Solo FID de nixpkgs | + FID de las distribuciones |
|---|---|---|
| C | 0,4–11 % | **54–60 %** |
| C++ | 0,5–8 % | **27–36 %** |

  - Nombres equivocados: 0,7 % o menos. Las firmas de nixpkgs solas apenas sirven con binarios de terceros; las de las distribuciones donde se compilan, sí.
- **Pendiente:**
  - una lista de símbolos comunes como la que usa Ghidra para MSVC;
  - exponer en REA el comentario PLATE con los candidatos de `FID_conflict`.

**Estado M3 (2026-10-14): Kuna medido, no adoptado.** Kuna v1.833 compilado desde `fe01d629` (`bench/kuna.nix`).
- **Cómo se monta:** es un árbol de Ghidra copiado, con `decompile` sustituido. Hay que cambiar el `launch.sh` de nixpkgs, que es un envoltorio binario que salta al Ghidra original por ruta absoluta; sin eso, la copia usaba en silencio el decompilador normal (medido: salida idéntica).
- **Resultado frente a Ghidra 12.1.4, mismo corpus:**
  - −28 a −35 % de `goto`;
  - C más compacto: 152k frente a 229k líneas en glibc estático;
  - casi ningún comentario `WARNING`, porque no los emite;
  - un fallo en glibc, ninguno en Rust ni Go;
  - **tres veces más lento** en el binario grande (188 s frente a 59 s).
- **Sin tests semánticos, lo más compacto no demuestra que sea más correcto.** Queda como segunda opinión para el banco, nunca como motor de REA. Lo siguiente: tests de recompilación y ejecución (como HumanEval-Decompile) antes de compararlos en serio.

**M3 — motores alternativos.** Kuna va en una **imagen aparte** con un `GHIDRA_INSTALL_DIR` alternativo (un `symlinkJoin` que sustituye `Decompiler/os/linux_x86_64/decompile`), con commit fijado y compilado con Nix. Nunca es el motor por defecto. Kuna como decompilador alternativo en headless, comparado con el nativo en M1. Nunca lo sustituye. Opcional: RetDec y Reko desde los runners de dogbolt.

**M4 — IA local como anotación.**
- LLM4Decompile-Ref 9B-v2 (pesos MIT, base Yi-Coder-9B, referencia Ghidra 11.0.3: con 12.1.4 hay que medir) en el router de `llama-server` del NAS.
- VarBERT **solo con su modelo entrenado con Ghidra**: sus modelos usaron salida de IDA 7.6 y de Ghidra 10.4, y el de IDA se excluye por la misma razón que ReSym/DIRTY. DAILA ya no usa LiteLLM (v3.20 usa pydantic-ai) y `libbs` es ahora `declib` ≥ 4.5, en modo PyGhidra.
- Integración: una herramienta (fuera de REA, en `rea-cli` o en un MCP propio) que manda el pseudocódigo de una función y guarda la propuesta **como comentario**.
- **Medido con M1** y a mano en 20–30 funciones de binarios conocidos.
- **VRAM:** el 9B Q4 (~6 GB) y el Qwen 27B (~17 GB) apenas caben juntos en 24 GB. El router carga un preset u otro.

**Estado M4 (2026-10-14): activo en DESK.** El NAS tiene el preset preparado y el modelo descargado; se despliega cuando el reasoner esté libre, porque el despliegue reinicia `llama-server`.
- **Modelo:** LLM4Decompile-Ref 9B v2 (MIT). En DESK va en el Ollama de la RX 9070 XT, Q6_K de 7,25 GB, con una VRAM total medida de 11 GB con el escritorio. En el NAS es el preset `llm4decompile`, en Q8_0.
- **Herramienta:** `rea-llm-mcp` da a la sesión aislada una sola herramienta, `refine_pseudocode`, con el prompt del artículo y decodificación voraz. Orden de prueba: Ollama local, el Ollama de DESK por tailscale (para X13) y el NAS, este último solo si su preset activo ya es `llm4decompile`. El pseudocódigo nunca sale de la red local.
- **Medido:** 7,2 s por función en DESK.
- **Prueba con `vault`:** el C es mucho más legible pero tiene **tres errores de significado**:
  - toma el último carácter como dígito cuando es el byte crudo;
  - convierte mal la constante del hash;
  - cambia el signo de los bytes en el bucle.

  El agente aislado los detectó contra el pseudocódigo de REA y el desensamblado, y se fió de REA. Confirma que es una anotación, nunca evidencia.
- **Pendiente:** medirlo en el corpus de M1 compilando y ejecutando lo que propone, y probar VarBERT (modelo de Ghidra) para nombres de variables.

**M5 — aportar upstream.** Lo que mejore en M2/M3 va como PR a Ghidra (Apache) o a REA (MIT) desde el fork. DecBench no acepta PRs autónomos de IA: ahí solo issues escritos por Diego.

## Huecos que nadie cubre (posible trabajo propio)

- Hopper no está en ningún harness.
- Nadie mide **Ghidra + agente MCP (REA)** frente a Ghidra solo.
- Nadie hace regresión por versión de Ghidra.
- La cobertura de C++, Rust, PE/MSVC y ARM en el scoring es floja.
