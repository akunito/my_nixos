---
id: infrastructure.immich.compression-cutover-runbook
summary: Runbook definitivo (script v2.1) del cutover de la biblioteca comprimida de Immich en VPS_PROD — riesgos de las dos auditorías eliminados, con puertas de verificación y reversión quirúrgica
tags: [immich, vps, migration, runbook]
related_files: [docs/akunito/plans/immich-compression-cutover-audit.md, docs/akunito/plans/immich-compression-pipeline.md]
date: 2026-08-19
status: published
---

# Immich compression — RUNBOOK de cutover (v2)

Sustituye al plan auditado en `immich-compression-cutover-audit.md`. La auditoría
del 2026-08-19 encontró que el script v1 **borraba/sobrescribía** los originales
en vez de archivarlos. Este runbook usa el script **v2.1** (ya desplegado en el VPS:
`~/.homelab/immich-dev/cutover.sh`; anteriores en `cutover.sh.v1` y `cutover.sh.v2.bak`).
La re-auditoría del mismo día añadió a v2: modos `test-ids`/`revert-ids` (probar vídeo+PNG,
no solo JPEG) y guarda de `PLACEFAIL` (ningún fallo de colocación llega a la DB);
preflight re-ejecutado con v2.1: **ALL PASS**.

**Conexión**: `ssh -A -p 56777 akunito@100.64.0.6` (todo lo de abajo se ejecuta ahí,
desde `~/.homelab/immich-dev/`).

## 0. Qué corrige v2 (hallazgos de la auditoría)

| Hallazgo v1 | Solución v2 |
|---|---|
| `rm -f` del original (33,853 JPEG) y sobrescritura en sitio (1,829 vídeo/PNG) | `place_one` **archiva** cada original con `mv` a `~/immich-preclone-originals/` (mismo fs → instantáneo, sin espacio extra) antes de colocar el comprimido. Nada se borra nunca. |
| `test N` no era reversible | `test N` archiva igual; `revert N` deshace archivos **y** DB de esos N. |
| Sin control de rowcounts en el UPDATE | La transacción incluye un bloque `DO` que compara líneas del mapa vs filas aplicadas en `asset` y `asset_exif`; cualquier desajuste → `RAISE` → **rollback automático**. `ON_ERROR_STOP` activado. |
| Reversión de DB solo vía pg_restore completo | `gen-revert` capturó el estado pre-cutover de los 35,682 assets (`revert_map.tsv`) → `revert N|all` restaura filas quirúrgicamente sin tocar el resto de la DB. |
| Sin comprobaciones automatizadas | Modos `preflight` (11 checks read-only) y `verify` (post-cutover: existencia+tamaño de todos los archivos, sha1 de muestra 100, y conteo DB↔mapa). |
| `place-all` podía correr con Immich arriba | `place-all` se niega si `immich_server` está corriendo. |
| `test N` solo probaba JPEG (los primeros N del mapa por UUID) | Modo `test-ids ID...` para probar assets concretos → el PASO 1 incluye 1 vídeo + 1 PNG además de los 3 JPEG. `revert-ids` deshace. |
| Un `PLACEFAIL` en `place-all` no impedía el UPDATE de DB (asset roto commiteado) | `place-all` y `test*` cuentan fallos de colocación y **se niegan a tocar la DB** si hay alguno. |

## 1. Estado de preparación (hecho el 2026-08-19, todo read-only)

- Script v2 desplegado y `bash -n` OK. `revert_map.tsv` generado: 35,682 líneas.
- **`preflight`: ALL PASS** — 6 campos/línea, sin ids duplicados, sin checksums
  duplicados por owner (los 24 dups globales son entre los dos usuarios → no violan
  `UQ_assets_owner_checksum (ownerId, checksum)`), sin caracteres que rompan el COPY,
  todos los ids existen en prod (38,895 assets), los 35,682 archivos dev presentes
  con el tamaño registrado, los 35,682 originales presentes en prod, mismo
  filesystem (hardlinks OK), 198 GB libres.
