---
id: akunito.plans.nas-on-demand-services
summary: AkuCraft hibernado (bot solo Telegram, Discord e invitados fuera) y Minecraft survival + Calibre + RomM + UniFi mudados del VPS al NAS como servicios bajo demanda, con limpieza de copias y monitorización alineada
tags: [nas, vps, minecraft, akucraft, calibre, romm, unifi, headscale, backups, infra-bot, migration]
related_files:
  - system/app/nas-services.nix
  - system/app/akucraft-bot.py
  - system/app/akucraft-status-bot.nix
  - system/app/infra-bot.py
  - system/app/infra-notify.nix
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
Auditado el 2026-09-30 (4 bloqueantes y 11 mayores corregidos abajo).

## Decisiones (entrevista 2026-09-30)

| Tema | Decisión |
|---|---|
| Bot AkuCraft | Sigue **solo Telegram**, remapeado al NAS. **Discord desconectado** "por el momento" (secretos y código se quedan) |
| Invitados Minecraft | Se borran: usuarios `MC_Guest_{Zuza,Ulfhogg,Ankred,wonsio}`, nodos `desktop-542nkge` y `desktop-ko51j7r`, regla y `tagOwners` de `tag:mc-guest` |
| Komi ("Misia") | **Desactivar, no borrar**: `Komi_Macbook@` sale de `group:family`; nodo y usuario se quedan. Volver = una línea en la ACL |
| Ingress | **Nativo en el NAS**: públicos por el túnel `truenas-local`, `.local` por NPM + overrides de pfSense |
| Arranque | Minecraft por el bot de AkuCraft; Calibre/RomM/UniFi por `/svc` en el bot de infra + script `nas-svc` |
| Bibliotecas | Sin copia extra: si se pierden, se vuelven a descargar |
| Extras AkuCraft | `akucraft-web`, `akucraft-playermap` y alias LiteLLM: **archivados** |
| Limpieza | **El mismo día**, tras verificación y OK explícito de Diego |

## Medidas (2026-09-30, medidas salvo que diga "estimado")

| Qué | Dónde hoy | Tamaño |
|---|---|---|
| Minecraft survival `data/` | VPS `~/.homelab/minecraft` | 57 G = `world` 28 G + `world-snapshot` 28 G (**no se muda**) + 1,6 G resto |
| Calibre biblioteca | VPS `~/calibre-library` | 211 G |
| Calibre config | VPS `~/.homelab/calibre/data/config` | 50 G, casi todo `thumbnails/` (fuera del backup) |
| ROMs | VPS `~/romm-library` | 43 G |
| RomM datos + BD / UniFi | VPS | 156 M / <100 M legibles (mongo no medible sin root) |
| Restos AkuCraft | VPS `~/.homelab/{backups,minecraft-creative,*.migrated-to-nas-*}` | 8,9 + 2,8 + 5,1 G |

NAS: `ssdpool` 2,85 T libres, `extpool` 1,03 T libres. VPS: 746 G usados, 210 G libres.
Después (estimado): `ssdpool` −335 G; VPS −~330 G (385 G borrados, ~55 G vuelven como
copia offsite del mundo, ver fase 5); `extpool` +~280 G, **visibles a los 7 días**
(`extpool/vps-backups` tiene auto-snapshots que retienen lo purgado).

## Hechos que condicionan el diseño

