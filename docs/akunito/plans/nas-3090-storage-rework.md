---
id: akunito.plans.nas-3090-storage-rework
summary: Liberar el PCIEX16 del NAS para la RTX 3090 — sistema del 840 EVO (SATA) a un Samsung 980 500GB en M2B_SB por clonado dd, ssdpool del HBA LSI a los 4 SATA de la placa (TRIM por fin), HBA fuera, KIOXIA fuera
tags: [nas, hardware, zfs, ssdpool, trim, gpu, rtx3090, runbook]
tickets: [AINF-402]
date: 2026-10-01
status: draft
related_files:
  - profiles/NAS_PROD-config.nix
  - system/hardware-configuration.nix
  - system/app/nas-services.nix
  - scripts/autoSystemUpdate.sh
  - lib/defaults.nix
---

# NAS: 3090 en el PCIEX16 + ssdpool a SATA de placa

Auditado por Fable 5.1 el 2026-10-01 (2 blockers, 10 should-fix, todos incorporados abajo).

## Estado medido (2026-10-01)

| Ubicación | Dispositivo | Enlace | Uso |
|---|---|---|---|
| PCIEX16 (CPU) | LSI SAS9300-16i (PLX + 2× SAS3008) | Gen3 x8 (root port admite x16) | 03:00.0 → 4× 870 EVO `ssdpool`; 05:00.0 vacío |
| PCIEX2 (chipset) | Intel X520-DA2 | Gen2 x2 | bond 2×10GbE (techo ~7 Gbps, sin cambios) |
| M2A_CPU | Lexar NQ790 4TB | Gen3 x4 | `extpool` |
| M2B_SB (chipset) | KIOXIA EXCERIA G2 2TB | Gen3 x4 | LUKS `65315a71` sin referenciar → **se retira** |
| SATA placa (1 de 4) | Samsung 840 EVO 500GB, 976773168 sectores, 512/512 | SATA | ESP `41C0-160E` (systemd-boot) + LUKS `cryptroot` `c36addf8-…` |

- initrd: `[ "mpt3sas" "xhci_pci" "ahci" "nvme" "sd_mod" ]` → root en NVMe arranca sin rebuild.
- ESP: entrada NVRAM "Linux Boot Manager" por PARTUUID `9a23a5de-…` (el dd la clona) + fallback `\EFI\BOOT\BOOTX64.EFI`.
- ZFS: desbloqueo **automático** (`nas-zfs-unlock`, claves en `/etc/zfs/keys`, viajan con el clon). Import por `boot.zfs.extraPools` escaneando `/dev/disk/by-id` → el cambio de controladora no cambia rutas. hostid declarativo `47bff07a`.
- Root LUKS: passphrase con teclado local (sin SSH en initrd).
- libata (6.12, `Samsung SSD 870*`): `NO_NCQ_TRIM | ZERO_AFTER_TRIM | NO_NCQ_ON_ATI | NO_LPM_ON_ATI`. Los `_ON_ATI` solo aplican a vendor 0x1002; el SATA del B550 es `1022:43eb` → **NCQ activo**, TRIM no encolado vía `writesame_16`, igual que hace hoy el 840 EVO (DISC-MAX 2G).
- `sda` (serie …077877) reporta 4000797360 sectores, sus hermanos 3907029168 (lectura a través del SAS3008, sin explicar).
- **El NAS no hace arranque en frío desde 2026-09-13**: arrancado en gen 69, la actual es la 79; gens 70-79 nunca arrancadas.
- PSU: Gigabyte UD750GM PG5 (750 W, ATX 3.0), 4× PCIe 6+2 en 2 cables.

## Objetivo

```
PCIEX16 (CPU)   → RTX 3090 (Gen3 x16)
PCIEX2          → X520 (sin cambios)
M2A_CPU         → Lexar 4TB extpool (sin cambios)
M2B_SB          → Samsung 980 500GB = sistema (clon del 840 EVO)
SATA0-3 placa   → 4× 870 EVO ssdpool (AHCI, TRIM)
fuera           → HBA 9300-16i, KIOXIA 2TB, 840 EVO (queda como rollback)
```

## Puntos abiertos (se verifican durante, no se suponen)