- Dump DB de hoy: `~/immich-precutover-db-20260819-1114.sql.gz` (218 MB).

## 2. Redes de seguridad (cuádruple)

1. **Originales archivados** en `~/immich-preclone-originals/` (v2; se crean durante el cutover).
2. **`revert_map.tsv`** → reversión quirúrgica de DB por asset (`cutover.sh revert`).
3. **`pg_dump`** completo pre-cutover (regenerar justo antes del PASO 2).
4. **Restic en NAS** (`sftp:akunito@nas-aku:/mnt/extpool/vps-backups/immich.restic`) — GATE 0.

## 3. GATE 0 — backup restic fresco y verificado (OBLIGATORIO antes del PASO 2)

> ✅ **COMPLETADO 2026-08-20 15:39** — snapshot fresco `3ea11af9` (121.073 GiB,
> incluye pg_dumpall), verificado restaurando una muestra: sha1 restaurado == sha1
> vivo (`GATE0_VERIFY_OK`). Ventana de retención: limpieza (PASO 4) antes del **~19-sep**.

La NAS duerme 23:00–16:00 (despertar antes: skill `/wake-on-lan-nas`).

```bash
# 1) lanzar backup fresco (incremental; incluye pg_dumpall) y seguirlo
sudo systemctl start vps-restic-immich.service
journalctl -fu vps-restic-immich.service    # esperar "Backup complete"

# 2) verificar restaurando una muestra y comparando sha1 contra prod
export RESTIC_PASSWORD_FILE=/etc/secrets/restic-immich
R() { /run/wrappers/bin/restic -r sftp:akunito@nas-aku:/mnt/extpool/vps-backups/immich.restic \
      -o "sftp.command=ssh -i ~/.ssh/id_ed25519_restic -o BatchMode=yes akunito@nas-aku -s sftp" "$@"; }
R snapshots | tail -5
F=$(head -1 ~/.homelab/immich-dev/cutover_map.tsv | cut -d'|' -f2)   # /data/upload/...
R restore latest --target /tmp/restic-verify --include "/home/akunito/immich-library${F#/data}"
sha1sum "/tmp/restic-verify/home/akunito/immich-library${F#/data}" "/home/akunito/immich-library${F#/data}"
rm -rf /tmp/restic-verify
```
Los dos sha1 deben coincidir. No continuar sin esto.

> Política de retención: `--keep-within 30d --keep-monthly 3`. El snapshot
> pre-cutover con originales queda garantizado ~30 días → **decidir la limpieza
> (PASO 6) antes del ~18-sep** o los originales quedarán solo en el archivo local.

## 4. PASO 1 — prueba de 6 assets: 3 JPEG + 2 VÍDEOS + 1 PNG (Immich ARRIBA, reversible de verdad)

El `test 3` original solo cubría JPEG (los primeros del mapa por UUID). El punto más
incierto del cutover es el **vídeo**, y hay DOS casos distintos en prod:
- **583 vídeos CON copia `encoded_video`** (H.264): la app seguirá sirviendo esa copia
  existente → deben reproducirse igual que hoy.
- **222 vídeos SIN copia `encoded_video`**: hoy la app reproduce el original directamente.
  Tras el cutover el original es AV1 (con la DB aún diciendo h264) → solo reproducirá en
  dispositivos con decodificación AV1 (Pixel sí; GT 2 probablemente no). **El PASO 3
  (Video Conversion=All) lo arregla definitivamente** — por eso deja de ser opcional.

Probar UN vídeo de cada caso antes del `place-all`:

```bash
cd ~/.homelab/immich-dev
bash cutover.sh preflight                      # debe seguir ALL PASS
bash cutover.sh test 3                         # 3 JPEG→AVIF (cambio de extensión)
bash cutover.sh test-ids \
  083cdd07-6300-4e49-984a-90b36739d2c4 \
  00792f30-5c9b-4f8f-94f1-6ae4a410627d \
  72276b57-c17b-4701-a972-2598e7d9316e
# 083cdd07 = VID20250128191700.mp4 (28 MB, CON encoded_video)
# 00792f30 = VID20220115131856.mp4 (57 MB, SIN encoded_video → caso AV1 directo)
# 72276b57 = rubocop-small2.png   (oxipng, sin cambio de extensión)
```
Verificar:
- Web (`pictures.local.akunito.com` — la pública `pictures.akunito.com` está tras
  Cloudflare Access) o la app: las 3 fotos se ven y se descargan como `.avif`; el PNG se ve.