- Los compose del VPS **no están en este repo**. Los del NAS salen de `templates/truenas/` vía `scripts/nas-docker-startup.sh`, cuyo array `ALL_TEMPLATE_PROJECTS` (`:46`) está a mano; `gameservers/*` no tiene plantilla: los compose vivos del NAS son la única copia.
- `nasDockerProjects` (`NAS_PROD-config.nix:135-142`) es config muerta; el módulo lee `nasRootDockerProjects` / `nasRootlessDockerProjects`, que no están en `lib/defaults.nix`.
- **Un dataset ZFS nuevo sin entrada en `nasZfsMountPoints` deja el NAS en modo emergencia** en el siguiente arranque (`nas-services.nix:288-292`). Por eso **no se crea dataset**: las bibliotecas van a `/mnt/ssdpool/media/library/`.
- **`restic` no está instalado en el NAS** (`/run/wrappers/bin/restic` es un wrapper colgante).
- `level.dat`, `playerdata` y `automodpack/.private` son `0600 uid 100999`: un `rsync`/`tar` como `akunito` los salta en silencio. Todo lo que pertenece a contenedores se copia y verifica **desde dentro de un contenedor** (mismo subuid 100000 en ambos hosts).
- Stack fuera de las listas de suspensión = no se para a las 23:00 y pierde puertos al despertar (`nas-services.nix:638-642`). El hook actual tiene `TimeoutSec = 180` y el compose de survival no tiene `stop_grace_period`.
- `restart: unless-stopped` resucita contenedores (creative, solo, plantilla vieja de UniFi).
- `infra-notify` pinta "🟡 containers not running" por cada `exited` → **`compose down`**, nunca `stop`.
- cAdvisor deja de exportar un contenedor en cuanto para: `ContainerDown` **no salta** en paradas limpias, y el bot de infra no ve "parado", ve "no existe".
- `services.restic` = todo `~/.homelab` + bibliotecas (job dominical, mismo repo). No contiene thumbnails ni el volumen mongo de UniFi; las BBDD están copiadas en caliente. El job diario del VPS escribe en él a las 19:30.
- Nodos invitados pertenecen a `tagged-devices`, no a los usuarios `MC_Guest_*`. Una política que referencia un usuario inexistente impide arrancar headscale.
- Quitar `unifi/emulators/calibre` de `nginxLocalServices` borra sus registros MagicDNS (`headscale.nix:34-38`).
- NAS dormido 23:00–16:00: los servicios bajo demanda solo existen en esa ventana. `nas-rtc-wake` programa siempre las 16:00: **una suspensión manual deja el NAS fuera hasta el día siguiente**.
- La clave ssh VPS→NAS del bot AkuCraft es la de `/restart` del bot de infra. No se toca.

## Fases

Cambios de Nix: commit + push → `install.sh` (VPS y NAS `-s -d`). Un deploy por
máquina a la vez. Trabajo con el NAS: 16:10–23:00.

### 0 · Preparación (solo lectura)

1. Ticket AINF (buscar antes de crear); ID en todos los commits.
2. `headscale policy get > ~/headscale-policy-backup-2026-09-30.json`.
3. Dashboard Cloudflare: origen que usa `truenas-local` para `jellyfin.akunito.com`; correo de Komi en su política de Access.
4. pfSense: a qué IP apunta hoy `jellyfin.local` (los nuevos siguen la misma convención).
5. Medir VPS→NAS con un fichero de 1 G (decide thumbnails: copiar o regenerar).
6. Leer compose y nombres de variables de `.env` de los cuatro stacks del VPS.

### 1 · Mecanismo "bajo demanda" en el NAS (repo)

- `lib/defaults.nix`: declarar `nasRootDockerProjects`, `nasRootlessDockerProjects`, y el nuevo `nasOnDemandDockerProjects` (default `[]`); `docs/profile-feature-flags.md`. Borrar `nasDockerProjects`.
- NAS_PROD: `nasOnDemandDockerProjects = calibre romm unifi gameservers/akucraft-{survival,solo,creative,staging}`; `restic` en `systemPackages`; `nasBackupAclPaths` += `compose/{calibre,romm,unifi}`.
- `nas-services.nix`: hook pre-suspend que hace `compose down -t 120` **solo de los proyectos con contenedores vivos**, en paralelo, `TimeoutSec = 300`; sin post-resume ni arranque al boot.
- `nas-svc list|status|start|stop <nombre>` en `systemPackages` (lista cerrada generada del flag; `stop` = `down`).
- Plantillas nuevas `templates/truenas/{calibre,romm,unifi}` y `gameservers/akucraft-{survival,solo,creative,staging}` (las tres últimas importadas de los compose vivos, sin secretos); todas en `ALL_TEMPLATE_PROJECTS`.
  - `restart: "no"`, tags del VPS (`unifi 10.5.67-ls141`, `mongo:8.0`, `romm 5.1.0`, `mariadb:12.2`, CWA por digest), mismos nombres de contenedor.
  - Survival: `stop_grace_period: 2m`, `cpus`, memoria 11 G como en el VPS.
  - UniFi: 8080/tcp y 3478/udp publicados en `100.64.0.1`, 8443 donde lo alcance NPM.
  - Datos de estado con bind absoluto bajo el propio proyecto; bibliotecas en `/mnt/ssdpool/media/library/{calibre-library,romm-library}`; directorio de ingest de Calibre creado.

