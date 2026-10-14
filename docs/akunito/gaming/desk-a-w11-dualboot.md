---
id: gaming.desk-a-w11-dualboot
summary: Runbook para añadir Windows 11 en un NVMe aparte en DESK_A (nixosagadesk, desktop de Aga, AMD RX 9060 XT) sin que Windows toque el bootloader de NixOS — método de aislamiento físico del disco; endurecer W11 para el anti-cheat kernel de LU4; streaming Sunshine(W11)→Moonlight(DESK) para jugar LU4 Black
tags: [gaming, lineage2, lu4, windows11, dualboot, nvme, nixos, desk_a, sunshine, moonlight, anticheat, runbook]
related_files:
  - docs/akunito/gaming/l2reborn-linux.md
  - profiles/DESK_A-config.nix
date: 2026-10-14
status: draft
---

# DESK_A — Windows 11 en NVMe aparte, sin romper NixOS (runbook)

Objetivo: jugar **LU4 Black** (anti-cheat kernel que no corre bajo Linux/Proton, medido) en **W11 bare metal** en DESK_A (`nixosagadesk`, desktop de Aga, AMD RX 9060 XT), y **streamear a DESK** con Sunshine→Moonlight. NixOS se queda intacto en su disco actual. **No es dual-boot compartido**: son **dos discos single-boot independientes**, elegidos en el menú de arranque de la BIOS.

**Antes de nada:** DESK_A es la máquina de Aga → confirmar con ella que puede llevar W11 y abrir la caja.

## Principio de seguridad (por qué el método funciona)
El instalador de W11 **siempre** intenta escribir su gestor de arranque en la primera ESP (EFI) que encuentra y reordenar el firmware. Si el disco de NixOS **no está conectado físicamente** durante el install, Windows **no puede** tocar su ESP ni su bootloader: imposible, no está ahí. Cada disco acaba con su propia ESP y eliges el SO en el menú del firmware. Cero cambios en la config de NixOS, cero riesgo.

## Fase 0 — Preparación (con NixOS arrancado, antes de abrir la caja)
1. **Nota qué bootloader usa NixOS** por si acaso: `bootctl status` (si responde → systemd-boot) o mira `/boot/grub` (GRUB). Solo informativo; no se toca.
2. **Identifica los discos actuales** para reconocerlos luego: `lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINT` y guarda la salida (foto o a fichero). Apunta el **modelo+serial** del NVMe de NixOS.
3. **USB de rescate de NixOS** a mano (ISO instalador) por si el arranque se tuerce: `lsblk` para no equivocarte de USB al grabarlo.
4. **USB de Windows 11** (Media Creation Tool desde otra máquina Windows, o Ventoy con la ISO oficial).
5. Apaga del todo (no suspend): `poweroff`.

## Fase 1 — Montaje físico + aislamiento
1. Con el equipo apagado y desenchufado de corriente, **instala el NVMe nuevo** (vacío) para Windows en una ranura M.2 libre.
2. **Desconecta físicamente el NVMe de NixOS** (saca el M.2, o desconecta su cable si fuera SATA/U.2). Deja conectado **solo el NVMe nuevo y vacío**. Si hay más discos de datos, desconéctalos también para que Windows no ponga ahí su ESP.
   - *Alternativa si no puedes sacarlo cómodamente:* deshabilita el NVMe de NixOS en la BIOS (SATA/M.2 port → Disabled). Menos seguro que quitarlo, pero sirve. **Sacarlo es lo ideal.**
3. Arranca a la BIOS y confirma que **solo se ve el disco nuevo**.

## Fase 2 — Instalar Windows 11 en el disco solitario
1. Arranca del USB de W11. Instalación **Custom**.
2. Selecciona el NVMe nuevo (estará vacío). Deja que Windows cree sus particiones (ESP + MSR + Windows) **en ese disco**. No toques nada más (no hay nada más conectado).
3. Completa el install. **Cuenta local** si puedes (en el OOBE: `Shift+F10` → `oobe\bypassnro` para saltar la cuenta Microsoft, o desconecta la red durante el OOBE).
4. Instala los **drivers AMD** (RX 9060 XT) desde la web de AMD.

