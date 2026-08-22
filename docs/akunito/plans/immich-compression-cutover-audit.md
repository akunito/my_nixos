---
title: Immich compression — CUTOVER audit (review before executing)
status: SUPERSEDED — audit done 2026-08-19 (v1 script deleted originals instead of archiving); execute via immich-compression-cutover-runbook.md (script v2)
date: 2026-08-19
host: VPS_PROD (100.64.0.6)
---

# Immich compression — auditoría del CUTOVER

Documento para revisar ANTES de tocar producción. Aquí está exactamente qué se
ejecuta, sobre qué archivos y filas de base de datos, y cómo revertir en cada punto.

---

## 0. Estado actual (ya hecho, NADA de esto tocó prod)

- **Clon paralelo** `immich-dev` (contenedores `immich_dev_*`, puerto 2284,
  `pictures-dev.local.akunito.com`) con TODA la biblioteca clonada y **comprimida**:
  - 33,853 fotos JPEG → **AVIF** (calidad 85, resolución completa preservada)
  - 805 vídeos → **AV1** (los que encogían; 1,290 se saltaron por no mejorar)
  - 1,024 PNG → **oxipng** (sin pérdida)
  - Metadatos EXIF (fecha/GPS) **re-incrustados** desde los originales de prod.
- **Prod (`immich`, puerto 2283) INTACTO.** 38,891 assets, fechas y álbumes originales.
- Ahorro medido en el clon: originales 74 GB → ~56 GB. Con streams 720p: total ~121 GB → ~83 GB (**~38 GB**).

## 1. Modelo: "aplicar sobre prod, prod manda" (Approach 2)

NO promovemos el clon (perderíamos las 25 fotos subidas a prod desde el 13-ago y
alteraríamos fechas). En su lugar: **la base de datos de PROD sigue siendo la
fuente de la verdad**; solo sustituimos los archivos por sus versiones comprimidas
y actualizamos 4 campos por asset. Consecuencias:
- Las **25 fotos nuevas** de prod NO se tocan (no están en el mapa).
- Las **fechas de prod NO se tocan** (NO se ejecuta `metadataExtraction` en prod —
  eso re-derivaría fechas y desplazaría ~197, mayormente 1h de zona horaria).

## 2. Qué modifica EXACTAMENTE (por cada uno de los 35,682 assets re-codificados)

El script `~/.homelab/immich-dev/cutover.sh` usa el mapa `cutover_map.tsv`
(35,682 líneas: `id | ruta_original | ruta_nueva | nombre_nuevo | sha1 | tamaño`).

**Operación de archivo** (`place_one`), con inmich PARADO:
1. **Mueve el ORIGINAL a un archivo** (no lo borra):
   `mv /home/akunito/immich-library/<orig> → /home/akunito/immich-preclone-originals/<orig>`
2. **Coloca el archivo COMPRIMIDO** en la ruta nueva (hardlink desde el clon; mismo
   disco → instantáneo, sin gastar espacio): `ln immich-dev-library/<comprimido> → immich-library/<comprimido>`

**Operación de base de datos** (`apply_db`, en UNA transacción):
```sql
BEGIN;
-- carga el mapa en una tabla temporal _cut(id,path,name,sha,sz)
UPDATE asset a SET "originalPath"=c.path, "originalFileName"=c.name,
       checksum=decode(c.sha,'hex')  FROM _cut c WHERE a.id=c.id;
UPDATE asset_exif e SET "fileSizeInByte"=c.sz FROM _cut c WHERE e."assetId"=c.id;
COMMIT;
```
**NO se toca**: fechas (`dateTimeOriginal`, `localDateTime`), álbumes, caras,
favoritos, GPS, ni ningún otro campo. Solo esos 4: ruta, nombre, checksum, tamaño.

> Fotos JPEG→AVIF cambian de extensión (.jpg→.avif) ⇒ se actualiza ruta+nombre.
> Vídeos/PNG mantienen extensión ⇒ ruta/nombre iguales, solo cambia checksum+tamaño.

## 3. Redes de rescate (TRIPLE) y cómo revertir

| Red | Qué es | Dónde |
|-----|--------|-------|
| **Originales archivados** | Todos los originales, movidos (no borrados) | `~/immich-preclone-originals/` |
| **Volcado de la DB** | `pg_dump` de prod justo antes | `~/immich-precutover-db-20260819-1114.sql.gz` (218 MB) |
| **Backup NAS** | Snapshot restic completo (biblioteca + DB) | `immich.restic` 2026-08-16 (cubre TODO lo que se modifica) |