**Verificar**: deploy NAS en verde; `grep -c zfsutil /etc/fstab` sigue en 7; `restic version` responde;
`nas-svc list` = 7 parados; `nas-svc start xx` rechaza nombre desconocido; `stop` dos veces seguidas no falla;
arrancar creative y esperar a la suspensión natural de las 23:00 → al día siguiente parado y `docker ps -a` sin `exited`.

### 2 · Datos

Primero **parar los cuatro stacks en el VPS** (`compose down`; CWA tiene WAL activo). Desde ese momento el VPS es origen congelado.

| Dato | Origen | Método |
|---|---|---|
| Bibliotecas (254 G) | **restic local en el NAS**, snapshot del 27-09 | `sudo restic restore latest --tag libraries --target /mnt/ssdpool/media/library/.restore`, `mv` al sitio final (mismo dataset), delta `rsync` desde el VPS |
| Proyecto survival entero sin `world-snapshot` (~29 G: `data/`, compose, `.env`, `datapacks/`, scripts) | VPS | tar **dentro de contenedor** por ssh (método de creative) |
| Proyectos calibre (sin thumbnails), romm, unifi enteros + volúmenes `unifi_unifi_app_config` y `unifi_unifi_db_data_mongo8` | VPS en frío | tar dentro de contenedor |
| Thumbnails 50 G / 194 k ficheros | VPS | `rsync` en segundo plano si 0.5 lo permite; si no, CWA los regenera |
| `akucraft-web`, `akucraft-playermap` (incl. `secrets/`), `/var/lib/akucraft-status` no se toca | VPS | tar a `gameservers/akucraft-archive/` |

- Contraseña de `services.restic`: del VPS a `/run/user/1000/` del NAS, se borra al acabar la fase 6.
- Tras el restore: `ls -ln` de propietarios, `systemctl start nas-backup-acl`.
- Directorios viejos del NAS (`/mnt/ssdpool/docker/{calibre-web,romm,unifi-db,unifi-network-application,emulatorjs}`) apartados a `_old-2026-03/`.

**Puerta de verificación (obligatoria antes de la fase 6)**: manifiesto
`find . -type f -exec sha256sum {} +` generado **dentro de un contenedor** en VPS y NAS
para cada árbol, `diff` vacío; comprobación explícita de `level.dat`, `playerdata/*.dat`,
`automodpack/.private/*`, `EasyAuth/*`, `.env` de cada stack; `mongod` y `mariadb` arrancan sin recuperación.

### 3 · Ingress y arranque de cada servicio

Orden: **overrides de pfSense y proxy hosts de NPM primero**, deploy del VPS después (si no, los nombres dan NXDOMAIN entre medias).

| Host | Después | Cómo (rollback = deshacer la misma entrada) |
|---|---|---|
| `emulators.akunito.com`, `unifi.akunito.com` | túnel `truenas-local` | dashboard Cloudflare; Access va por hostname y se conserva |
| `akucraft-map.akunito.com` | eliminado (hostname + app de Access) | dashboard |
| `calibre.local`, `emulators.local`, `unifi.local` | NPM del NAS | proxy hosts (UniFi: upstream https + websockets); override pfSense a la IP de 0.4 |
| `akucraft.local` | `100.64.0.1` | `VPS_PROD-config.nix:94-96` |
| `akucraft-map.local` | eliminado | `VPS_PROD-config.nix:492-498` |