- **`VID20250128191700.mp4` SE REPRODUCE en la app** ← puerta crítica (caso 583).
- `VID20220115131856.mp4`: probar en la app; si NO reproduce en algún dispositivo,
  NO es bloqueante — es el caso 222 que el PASO 3 corrige (queda verificado que solo
  falla por decodificación AV1, no por el cutover en sí).
- DB de los 6: `originalPath`/checksum actualizados (el `verify` del PASO 2 cubre el resto).
- **App móvil**: abrirla y comprobar que NO encola re-subidas. (El estado de backup
  usa `deviceAssetId`, que no se toca, así que no debería; esta es la comprobación
  empírica del único riesgo no eliminable por adelantado.)

Si algo falla:
`bash cutover.sh revert 3` y
`bash cutover.sh revert-ids 083cdd07-6300-4e49-984a-90b36739d2c4 00792f30-5c9b-4f8f-94f1-6ae4a410627d 72276b57-c17b-4701-a972-2598e7d9316e`
→ estado idéntico al previo (archivos + DB).

## 5. PASO 2 — cutover completo (downtime < 10 min)

> ✅ **COMPLETADO 2026-08-21 13:38** (downtime 13:28→13:38). place-all + UPDATE 35682×2
> commiteado con guarda OK; `verify`: 0 bad files, sha1 100/100, conteos 35682/35682/35682.
> Gotcha encontrado: la 1ª pasada dio 6 `PLACEFAIL` espurios en los assets ya cortados en
> el PASO 1 (GNU `mv` se niega entre dos hardlinks del mismo inodo) → la guarda abortó la
> DB como debía; parche de idempotencia en `place_one` (`[ "$newh" -ef "$devh" ] && return 0`,
> script v2.2, anterior en `cutover.sh.v21.bak`) y 2ª pasada limpia en 4 s.

Evitar domingo ~21:00 (colisión con el timer `vps-restic-immich`).

```bash
# dump DB fresco inmediatamente antes
docker exec immich_postgres pg_dump -U postgres -d immich | gzip > ~/immich-precutover-db-$(date +%Y%m%d-%H%M).sql.gz

docker stop immich_server
cd ~/.homelab/immich-dev
bash cutover.sh place-all        # archiva 35,682 originales + coloca hardlinks + UPDATE en 1 transacción
bash cutover.sh verify           # 0 bad files, 0 bad sha, y los 3 conteos DB idénticos (35682)
docker start immich_server
```
- Si `place-all` falla en la fase de archivos: reejecutable (idempotente) o `revert all`.
- Si falla el UPDATE de DB: se hace rollback solo (prod DB intacta); los archivos ya
  colocados se deshacen con `bash cutover.sh revert all`.

Validación humana tras arrancar: timeline, un álbum, favoritos, caras, reproducir un
vídeo en la app, descargar una foto. Confirmar en la app móvil que no hay re-subidas
masivas encoladas (si las hubiera: pararlas en la app y avisar — los duplicados se
detectan con `select checksum from asset group by 1 having count(*)>1`).

**Reglas durante la ventana de confianza (hasta el PASO 6):**
- NO ejecutar `metadataExtraction` / "Refresh metadata" (re-derivaría fechas).
- NO vaciar la papelera (250 assets; borraría archivos colocados — recuperables desde
  el clon, pero mejor no).

## 6. PASO 3 (YA NO opcional; además ~20 GB extra) — streams 720p en prod