## Fase 3 — Endurecer W11 para el anti-cheat de LU4 (CRÍTICO)
El anti-cheat de LU4 es un **driver kernel (Active Anticheat / PRProt)** que **rechaza Windows con virtualización activa** — no solo VMs, también Hyper-V/VBS en Windows real. W11 lo activa por defecto. Si no lo apagas, **el AC bloquea el login aunque sea bare metal** (síntoma: "Driver installation error" o similar antes del login).
1. **Memory Integrity OFF:** Windows Security → Device Security → Core Isolation → Memory Integrity → **Off** (reinicia).
2. **No actives** Hyper-V, WSL2, "Virtual Machine Platform", "Windows Hypervisor Platform", ni Windows Sandbox (Panel → Activar características de Windows: todo eso **desmarcado**).
3. Comprueba que VBS está OFF: `msinfo32` → "Virtualization-based security" debe decir **Not enabled** (o **Running** = mal, hay que apagarlo).
4. **Secure Boot:** déjalo como esté de momento. Si el AC se queja al entrar, probamos encenderlo/apagarlo en BIOS (el requisito exacto de este AC no está confirmado). Cambiarlo afecta a ambos discos → anótalo.
5. Instala el **launcher de LU4 (EGlobalLauncher)**, 50+ GB, y verifica que **llega al login** (si da error de driver, revisa pasos 1-3).

## Fase 4 — Reconectar NixOS y elegir SO
1. Apaga, **vuelve a conectar el NVMe de NixOS** (y los discos de datos).
2. Arranca a la BIOS: verás **dos entradas EFI** — "Windows Boot Manager" (disco nuevo) y la de NixOS (systemd-boot/GRUB, intacta).
3. **Orden de arranque:** pon **NixOS como predeterminado** (arranca a NixOS normalmente). Para jugar, pulsa la **tecla del menú de arranque** del firmware (suele ser **F8/F11/F12/Supr** según la placa) y elige Windows. Así nunca dependes de que un SO gestione el menú del otro.
   - *Opcional (un solo menú):* si quieres que el menú de NixOS liste Windows: GRUB → `boot.loader.grub.useOSProber = true` (detecta la otra ESP); systemd-boot no auto-descubre una ESP en **otro** disco de forma fiable, así que para systemd-boot el **menú del firmware** es lo práctico. Recomendado: menú del firmware, sin tocar la config de NixOS.

## Fase 5 — Streaming (jugar LU4 desde DESK)
1. **W11 (host):** instala **Sunshine**, ábrelo, empareja. Permite el firewall. Configura el stream a la resolución/FPS del monitor de DESK.
2. **DESK (cliente):** **Moonlight ya está instalado** (`moonlight-qt`, vía `user/packages/user-basic-pkgs.nix`). Lánzalo (`moonlight`), empareja con DESK_A por LAN (o por Tailscale si DESK_A está en la tailnet), introduce el PIN en Sunshine.
3. Juega LU4 en DESK_A, visualiza/controla desde DESK. El asesor de **visión/OCR** (futuro) leería ese stream en DESK y daría consejos por voz — nunca inyección ni lectura de paquetes (UE5 + AC kernel).

## Gotchas de convivencia (dos SO, dos discos)
- **Reloj:** Windows usa RTC en hora local, NixOS en UTC → el reloj se desajusta al alternar. Arréglalo con **uno** de los dos: en NixOS `time.hardwareClockInLocalTime = true`, **o** en Windows poner el RTC en UTC (clave de registro `RealTimeIsUniversal`). No ambos.
- **Fast Startup de Windows:** desactívalo (Panel → Opciones de energía → "Cambiar lo que hacen los botones" → quitar "Inicio rápido") para que no deje su disco en estado sucio si algún día lo montas desde Linux.
- **No "reparar arranque" de Windows** nunca con el disco de NixOS conectado — si Windows alguna vez ofrece reparar el boot, hazlo con NixOS desconectado.
- **BIOS/Secure Boot/CSM:** cambios aquí afectan a los dos discos; cámbialos conscientemente.

## Estado y memoria
Decisión en `project_l2_server_choice_2026_09.md` (memoria dotfiles). El asistente completo (no solo visión) vive en el testbed propio Mobius Interlude: `docs/akunito/plans/l2-rpa-testbed.md`. SmartGuard/Active-AC y por qué Linux no corre estos clientes: `docs/akunito/gaming/l2reborn-linux.md`.