- VPS: `unifi romm calibre` fuera de `homelabDockerStacks` y `nginxLocalServices`; `nfsServerEnable`/`nfsExports` fuera.
- UniFi: arrancar el controlador del NAS → `system_ip=100.64.0.1` → `set-inform http://100.64.0.1:8080/inform` en `.180` y `.181`. El del VPS no vuelve a encenderse (dos controladores con la misma clave se pelean por los dispositivos).
- Con el servicio parado las URLs dan 502: esperado.

**Verificar** (Diego, a mano, cada servicio arrancado con `nas-svc start`): URL pública con login de Access, URL `.local`, un libro y una ROM abiertos, login OIDC de RomM, los 2 dispositivos UniFi "Connected", `headscale` activo tras el deploy.

### 4 · AkuCraft: bot, tailnet, extras

- Flag `akucraftDiscordEnable = false`: sin token/guild/webhook no arrancan gateway ni anuncios. Con él: `akucraftAskEnable = false`, `INVITE_SCRIPT`/`MAP_ROSTER`/`MAP_URL` vacíos, regla sudo de headscale fuera.
- `akucraft-bot.py`: `survival` con `ssh_host`, `gameservers/akucraft-survival`, `100.64.0.1:25565`; `compose stop` → `down` (el `/stop` ya se niega con jugadores dentro); textos sin mapa ni `:8100`. Se pierden los anuncios de muertes/logros: aceptado.
- LiteLLM: fuera alias `akucraft-support*`, su fallback y `DEEPSEEK_KEY_DISCORD`; el gateway se queda.
- Clientes: `prodAddress`, `stagingAddress`, `soloAddress` → `100.64.0.1` (`minecraft-client-mods.nix:737-761`). AutoModpack pedirá la huella una vez.
- Headscale, **en este orden**: `nodes delete -i 18` y `-i 19` → `policy set` (sin `tag:mc-guest`, sin `Komi_Macbook@`) → `users destroy` 16, 17, 18, 22.
- `.claude/skills/akucraft-solo-reset.md`: ruta del VPS obsoleta.

**Verificar**: `/start`, `/status`, `/stop` desde Telegram; entrar con el cliente de DESK (Diego); idle-stop a los 45 min deja `docker ps -a` limpio; `headscale nodes list` sin invitados; `policy get` sin Komi; `systemctl restart headscale` arranca (prueba que la política valida).

### 5 · Bot de infra, alertas, backups

- `infra-bot`: flag `infraOnDemandServices` en VPS_PROD (nombre → proyecto); `/svc list|start|stop` solo admins con confirmación, por ssh a `nas-svc`; NAS dormido → "💤". `/status nas` y el resumen dominical añaden la línea "bajo demanda: N encendidos / M parados" leída por ssh. `/help` actualizado.
- No existe harness de tests para los bots: se crea uno mínimo (`unittest`) para las funciones puras nuevas; el resto son las pruebas a mano de abajo.
- `infra-notify.nix`: ignora contenedores de la lista bajo demanda.
- `grafana.nix`: sin cambios en `ContainerDown`; quitar `libraries` de la regex `:588-589` (cosmético, nunca disparó).
- `restic-backup-vps.nix`: fuera `vps-restic-libraries`, el volumen UniFi (`:166`), exclude de thumbnails, hook de snapshot del mundo, `akucraft-backup-now`, `akucraft-restore-drill`, regla polkit.
- `restic-backup-nas.nix`: job `data` añade calibre (sin thumbnails), romm, unifi. Survival entra solo en el job `akucraft`: **sembrar en el VPS** `staging-akucraft/akucraft-survival/` desde el original local antes de borrarlo (evita subir 28 G por el enlace de casa contra un timeout de 2 h). Coste en el VPS: ~28 G de staging + hasta ~28 G de repo.
- Uptime Kuma (UI): fuera los monitores de `unifi`, `emulators`, `calibre`, `akucraft-map`.