> ✅ **COMPLETADO 2026-08-21 ~19:00** — 2,131 vídeos, 0 fallos. encoded-video 32→12 GB.
> Los 222 sin stream ahora tienen H.264 720p (reproducción universal). Biblioteca 84 GB.
> Config permanente: 720p + 2000k + veryfast + transcode=all. Gotcha: el vhost nginx
> local corta `x-api-key` — la API de prod se ataca directa a `127.0.0.1:2283`.

Admin → Video Transcoding → resolución 720p + maxBitrate 2000k → lanzar
Video Conversion = All. Igual que se hizo en dev.

**Por qué es necesario**: 222 de los 805 vídeos re-codificados no tienen copia
`encoded_video` en prod — tras el cutover su original es AV1 y solo reproducirían en
dispositivos con decodificación AV1. `Video Conversion=All` genera copias H.264 720p
para TODOS (ffmpeg de Immich decodifica AV1 sin problema — probado en dev) →
reproducción universal restaurada + ahorro extra. Ejecutarlo el mismo día del cutover.
(Es `videoConversion`, NO `metadataExtraction` — no toca fechas.)

## 7. PASO 4 — LIMPIEZA (tras ≥7 días de uso normal; libera el espacio)

```bash
rm -rf ~/immich-preclone-originals            # ~74 GB de originales archivados
docker compose -p immich-dev down -v          # -v: el docker rootless nunca se poda solo
rm -rf ~/immich-dev-library                   # los hardlinks de prod sobreviven
rm -f ~/immich-precutover-db-*.sql.gz         # conservar revert_map.tsv (es diminuto)
# + retirar vhost pictures-dev.local.akunito.com y su DNS; borrar álbumes de muestra en prod si los hubiera
```
Ahorro neto: ~18 GB (originales) o ~38 GB con el PASO 3. El disco no crece en ningún
punto intermedio (mv + hardlinks en el mismo filesystem).

## 8. Matriz de reversión

| Momento | Cómo volver atrás |
|---|---|
| Tras `test N` | `bash cutover.sh revert N` |
| Tras `test-ids ID...` | `bash cutover.sh revert-ids ID...` (mismos ids) |
| `place-all` interrumpido | Reejecutar `place-all` (idempotente) o `revert all` |
| UPDATE DB falló | Nada que hacer en DB (rollback automático); `revert all` para los archivos |
| Tras cutover completo | `docker stop immich_server && bash cutover.sh revert all && docker start immich_server` |
| Catástrofe (archivo local perdido) | Restaurar DB del dump + biblioteca del snapshot restic pre-cutover |
| Tras el PASO 4 (limpieza) | Ya solo restic (snapshot pre-cutover vivo ~30 días desde GATE 0) |

## 9. Riesgos residuales asumidos

- **Re-subida desde la app móvil**: ⚠️ MATERIALIZADO 2026-08-21 — en v3 el dedup del
  backup es POR CHECKSUM (no existe `deviceAssetId`); el móvil re-subió 48 fotos aún
  presentes en el teléfono. Solución = **escudo de papelera**: las re-subidas se mandan
  a la papelera (soft-delete) y NO se vacía — su checksum en DB hace que la app las vea
  como duplicado y no vuelva a subirlas. Identificación certera: `createdAt` > cutover
  AND checksum ∈ sha1 originales de `revert_map.tsv`. Al reactivar el backup puede subir
  UNA vez más lo que quede en local → repetir el script. **NO VACIAR LA PAPELERA** mientras
  los teléfonos conserven fotos pre-cutover en local.
- Los originales JPEG desaparecen definitivamente en el PASO 4 — a partir de ahí la
  "copia maestra" es AVIF/AV1. Decisión ya tomada en el proyecto de compresión.
- La metadata de vídeo en DB (`asset_video`: codec/bitrate del ORIGINAL antiguo) queda
  desactualizada tras el cutover. NO es solo cosmética: el cliente la usa para decidir
  reproducción directa — es la causa del caso "222 sin encoded_video". El PASO 3 la
  neutraliza (siempre habrá copia H.264 que servir). NO corregirla vía
  `metadataExtraction` (tocaría fechas). Los archivos llevan EXIF re-incrustado (fecha/GPS).