1. **M2B_SB vs SATA**: la ficha de Gigabyte no lo aclara. Evidencia en vivo: con NVMe en M2B_SB hoy, ata2-5 están "link down" normales (puertos vivos). La BIOS lo decide en el paso 7.
2. **980 ≥ 840 EVO** en sectores y bloque lógico 512 — comprobado antes del `dd`.
3. **Ranuras tapadas por la 3090** (~3 slots): el PCIEX2 de la X520 debe quedar libre.
4. **Tamaño de `sda`** tras pasar a AHCI (paso 10).

## Fase 0 — trabajo previo en el repo y en el NAS (remoto)

1. **Flag para bloquear `nouveau`** (nuevo, default `false` en `lib/defaults.nix`, activado en NAS_PROD): `boot.blacklistedKernelModules = [ "nouveau" ]` + `boot.kernelParams = [ "modprobe.blacklist=nouveau" ]`. Sin driver la 3090 queda en estado PCI básico (lo menos arriesgado en S3) y no aparece un segundo `/dev/dri` que pueda quitarle `renderD128` a Jellyfin (`compose/media/docker-compose.yml:30` monta todo `/dev/dri`).
2. `scripts/autoSystemUpdate.sh:102`: `REQUIRED_MARKERS` de NAS_PROD pasa de `mpt3sas cryptroot ssdpool extpool` a `cryptroot ssdpool extpool nvme`. Si no, tras quitar el HBA cada regen semanal se descarta en silencio. (`nvme` ya está en el hwconfig actual: el cambio es válido antes y después.)
3. Commit + push. Deploy en el NAS (`install.sh … NAS_PROD -s -d`) y **reboot en frío con el hardware actual**: LUKS, `systemctl status nas-zfs-unlock`, `zfs get keystatus`, ambos pools ONLINE, Docker arriba. Así el clon lleva una generación ya probada y cualquier fallo posterior es hardware.
4. Baseline (en el NAS y copiado a local):
   ```bash
   ssh -A akunito@192.168.20.200 'mkdir -p ~/nas-rework && cd ~/nas-rework &&
     lspci -tv > lspci.txt && lsblk -o NAME,MODEL,SERIAL,SIZE,TRAN,DISC-MAX > lsblk.txt &&
     grep . /sys/block/sd*/size > sizes.txt && zpool status -P > zpool.txt &&
     ls -l /dev/disk/by-id > byid.txt && sudo bootctl status > bootctl.txt; echo EXIT=$?'
   ```
5. Último backup restic OK. Silenciar alertas `node=nas` en Alertmanager para la ventana. Día ≠ sábado (autoSystemUpdate sáb 12:05, `Persistent=true`); terminar antes de 17:30 (pulls restic del VPS 17:30/18:00/18:30) o asumir que fallan ese día.
6. Live USB de NixOS 25.11 (minimal) + teclado y monitor.

## Fase 1 — clonar el sistema (HBA y 840 EVO aún en su sitio)

1. Desarmar la alarma RTC (enciende el NAS a las 16:00 aunque esté apagado): `sudo rtcwake -m disable` → `grep alarm_IRQ /proc/driver/rtc` = `no`. Apagar: `sudo systemctl poweroff`. **Interruptor de la PSU en OFF** siempre que haya manos dentro.
2. Quitar KIOXIA de M2B_SB, poner el Samsung 980. No tocar SATA ni HBA.
3. Arrancar el live USB (F12). **Nunca importar los pools ZFS desde el live** (hostid ajeno). En el live:
   ```bash
   lsblk -o NAME,MODEL,SERIAL,SIZE      # identificar por MODELO/SERIE, nunca por sdX/nvmeX
   SRC=/dev/disk/by-id/ata-Samsung_SSD_840_EVO_500GB_<serie>
   DST=/dev/disk/by-id/nvme-Samsung_SSD_980_500GB_<serie>
   blockdev --getsz $SRC; blockdev --getsz $DST      # DST >= SRC o ABORTAR
   cat /sys/block/$(basename $(readlink -f $DST))/queue/logical_block_size   # 512 o ABORTAR
   dd if=$SRC of=$DST bs=16M conv=fsync status=progress
   cmp $SRC $DST && echo CLON_OK        # +~15 min; si DST es mayor, "EOF on SRC" también es OK
   sgdisk -e $DST                       # solo si DST > SRC
   partprobe $DST; udevadm settle; sgdisk -v $DST    # "No problems found"
   cryptsetup luksDump ${DST}-part2 | grep UUID      # c36addf8-193b-47b2-bf52-dfdf7d6e3a41
   ```
4. Apagar, PSU OFF.

> Desde aquí 840 EVO y 980 comparten UUIDs. **Nunca arrancar NixOS con los dos conectados.**

