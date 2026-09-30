---
id: akunito.plans.nas-on-demand-services
summary: AkuCraft hibernado (bot solo Telegram, Discord e invitados fuera) y Minecraft survival + Calibre + RomM + UniFi mudados del VPS al NAS como servicios bajo demanda, con limpieza de copias y monitorización alineada
tags: [nas, vps, minecraft, akucraft, calibre, romm, unifi, headscale, backups, infra-bot, migration]
related_files:
  - system/app/nas-services.nix
  - system/app/akucraft-bot.py
  - system/app/akucraft-status-bot.nix
  - system/app/infra-bot.py
  - system/app/restic-backup-vps.nix
  - system/app/restic-backup-nas.nix
  - system/app/grafana.nix
  - profiles/VPS_PROD-config.nix
  - profiles/NAS_PROD-config.nix
  - templates/truenas/**
  - scripts/nas-docker-startup.sh
  - lib/defaults.nix
date: 2026-09-30
status: draft
---

# Servicios bajo demanda en el NAS

Nadie juega ya a Minecraft y Calibre / RomM / UniFi apenas se usan. Salen del
VPS, viven en el NAS **parados por defecto** y se arrancan cuando hacen falta.
Dos auditorías independientes el 2026-09-30; sus correcciones están integradas.

## Decisiones (entrevista 2026-09-30)

| Tema | Decisión |
|---|---|
| Bot AkuCraft | Sigue **solo Telegram**, remapeado al NAS. **Discord desconectado** "por el momento" (secretos y código se quedan) |
| Invitados Minecraft | Se borran: usuarios `MC_Guest_{Zuza,Ulfhogg,Ankred,wonsio}`, nodos `desktop-542nkge` y `desktop-ko51j7r`, regla y `tagOwners` de `tag:mc-guest` |
| Komi ("Misia") | **Desactivar, no borrar**: `Komi_Macbook@` sale de `group:family`; nodo y usuario se quedan. Volver = una línea en la ACL |
| Ingress | **Nativo en el NAS**, igual que hoy: públicos por el túnel `truenas-local`, `.local` por NPM + pfSense |
| Arranque | Minecraft por el bot de AkuCraft; Calibre/RomM/UniFi por `/svc` en el bot de infra + script `nas-svc` |
| Bibliotecas | Sin copia extra: si se pierden, se vuelven a descargar. **En `extpool`** (NVMe), no en `ssdpool` (decidido 2026-09-30 al medir el pool, ver hechos) |
| Extras AkuCraft | `akucraft-web`, `akucraft-playermap` y alias LiteLLM: **archivados** |
| Limpieza | **El mismo día**, tras verificación y OK explícito de Diego |

## Medidas (2026-09-30, medidas salvo que diga "estimado")

| Qué | Dónde hoy | Tamaño |
|---|---|---|
| Minecraft survival `data/` | VPS `~/.homelab/minecraft` | 57 G = `world` 28 G + `world-snapshot` 28 G (**no se muda**) + 1,7 G resto |
| Calibre biblioteca (incluye `metadata.db` 621 M) | VPS `~/calibre-library` | 211 G |
| Calibre config | VPS `~/.homelab/calibre/data/config` | 50 G `thumbnails/` (fuera del backup) + 386 M |
| ROMs | VPS `~/romm-library` | 43 G |
| RomM datos + BD / UniFi | VPS | 156 M / <100 M legibles |
| Restos AkuCraft | VPS `~/.homelab/{backups,minecraft-creative,*.migrated-to-nas-*}` | 8,9 + 2,8 + 5,1 G |

NAS: `ssdpool` 2,85 T libres, `extpool` 1,03 T libres. VPS: 746 G usados, 210 G libres.
Después (estimado): `ssdpool` −31 G (mundo + configs), `extpool` −304 G (bibliotecas + thumbnails); VPS −~330 G (385 G borrados, ~55 G vuelven como
copia offsite del mundo); `extpool` +~280 G, **visibles a los 7 días** (auto-snapshots
de `extpool/vps-backups`).

## Hechos que condicionan el diseño

- Los compose del VPS **no están en este repo**. Los del NAS salen de `templates/truenas/` vía `scripts/nas-docker-startup.sh`, que **sobrescribe** el compose vivo si difiere de la plantilla; su array `ALL_TEMPLATE_PROJECTS` (`:46`) está a mano. `gameservers/*` no tiene plantilla.
- `nasDockerProjects` (`NAS_PROD-config.nix:135-142`) es config muerta; el módulo lee `nasRootDockerProjects` / `nasRootlessDockerProjects`, que no están en `lib/defaults.nix`.
- **Un dataset ZFS nuevo sin entrada en `nasZfsMountPoints` deja el NAS en modo emergencia** (`nas-services.nix:288-292`). No se crea dataset: las bibliotecas son un directorio del dataset raíz de `extpool`.
- **`ssdpool` no recibe TRIM** y se hunde en escrituras sostenidas (medido 2026-09-30: 30 G en 20 min, 7-20 MB/s, avisos de tarea colgada). Los 870 EVO no declaran DRAT/RZAT y la LSI SAS3008 solo traduce TRIM para discos que sí; no hay arreglo por software. Arreglo: los 4 SSD a puertos AHCI + `zpool trim` + `autotrim=on`. Hasta entonces lo voluminoso va a `extpool` (restore medido a 630 MiB/s): bibliotecas en `/mnt/extpool/library/`, thumbnails de Calibre en `/mnt/extpool/library/calibre-thumbnails`.
- **`restic` no está instalado en el NAS** (wrapper colgante en `/run/wrappers/bin`).
- **El job `configs` barre todo `/mnt/ssdpool/docker/compose/`** salvo `gameservers/` y `tailscale/state/` (`restic-backup-nas.nix:271-275`). El estado de Calibre/RomM/UniFi va por tanto a `/mnt/ssdpool/docker/{calibre,romm,unifi}` (convención del NAS), nunca dentro de `compose/`.
- Ficheros de contenedor con `0600 uid 100999` (`level.dat`, `playerdata`, `automodpack/.private`, `calibre-library` entera): copiar o escribir como `akunito` los salta o los deja con dueño equivocado. Se copia y verifica **dentro de un contenedor** o como root con `--numeric-ids` (mismo subuid 100000 en ambos hosts).
- `automodpack-server.json` de survival tiene `"addressToSend": "100.64.0.6"` y el compose publica en `100.64.0.6:25565`.
- El inform de UniFi llega hoy al VPS **enmascarado como `100.64.0.7`** (pfSense; medido con `ss`). El mismo camino sirve para `100.64.0.1` solo si la regla NAT de pfSense no está limitada al destino del VPS: se comprueba, no se supone.
- NPM y cloudflared del NAS están solos en sus redes docker: los orígenes son **puertos publicados en el host**, por IP. Con el stack parado, 502.
- `calibre.akunito.com` **existe en público** (Cloudflare), además de `emulators` y `unifi`.
- Hook de suspensión actual: `TimeoutSec = 180`, `stop -t 30`; survival no tiene `stop_grace_period`. `restart: unless-stopped` en creative y solo.
- `infra-notify` avisa de contenedores `exited` → **`compose down`**, nunca `stop`. cAdvisor olvida un contenedor al parar: `ContainerDown` no salta y el bot de infra no distingue "parado" de "no existe".
- `services.restic` = `~/.homelab` (tag `services`, diario 19:30, 30 d + 3 mensuales) + bibliotecas (tag `libraries`, domingos). Sin thumbnails ni mongo de UniFi; BBDD en caliente.
- Nodos invitados pertenecen a `tagged-devices`. `headscale policy set` rechaza una política inválida; una política guardada que referencia un usuario borrado impide arrancar headscale.
- Quitar entradas de `nginxLocalServices` borra sus registros MagicDNS (`headscale.nix:34-38`).
- `homelab-docker.service` levanta los stacks de su lista en cada arranque del VPS; el bot de AkuCraft puede hacer `/start` del survival local.
- `nas-rtc-wake` programa siempre las 16:00: una suspensión manual deja el NAS fuera hasta el día siguiente.
- La clave ssh VPS→NAS (sin `command=`) la comparten el bot de AkuCraft y `/restart` del bot de infra. No se toca.

## Estado (2026-09-30 17:10)

| Fase | Estado |
|---|---|
| 0 Preparación | hecha |
| 1 Mecanismo en el NAS | desplegada y probada (`nas-svc`, hook). Falta ver la suspensión real de las 23:00 con calibre, romm y unifi encendidos |
| 2 Datos | **hecha y verificada**: bibliotecas 704 516 ficheros con sha256, propietario, modo y tamaño idénticos (restore local a 630 MiB/s, sin delta); survival 39 380 ficheros idénticos incl. `level.dat`, `playerdata`, `.private`, EasyAuth, `.env`; RomM, UniFi, config de Calibre y el archivo de AkuCraft idénticos en contenido y propietario. Thumbnails: 1 367 816 entradas copiadas, sin hash |
| 3 Ingress | NPM (6 proxy hosts), pfSense y deploy del VPS hechos; UniFi informando al NAS (2 switches); los tres responden por `.local`. **Pendiente: Cloudflare** (dashboard, hace falta iniciar sesión) |
| 4 AkuCraft | VPS desplegado: bot solo Telegram y remapeado (probado `/status`, `/start` y `/stop` de staging por el mismo código, deja el NAS sin contenedores); Headscale hecho. **Pendiente**: `sync-user.sh` en DESK y LAPTOP_X13, probar `/start` en el grupo de Telegram y entrar con el cliente |
| 5 Bots y backups | `/svc` y la línea "on-demand 3/7 on" verificados con `--selftest`; `nas-backup-data` y `nas-backup-akucraft` en verde con 0 avisos y el mundo dentro; 4 monitores de Kuma pausados (Calibre y Emulators, local y global). **Pendiente**: probar `/svc start|stop` con el botón en Telegram, 24 h sin alertas |
| 6 Limpieza | no empezada; necesita OK |
| 7 Documentación | hecha salvo el índice (`generate_docs_index.py` arrastra cambios de otra sesión) |

Lecciones de hoy: `ssh host 'bash -s' < script` se queda sin script en cuanto algo dentro llama a ssh;
un servidor de Minecraft reescribe `level.dat` como 0600 en cada guardado y enmascara la ACL de backup
(por eso el refresco extra de las 18:20); `du` y `zdb` se cuelgan minutos con `ssdpool` saturado.

## Fases

Trabajo con el NAS: 16:10–23:00.

### 0 · Preparación — HECHA 2026-09-30 (AINF-401)

| Punto | Resultado (medido) |
|---|---|
| Ticket | **AINF-401** |
| Copia de la ACL | `~/headscale-policy-backup-2026-09-30.json` en el VPS (13 miembros, 2 reglas) |
| Origen del túnel `truenas-local` | `jellyfin.akunito.com` y `jellyseerr.akunito.com` → `http://192.168.20.200` (NPM :80, enruta por `Host`). Los hostnames públicos nuevos necesitan **también** proxy host en NPM |
| DNS `.local` del NAS | alias del override de pfSense id 3 (`jellyfin` → **`100.64.0.1`**); los del VPS son alias del id 2 (`grafana` → `100.64.0.6`); `akucraft.local` es el id 0. La API REST de pfSense funciona desde DESK_W11 (el ssh no: la clave de esta máquina no está autorizada) |
| NAT de pfSense | `192.168.8.0/24 → any` por Tailscale, descripción "UniFi inform": **no está limitada al VPS**, el inform a `100.64.0.1` debería pasar |
| Enlace VPS→NAS | 55,7 MiB/s (256 MiB de ROMs por ssh; Tailscale directo). Thumbnails: **se copian** (~15 min en bruto, más por ser 194 k ficheros) |
| Discos del NAS | `extpool` es NVMe, `ssdpool` raidz1 de 4 SSD: el restore local de restic gana a los 56 MiB/s del enlace (254 G ≈ 77 min por red) |
| Compose del VPS | leídos. Calibre sin `.env`; RomM: OIDC atado a `emulators.akunito.com` (no cambia); UniFi: 8443 en loopback, 8080 en la IP del tailnet; survival: `100.64.0.6:25565`, RCON en loopback, 11 G |
| Pendiente (solo dashboard) | hostnames del túnel del VPS y política de Access de Jellyfin (correo de Komi) |

### 1 · Mecanismo "bajo demanda" en el NAS — deploy NAS

- `lib/defaults.nix`: declarar `nasRootDockerProjects`, `nasRootlessDockerProjects` y `nasOnDemandDockerProjects` (default `[]`); `docs/profile-feature-flags.md`. Borrar `nasDockerProjects`.
- NAS_PROD: `nasOnDemandDockerProjects = calibre romm unifi gameservers/akucraft-{survival,solo,creative,staging}`; `restic` en `systemPackages`; `nasBackupAclPaths` += `/mnt/ssdpool/docker/{calibre,romm,unifi}`.
- `nas-services.nix`: hook pre-suspend que hace `compose down -t 120` de los proyectos de la lista **que existan y tengan contenedores vivos**, en paralelo, `TimeoutSec = 300`; sin post-resume ni arranque al boot.
- `nas-svc list|status|start|stop <nombre>` (lista cerrada del flag; `stop` = `down`; directorio ausente = "no instalado").
- Apartar primero los directorios viejos `/mnt/ssdpool/docker/{calibre-web,romm,unifi-db,unifi-network-application,emulatorjs}` a `_old-2026-03/`.
- Plantillas `templates/truenas/{calibre,romm,unifi}` y `gameservers/akucraft-{survival,solo,creative}`, añadidas a `ALL_TEMPLATE_PROJECTS`. **Staging queda fuera** (tiene un secreto literal en el compose y no tiene `.env`); solo se le cambia nada si se pasa antes el secreto a `.env`.
  - `restart: "no"`, tags del VPS (`unifi 10.5.67-ls141`, `mongo:8.0`, `romm 5.1.0`, `mariadb:12.2`, CWA por digest), mismos nombres de contenedor, `SKIP_CHOWN`/`NO_PERMISSIONS_CHECK` de CWA conservados.
  - Survival: puerto en `100.64.0.1:25565`, `stop_grace_period: 2m`, `cpus`, memoria 11 G.
  - UniFi: 8080/tcp y 3478/udp en `100.64.0.1`; 8443, 8083 (Calibre) y 8998 (RomM) donde los alcance NPM.
  - Bibliotecas en `/mnt/extpool/library/{calibre-library,romm-library}`; ingest de Calibre creado con dueño `100999`.

**Verificar**: deploy en verde; `grep -c zfsutil /etc/fstab` = 7; `restic version` responde; `nas-svc list` = 3 parados y 4 "no instalado"; nombre desconocido rechazado; `stop` dos veces no falla; creative encendido a las 23:00 → al día siguiente parado y sin `exited`.

### 2 · Datos (sin deploy)

1. **Congelar el VPS**: `systemctl stop akucraft-status-bot` (evita un `/start` del survival viejo), `compose down` de calibre, romm, unifi, minecraft, akucraft-web, akucraft-playermap. **Ningún reinicio del VPS hasta el deploy de la fase 3** (`homelab-docker` los volvería a levantar).
2. Copiar:

| Dato | Origen | Método |
|---|---|---|
| Bibliotecas (254 G) | **restic local en el NAS**, snapshot 27-09 | `sudo restic restore latest --tag libraries --target /mnt/extpool/library/.restore`; `mv .restore/home/akunito/{calibre-library,romm-library} .`; delta `sudo rsync -a --numeric-ids --delete` desde el VPS |
| Proyecto survival entero sin `world-snapshot` ni `.bak*` (~30 G) | VPS | tar dentro de contenedor por ssh → `gameservers/akucraft-survival/` |
| Proyectos calibre (sin thumbnails), romm, unifi + volúmenes `unifi_unifi_app_config`, `unifi_unifi_db_data_mongo8` | VPS en frío | tar dentro de contenedor → `/mnt/ssdpool/docker/{calibre,romm,unifi}`; compose y `.env` al proyecto en `compose/` |
| Thumbnails 50 G | VPS | `sudo rsync --numeric-ids` en segundo plano (no bloquea la puerta) |
| `akucraft-web`, `akucraft-playermap` (con `secrets/`) | VPS | tar dentro de contenedor → `gameservers/akucraft-archive/` |

3. Survival en el NAS: `addressToSend` → `100.64.0.1` en `automodpack-server.json` (dentro de contenedor).
4. Contraseña de `services.restic`: del VPS a `/run/user/1000/` del NAS; se borra al acabar la fase 6.
5. `ls -ln` de propietarios; `systemctl start nas-backup-acl`.

**Puerta de verificación (obligatoria antes de la fase 6)**: en VPS y NAS, dentro de un
contenedor, `find . -type f -exec sha256sum {} + | sort -k2` de cada árbol (sin `logs/`,
`.cache/`, thumbnails, `world-snapshot`); `diff` vacío salvo `automodpack-server.json`.
Presencia explícita de `level.dat`, `playerdata/*.dat`, `automodpack/.private/*`,
`EasyAuth/*`, `metadata.db`, cada `.env`. `mongod` y `mariadb` arrancan sin recuperación.

### 3 · Ingress y arranque — deploy VPS al final

Orden: NPM y pfSense → Cloudflare → deploy del VPS (antes, los `.local` darían NXDOMAIN).

| Host | Después | Cómo (rollback = deshacer la misma entrada) |
|---|---|---|
| `calibre.akunito.com`, `emulators.akunito.com`, `unifi.akunito.com` | túnel `truenas-local` | dashboard Cloudflare, origen `http://192.168.20.200` + proxy host en NPM para cada uno; Access va por hostname y se conserva |
| `akucraft-map.akunito.com` | eliminado (hostname + app de Access) | dashboard |
| `calibre.local`, `emulators.local`, `unifi.local` | NPM del NAS | proxy hosts a IP:puerto del host (UniFi: https + websockets); en pfSense (API) pasan de alias del id 2 a alias del id 3 (`100.64.0.1`) |
| `akucraft.local` | `100.64.0.1` | `VPS_PROD-config.nix:94-96` y override id 0 de pfSense |
| `akucraft-map.local` | eliminado | `VPS_PROD-config.nix:492-498` |

- VPS: `unifi romm calibre` fuera de `homelabDockerStacks` y `nginxLocalServices`; `nfsServerEnable`/`nfsExports` fuera (sin clientes activos, comprobado).
- **UniFi**: arrancar el controlador del NAS → `system_ip=100.64.0.1` → desde cada switch por ssh, comprobar que `http://100.64.0.1:8080/inform` responde → `set-inform`. Si no responde (regla NAT limitada al VPS): ampliar la regla en pfSense, o publicar 8080/3478 en `192.168.20.200`, abrirlos en el firewall del NAS y permitir `.180/.181 → 192.168.20.200` en pfSense.
  Rollback: levantar el stack del VPS y `set-inform` de vuelta; el del VPS solo se elimina en la fase 6.

**Verificar** (Diego, a mano, cada servicio arrancado con `nas-svc start`): las 3 URL públicas con Access, las 3 `.local`, un libro y una ROM abiertos, subir un libro por ingest, login OIDC de RomM, los 2 dispositivos UniFi "Connected", `systemctl is-active headscale` tras el deploy.

### 4 · AkuCraft: bot, tailnet, extras — deploy VPS + `sync-user.sh` en DESK y LAPTOP_X13

- Flag `akucraftDiscordEnable = false` (declarado en `defaults.nix`): sin token/guild/webhook; con él `akucraftAskEnable = false`, `INVITE_SCRIPT`/`MAP_ROSTER`/`MAP_URL` vacíos y la regla sudo de headscale condicionada al flag.
- `akucraft-bot.py`: `survival` con `ssh_host`, `gameservers/akucraft-survival`, `100.64.0.1:25565`; `compose stop` → `down`; textos sin mapa ni `:8100` ni `.mrpack` (el primer install queda sin servidor de descarga: no se esperan jugadores nuevos). Se pierden los anuncios de muertes/logros: aceptado.
- LiteLLM: fuera alias `akucraft-support*`, su fallback y `DEEPSEEK_KEY_DISCORD`; el gateway se queda.
- Clientes: `prodAddress` → `100.64.0.1:25565`; `stagingAddress`/`soloAddress` también (llevan mal desde el 25-08). AutoModpack pedirá la huella una vez.
- Scripts con rutas del VPS: `sync-akucraft-automodpack.py:64`, `generate-akucraft-manifest.sh:109-110`, `build-akucraft-pack.py`, `.claude/skills/akucraft-solo-reset.md`.
- Headscale, **en este orden**: `nodes delete -i 18`, `-i 19` → `policy set -f` (sin `tag:mc-guest`, sin `Komi_Macbook@`) → `users destroy -i` 16, 17, 18, 22. Irreversible salvo la ACL (copia de 0.2).

**Verificar**: `/start`, `/status`, `/stop` desde Telegram; cliente de DESK entra **y sincroniza el modpack** (Diego); idle-stop a los 45 min deja `docker ps -a` limpio; `headscale nodes list` sin invitados; `policy get` sin Komi ni `mc-guest`.

### 5 · Bot de infra, alertas, backups — deploy VPS y NAS

- `infra-bot`: flag `infraOnDemandServices` en VPS_PROD; `/svc list|start|stop` solo admins con confirmación, por ssh a `nas-svc`; NAS dormido → "💤". `/status nas` y el resumen dominical añaden "bajo demanda: N encendidos / M parados" (leído por ssh). `/help` actualizado. Ampliar el `doCheck` existente (`infra-bot.nix:40-44`) con tests de las funciones puras nuevas.
- `grafana.nix`: quitar `libraries` de la regex `:588-589` (cosmético).
- `restic-backup-vps.nix`: fuera `vps-restic-libraries`, el volumen UniFi (`:166`), exclude de thumbnails, hook de snapshot del mundo, `akucraft-backup-now`, `akucraft-restore-drill`, regla polkit.
- `restic-backup-nas.nix`: job `data` añade `/mnt/ssdpool/docker/{calibre,romm,unifi}` con `--exclude thumbnails/`.
- Survival entra solo en el job `akucraft`. **Sembrar antes** en el VPS `/var/lib/truenas-backups/staging-akucraft/gameservers/akucraft-survival/` desde el original local, con dueño `akunito` (tar `--no-same-owner` desde contenedor) y los mismos excludes del job (`mods/ libraries/ versions/ automodpack/ bluemap/ squaremap/ logs/`): evita subir 28 G desde casa contra un timeout de 2 h.
- Uptime Kuma (UI): fuera los monitores de `unifi`, `emulators`, `calibre`, `akucraft-map`.

**Verificar**: `/svc start calibre` → URL responde → `/svc stop`; nombre inválido y usuario no admin rechazados; deploy del NAS en verde con todo parado; `nas-backup-data` a mano en verde con `app.db` y las BBDD dentro; `nas-backup-akucraft` a mano en verde, sin transferir el mundo, con `level.dat` dentro; 24 h sin alertas nuevas en `/alerts`.

### 6 · Limpieza (mismo día, **solo con OK de Diego**)

Requisitos: puerta de la fase 2 pasada; verificaciones de 3, 4 y 5 hechas; los dos jobs de backup del NAS en verde una vez.

1. VPS: `~/calibre-library`, `~/romm-library`, `~/calibre-ingest`, `~/unifi-backup-20260813`, `~/romm-backup-20260813`, `~/.homelab/{calibre,romm,unifi,minecraft,minecraft-creative,akucraft-web,akucraft-playermap,backups,*.migrated-to-nas-*}`, volúmenes `unifi_*`, `romm_*`, `minecraft-staging_mc-data` y anónimos, imágenes huérfanas. Post-condición: `docker volume ls` y `ls ~/.homelab` sin ellos.
2. NAS `services.restic`, **como `akunito`, entre 16:10 y 19:00 o cuando acabe el job de las 19:30**, nunca en domingo por la tarde:
   - `restic forget --tag libraries --unsafe-allow-remove-all --dry-run` → revisar → sin `--dry-run`.
   - `restic rewrite --forget --tag services` con `--exclude` de `/home/akunito/.homelab/{minecraft/data,minecraft-creative,backups}` y los dos `*.migrated-to-nas-20260825` (lo pequeño restante caduca en hasta 3 meses).
   - `restic prune`; `restic check`. Si el NAS suspende a mitad, los datos están a salvo y `prune` se repite al día siguiente.
3. NAS: `_old-2026-03/`.
4. Opcional, con OK aparte: destruir los auto-snapshots de `extpool/vps-backups` para recuperar el espacio hoy.
5. Anotar `df` del VPS, tamaño del repo y `zfs list` antes y después.

### 7 · Documentación

`infrastructure-registry.md`, `vps-services.md`, `nas-services.md`, `nas.md`,
`network-switching.md`, `proxy-stack.md`, `pfsense.md`, `tailscale-headscale.md`
(`:81` dice `25565,25566`), `monitoring-stack.md`, `infra-alerts-telegram.md`,
`akucraft-manifest.md`, `profile-feature-flags.md`, comandos `update-infra-vps-and-nas`
y `docker-startup-nas`, comentario en `templates/truenas/homelab/docker-compose.yml:25`;
`python3 scripts/generate_docs_index.py`.

## Rollback por fase

| Fase | Vuelta atrás |
|---|---|
| 1 | revert + deploy NAS |
| 2 | nada que deshacer: el VPS sigue intacto; `compose up` allí y arrancar el bot |
| 3 | deshacer entradas de Cloudflare/NPM/pfSense, revert + deploy VPS, UniFi según su nota |
| 4 | revert + deploy; la ACL desde la copia de 0.2; usuarios invitados **no** se recuperan (se recrean) |
| 5 | revert + deploy |
| 6 | **ninguna** |

## Riesgos que quedan

- Contenido del snapshot de bibliotecas no comprobado hasta la fase 2; el delta y el manifiesto lo cubren.
- Tras la fase 6 las bibliotecas tienen una sola copia (aceptado).
- Cambios a mano (Cloudflare, NPM, pfSense, Kuma) no quedan en el repo: se documentan en la fase 7.
- Fases 1–5 caben en una o dos tardes; la verificación de 24 h de la fase 5 no bloquea la limpieza si Diego da el OK; la fase 6 no se empieza después de las 21:00.

## Fuera de alcance (detectado, no pedido)

- Headscale: usuario `LAPTOP_L15` sin nodo, nodo `truenas-1` sin conexión desde el 13-09.
- Otros restos en `/mnt/ssdpool/docker/` (`nextcloud-data`, `freshrss`, `obsidian-remote`, `syncthing`, `redis-local`).
- `deepseekApiKeyIngame`: sin uso desde el 02-09, pendiente de revocar en el proveedor.
- Registro: `enp10s0` del NAS no tiene IPv4; el "192.168.8.206" de la documentación no está vivo.