**Verificar**: `/svc start calibre` → URL responde → `/svc stop`; nombre inválido rechazado; usuario no admin rechazado; deploy del NAS en verde con todo parado; `nas-backup-data` y `nas-backup-akucraft` lanzados a mano terminan en verde y contienen `level.dat`; 24 h sin alertas nuevas en `/alerts`.

### 6 · Limpieza (mismo día, **solo con OK de Diego**, tras 2–5 verificadas)

Requisitos: puerta de la fase 2 pasada, los dos jobs de backup del NAS ejecutados una vez en verde.

1. VPS: `~/calibre-library`, `~/romm-library`, `~/calibre-ingest`, `~/unifi-backup-20260813`, `~/romm-backup-20260813`, `~/.homelab/{calibre,romm,unifi,minecraft,minecraft-creative,akucraft-web,akucraft-playermap,backups,*.migrated-to-nas-*}`, volúmenes `unifi_*`, `romm_*`, `minecraft-staging_mc-data` y anónimos, imágenes huérfanas. Post-condición: `docker volume ls` y `ls ~/.homelab` sin ellos; `df`.
2. NAS `services.restic`, **como `akunito`, entre 16:10 y 19:00 o después de que acabe el job de las 19:30**, nunca en domingo tarde:
   `restic forget --tag libraries --unsafe-allow-remove-all --dry-run` → revisar → sin `--dry-run`;
   `restic rewrite --forget --tag services --exclude '/home/akunito/.homelab/minecraft/data'` (solo el árbol grande; lo pequeño caduca con la retención de 30 d);
   `restic prune`; `restic check`. Si el NAS suspende a mitad, los datos están a salvo y `prune` se repite al día siguiente.
3. NAS: `_old-2026-03/`.
4. Opcional, con OK aparte: destruir los auto-snapshots de `extpool/vps-backups` para recuperar el espacio hoy y no en 7 días.
5. Anotar `df` del VPS, tamaño del repo y `zfs list` antes y después.

### 7 · Documentación

`infrastructure-registry.md`, `vps-services.md`, `nas-services.md`, `nas.md`,
`network-switching.md`, `proxy-stack.md`, `pfsense.md`, `tailscale-headscale.md`
(`:81` dice `25565,25566`), `monitoring-stack.md`, `infra-alerts-telegram.md`,
`akucraft-manifest.md`, `profile-feature-flags.md`, comandos `update-infra-vps-and-nas`
y `docker-startup-nas`; `python3 scripts/generate_docs_index.py`.

## Riesgos que quedan

- **Contenido del snapshot de bibliotecas no comprobado** hasta tener la contraseña en la fase 2; si falta algo, el delta `rsync` y el manifiesto lo cubren (el VPS sigue intacto hasta la fase 6).
- **Tras la fase 6** las bibliotecas tienen una sola copia (aceptado).
- **Cambios a mano** (Cloudflare, NPM, pfSense, Kuma) no quedan en el repo: se documentan en la fase 7.
- **Ruta `.local` por pfSense** pierde ~10 % de conexiones para clientes remotos del tailnet (medido 2026-09-18); en casa no afecta.
- **Ventana**: fases 1–5 caben en una tarde larga o dos; la fase 6 no se empieza después de las 21:00.

## Fuera de alcance (detectado, no pedido)

- Headscale: usuario `LAPTOP_L15` sin nodo, nodo `truenas-1` sin conexión desde el 13-09.
- Otros restos en `/mnt/ssdpool/docker/` (`nextcloud-data`, `freshrss`, `obsidian-remote`, `syncthing`, `redis-local`).
- `deepseekApiKeyIngame`: sin uso desde el 02-09, pendiente de revocar en el proveedor.
- `ContainerDown` está en pending para `calibre-web-automated` en el VPS por series duplicadas; desaparece con la mudanza.