## Fase 2 — almacenamiento

5. Desconectar el 840 EVO (datos + alimentación), etiquetarlo "ROLLBACK NAS".
6. Quitar el HBA y sus cables SFF-8643. 4× 870 EVO a SATA0-3 con cables SATA normales.
7. PSU ON. BIOS: los 4 870 EVO + el 980 detectados, SATA en AHCI, CSM off, arranque "Linux Boot Manager". **Si falta un 870 EVO → parar y rollback.**
8. Primer arranque, **sin GPU**. Passphrase LUKS. Inmediatamente:
   ```bash
   sudo systemctl stop nas-suspend.timer autoSystemUpdate.timer   # no persiste: repetir tras cada arranque de la intervención
   sudo rtcwake -m disable
   ```
9. Verificar sistema y discos:
   ```bash
   findmnt / /boot -o TARGET,SOURCE       # el 980 será nvme0n1 (bus 09 antes que el Lexar 0b)
   grep . /sys/block/sd*/size             # comparar con sizes.txt
   lsblk -D -o NAME,MODEL,DISC-MAX        # 870 EVO con DISC-MAX 2G (antes 0B)
   grep . /sys/block/sd*/device/queue_depth          # 32 (NCQ activo)
   grep . /sys/class/scsi_disk/*/provisioning_mode   # writesame_16 en los 870
   journalctl -k -b | grep -iE 'FPDMA|ata[0-9].*(error|failed)'   # debe estar vacío
   ```
   Si aparecen `failed command: READ/WRITE FPDMA QUEUED`, el problema de AMD también afecta a Promontory → `libata.force=noncq` detrás de un flag.
10. `systemctl status nas-zfs-unlock; zfs get keystatus ssdpool extpool` (automático; `/unlock-nas` solo si falla). `zpool status ssdpool extpool` → ONLINE, 0 errores. Si la vdev de `sda` sale UNAVAIL / "too small" → rollback. Docker arriba.
11. TRIM y prueba de escritura:
    ```bash
    sudo zpool trim ssdpool; watch zpool status -t ssdpool        # hasta 100 %
    sudo zpool set autotrim=on ssdpool                            # el timer semanal queda como red
    # ≥ 40 GB secuenciales (el precipicio aparecía hacia ~30 G) a un dataset temporal,
    # con zpool iostat -v 1 en otra terminal: no debe caer a 7-20 MB/s
    ```
12. `sudo bootctl status`: si no hay entrada de arranque válida → `sudo bootctl install`. `sudo bootctl random-seed` (la semilla quedó duplicada con el clon).
13. Deploy `install.sh … NAS_PROD -s -d` → regenera `hardware-configuration.nix` sin el HBA. Revisar el diff (solo hwconfig), commit + push.

## Fase 3 — GPU

14. Apagar, PSU OFF. 3090 en PCIEX16, **3 conectores 8-pin**: los 2 del cable A + 1 del cable B (confirmar que son PCIe 6+2, no EPS). Sin 12VHPWR. Comprobar holgura con la X520.
15. BIOS: **Initial Display Output = IGD Video** (si no, el prompt LUKS sale por la 3090), Above 4G Decoding ON.
16. Arrancar, parar timers (paso 8) y verificar:
    ```bash
    for d in /sys/bus/pci/devices/*; do case $(cat $d/class) in 0x0300*|0x0200*) echo ${d##*/} $(cat $d/class) $(cat $d/current_link_width)x $(cat $d/current_link_speed);; esac; done
    # 3090: 16x 8.0 GT/s · X520: 2x 5.0 GT/s
    lsmod | grep -c nouveau     # 0
    ls -l /dev/dri/by-path      # solo la iGPU; Jellyfin transcodifica una prueba
    ```
17. Prueba S3 antes de las 23:00: `sudo rtcwake -m mem -s 120` (WoL desde S3 no es fiable en el RTL8125B). Si no vuelve → dejar `nas-suspend.timer` parado hasta el ticket de drivers.
18. Reboot normal para reactivar los timers (`nas-rtc-wake` re-arma la alarma antes de cada suspend). Quitar el silencio de Alertmanager.

## Fase 4 — cierre