**Revertir (si algo va mal):**
1. Parar inmich: `docker stop immich_server`
2. Restaurar DB: `gunzip -c ~/immich-precutover-db-*.sql.gz | docker exec -i immich_postgres psql -U postgres -d immich` (tras `DROP/CREATE` de la DB) — o simplemente el `UPDATE` inverso desde el volcado.
3. Devolver originales: `mv ~/immich-preclone-originals/* → ~/immich-library/` y borrar los `.avif` colocados.
4. Arrancar inmich. Estado idéntico al de ahora.

Nada se borra hasta la LIMPIEZA final (paso 6), que solo se hace tras tu visto bueno.

## 4. Reproducción de vídeo (por qué funcionará)

- La app de Immich reproduce los vídeos vía la **copia de streaming** (`encoded-video`),
  no el original. Prod YA tiene esas copias (H.264) que funcionan hoy.
- Tras el cutover, esas copias existentes **siguen sirviendo** (mismo contenido) ⇒
  los vídeos se reproducen en la app igual que ahora.
- El navegador del móvil NO reproduce (limitación de Immich, afecta también a prod hoy)
  — la app sí. Verificado: prod-app ✓, prod-navegador-móvil ✗, dev-navegador-móvil ✗.

## 5. Secuencia de ejecución (con puertas de verificación)

```
# PASO 1 — prueba de 3 assets (inmich ARRIBA, reversible)
ssh ... 'cd ~/.homelab/immich-dev && bash cutover.sh test 3'
#   → verifico archivos + DB de esos 3. Si OK ↓

# PASO 2 — cutover completo (inmich PARADO ~minutos)
ssh ... 'docker stop immich_server'
ssh ... 'cd ~/.homelab/immich-dev && bash cutover.sh place-all'   # archiva + coloca + UPDATE DB
ssh ... 'docker start immich_server'
#   → verifico: cuentas, un asset servido, salud. Tú lo confirmas en la APP.

# PASO 3 — (opcional, ahorro extra ~20 GB) streams a 720p en prod
#   Ajustar en prod: Admin→Video Transcoding→720p + maxBitrate 2000k, y lanzar
#   Video Conversion=All. (Requiere tu sesión admin de prod, o token.)

# PASO 4 — LIMPIEZA (solo tras días de confianza) → LIBERA EL ESPACIO
ssh ... 'rm -rf ~/immich-preclone-originals'     # borra originales archivados (~74 GB)
ssh ... 'docker compose -p immich-dev down && rm -rf ~/immich-dev-library'  # tira el clon
#   + borrar álbumes de muestra, vhost pictures-dev, DNS. (~38 GB netos liberados)
```

**El espacio NO se libera hasta el PASO 4.** Durante el cutover el disco no crece
(hardlinks); los originales siguen en disco (archivados) hasta que confirmes.

## 6. Downtime

Solo el PASO 2: inmich_server parado los minutos que tardan las operaciones de
archivo (hardlinks, instantáneos) + el UPDATE de DB (una transacción, segundos).
Estimado **< 5 min**. El resto (fotos, álbumes) intacto.

## 7. Riesgos conocidos y mitigación

| Riesgo | Mitigación |
|--------|-----------|
| Bug en rutas del script borra/pierde un original | Los originales se MUEVEN (no borran) → recuperables. + volcado DB + backup NAS. |
| UPDATE de DB incorrecto | Transacción (todo o nada) + volcado DB previo para revertir. |
| Vídeo no reproduce en la app | Copias de streaming existentes se mantienen; ya funcionan hoy en la app. |
| NAS dormida (backup fresco falló) | Backup del 16-ago cubre TODO lo modificado (esos assets ya existían). |
| `metadataExtraction` accidental desplaza fechas | NO se ejecuta en prod. Los archivos ya llevan EXIF re-incrustado por si acaso. |

## 8. Ahorro esperado
- Inmediato tras cutover+limpieza (sin 720p): **~18 GB** (originales AVIF+AV1 más pequeños).
- Con streams 720p (paso 3): **~38 GB** total (121 GB → ~83 GB).

---
**Estado: esperando tu auditoría. No se ha ejecutado nada destructivo.**
Scripts en el VPS: `~/.homelab/immich-dev/{cutover.sh, cutover_map.tsv}`.