19. Docs: `.claude/commands/unlock-nas.md` (sdd2 / 840 EVO), `docs/akunito/infrastructure/services/nas-services.md:106`, `docs/akunito/plans/nas-on-demand-services.md:62`, comentario en `system/app/nas-services.nix:557` (mpt3sas). `python3 scripts/generate_docs_index.py`.
20. Memorias: X520/PCIe, ssdpool TRIM (resuelto), local AI box (3090 instalada).
21. Ticket aparte: `gpuType = "nvidia"` headless en NAS_PROD, límite de potencia, hooks pre-suspend para servicios de IA, retirar el blacklist de nouveau. Borrador listo (2026-10-01, sin desplegar). Decisiones de Diego: driver **production** (el más estable), módulo open; servicios de IA **bajo demanda** (`nas-svc`) por ahora — se pulirá en una entrevista; límite **300 W** para empezar, a medir.
22. **Nunca `zpool upgrade`** mientras el 840 EVO sea la vía de rollback (arranca con el mismo paquete ZFS).

## Fase 5 (opcional, AINF-402) — biblioteca de vuelta a ssdpool

Solo si el paso 11 demostró escrituras sostenidas sanas: mover `/mnt/extpool/library` (Calibre + ROMs, ~304 G) a `ssdpool`, actualizar montajes y comentarios en `templates/truenas/calibre/docker-compose.yml` y `templates/truenas/romm/docker-compose.yml`, y el comentario de `system/app/restic-backup-nas.nix:338` (la biblioteca sigue sin backup, decisión 2026-09-30). `rsync` con servicios parados; borrar el origen solo tras comparar.

## Rollback (cualquier fase)

PSU OFF → 980 desconectado → 840 EVO a un SATA → HBA al PCIEX16 con los 870 EVO en sus cables SAS → arrancar. El 840 nunca se escribe tras el clon. `ssdpool` sí se escribe desde el paso 10 (Docker, snapshots, TRIM, prueba), pero sigue siendo importable por el sistema del 840 (mismo hostid, mismo ZFS) mientras no se haga `zpool upgrade`. Estado consistente, no idéntico: lo escrito en el root del 980 se pierde.

## Resultado (2026-10-01)

- Fases 0-2 hechas. `dd` 840→980 sin errores (500107862016 B, ~88 MB/s por la lentitud de lectura de datos viejos del 840 EVO); `cmp` sustituido por `sgdisk -v` + UUID + `fsck.ext4 -fn` limpio. Arranca del 980; HBA y KIOXIA fuera; 840 EVO guardado como rollback.
- **No previsto**: quitar el HBA renumeró los buses PCI y la X520 pasó de `enp8s0f*` a `enp3s0f*` → `bond0` sin esclavos. Arreglado con `networkBondingInterfaceMacs` (nombres `tengbe0/1` por MAC, 570d50ff), aplicado en vivo.
- TRIM OK (DISC-MAX 2G, `writesame_16`, NCQ 32), primer trim ~14 min, `autotrim=on`. Prueba de 40 GB: 43/58/56/128 MiB/s — el límite es el disco S5Y4R020A077877 (10 s de espera, los otros tres ociosos).
- **Los 4 "870 EVO" son falsificados** (ya sospechado; reclamación en Allegro aparte): firmware `W0724A0`/`W0814A0`, tabla SMART de 30 atributos con disposición Silicon Motion (un 870 EVO real tiene 15), sin WWN, ACS-2, uno de 2,048 TB. (Corregido: el atributo 241 cuenta en unidades de 32 MiB → ~13-14 TB escritos por disco, no ~200 MB.) Scrub del día limpio; capacidad real más allá de ~1,1 TB/disco sin verificar → no llenar ssdpool.
- Consumo en reposo y RGB de la 3090: AINF-403.
- Fase 3 hecha (20:10): 3090 en PCIEX16 a x16 8 GT/s, BAR por encima de 4G, sin driver (nouveau bloqueado); X520 sigue en PCIEX2 (x2, 3-4 cm de hueco, caja 4U). BIOS: la placa **apaga la iGPU sola** con una dGPU → `Settings → IO Ports → Integrated Graphics = Forces` + `Initial Display Output = IGD Video`; `CSM Support = Disabled`. iGPU sigue siendo `renderD128`, Jellyfin VAAPI (radeonsi) OK.
- Prueba S3 por el camino real (`systemctl suspend` con los hooks): suspend 20:16 → botón → resume 20:29, `suspend_stats` 1/0, 3090 y X520 en D0 con el mismo enlace, bond y 15 contenedores de vuelta. Los hooks de parada tardan ~1:40 (sonarr/prowlarr agotan los 30 s de Docker). Timers reactivados.
