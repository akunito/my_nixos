---
id: akunito.plans.akucraft-solo-hardcore
summary: A private single-player hardcore AkuCraft server with Terralith as the Overworld, no web map, no collaboration or AI mods, and a manual world reset
tags: [minecraft, akucraft, hardcore, solo, terralith, vps]
related_files:
  - system/app/akucraft-bot.py
  - user/app/games/minecraft-client-mods.nix
  - scripts/sync-akucraft-automodpack.py
date: 2026-08-22
status: published
---

# AkuCraft Solo — hardcore, una vida

Un tercer servidor en VPS_PROD, junto a prod (`:25565`) y staging (`:25599`).
Superviviencia hardcore en solitario: exploración, inmersión y gráficos como
en prod, pero si mueres te quedas de espectador y el mundo se acabó.

| | |
|---|---|
| Dirección | `100.64.0.6:25567` (VPN requerida) |
| Contenedor · directorio | `minecraft-solo` · `~/.homelab/minecraft-solo` |
| Mods | **78** (Fabric 1.21.1) |
| Dificultad | `hardcore=true` → hard forzado, espectador permanente al morir |
| Jugadores | 2 (uno juega, el otro puede mirar en espectador) |
| Mapa web | ninguno, a propósito |
| Instancia cliente | `AkuCraft-SOLO-HD` (FreesmLauncher, vía AutoModpack) |

## Las cuatro decisiones que definen el servidor

### 1. Terralith ES el Overworld

En prod, Terralith vive en un mundo aparte (`multiworld`) detrás de un borde
propio (`shadowborders`) porque su Overworld es **anterior** a Terralith:
instalarlo reescribe la receta del ruido, y cualquier chunk generado después
choca con sus vecinos en una costura visible — se midió una pared de piedra de
~40 bloques en staging. Todo el plan del *frontier* (pregenerar hasta un límite
y luego vallarlo) existe para quitarle la oportunidad a esa costura.

En un mundo nuevo el problema no existe: el primer chunk ya se genera con la
receta de Terralith, así que no hay dos recetas que puedan chocar. Eso elimina
`multiworld`, `icommon` y `shadowborders`, y con ellos el mundo doble, los
bordes por mundo y el orden obligatorio de la pregeneración.

Verificado en el arranque: `terralith:temperate_highlands` a 131 bloques del
spawn, en `minecraft:overworld`.

### 2. Hardcore vanilla, reset a mano

`hardcore=true` ya hace todo lo que hace falta: dificultad hard forzada y
espectador permanente al morir, con el mundo intacto para volar por encima de
lo que perdiste. **No hay watcher, ni detección de muerte, ni reset
automático** — fue una decisión explícita, no una simplificación.

`FORCE_GAMEMODE` se queda **sin poner** y esto no es un descuido: con
`force-gamemode=true` el servidor devolvería al espectador a survival en cada
login, deshaciendo la muerte permanente en silencio.

Empezar de cero es `./newrun.sh`, a mano. Archiva `data/world` en
`runs/world-<fecha>/` — **nunca borra** — arranca un mundo nuevo y relanza la
pregeneración. Sin `SEED` en el compose, archivar el mundo *es* cambiar de
semilla: cada run se explora de cero sin configurar nada.

Dos trampas que el script ya cubre:

- `data/` pertenece a `100999` (remap de docker rootless), así que akunito no
  puede mover nada ahí desde el host. El `mv` va dentro de un contenedor
  alpine de usar y tirar.
- `config/chunky/tasks/` vive **fuera** de `world/`, así que la tarea de
  pregeneración anterior sobrevive al archivado. Con `continueOnRestart=true`,
  chunky la reanudaría contra el mundo nuevo usando el centro viejo. El script
  hace `chunky cancel` antes de definir la tarea nueva.

### 3. Sin colaboración, sin IA, sin red de seguridad

99 mods de staging − 22 + `chunky` = **78**.

| Motivo | Retirados |
|---|---|
| Colaboración | `system-teams`, `chat-plus`, `styled-chat`, `flan`, `universal-shops`, `warputils`, `luckperms`, `anti-xray` |
| Revivir | `hardcore-revival`, `balm` (existe sólo para él) |
| IA / NPC | `minecraft-comes-alive-reborn`, `secondbrain` |
| Mapa web | `surveyor` |
| Multimundo | `multiworld`, `icommon`, `shadowborders` |
| Muerte blanda | `universal-graves`, `ly-soulbound-enchantment`, `inventory-totem`, `collective` (única dependencia de éste) |
| Descubrimiento | `explorers-compass` |
| Mascotas | `respawnable-pets` |

Verificado leyendo el `fabric.mod.json` de los 100 jars de staging: **ningún
mod superviviente depende de ninguno de los 22**.

`inventory-totem` merece su propia línea. Hace que el tótem funcione desde
cualquier hueco del inventario; sin él vuelve la regla vanilla de llevarlo en
la mano, y con ella el intercambio *escudo o seguro de vida* en cada salida.
Ese intercambio es la tensión que justifica el modo.

Se quedan a propósito: la fauna y la variedad (`naturalist`, `hybrid-aquatic`,
`small-ships`, `doggy-talents-next`, `travelersbackpack`, `toms-storage`,
`storagedrawers`), el viaje rápido (`sswaystones`, 1 nivel por salto), y los
árboles de skills y la magia enteros.

### 4. Privado de verdad, no sólo silencioso

El bot tenía un flag `quiet` que suprime anuncios. **No basta.** `/status`
imprimía la dirección de cualquier servidor a cualquiera, `/ask` le daba al
modelo una línea del tipo *"Solo: UP. Online now: Akunito"*, y los
constructores de perfil leían inventario, estadísticas y claims de **todos**
los servidores para responder a cualquier jugador.

Por eso `quiet` ahora se acompaña de `private`, y una función `public_servers()`
que usan todas las rutas de lectura que pueden llegar a un jugador: `/status`,
`/players`, el contexto de `/ask` y los tres lectores de perfil. `monitor()`,
`tail_logs()`, `STATES` y `pick_targets()` siguen viendo todos los servidores,
porque el temporizador de inactividad y `/start solo` los necesitan.

De paso, un `/start` o `/stop` a secas ya no toca los servidores `admin_only`
aunque quien escriba sea MCadmin. Con dos servidores era inofensivo; con solo,
un `/stop` distraído mataría una run hardcore en marcha.

## Pregeneración

`chunky`, cuadrado de radio 2000 centrado en el spawn real (`/chunky spawn`,
no `0,0`: el spawn de un mundo nuevo cae cerca del origen pero no encima).

```
radio 2000 (square) → 4x4 km → 16 km² → 62.500 chunks
```

Dimensionado con la tarea real de prod (`radius=12000`, 2.252.950 chunks,
28 GB, 13,5 h) ≈ 48 MB/km². Salen ~780 MB y algo más de una hora, más lento que
el cálculo a papel porque el contenedor lleva `cpus: "6"`: la VPS tiene 12
núcleos compartidos con Immich, Plane y Nextcloud, y el pregen de prod se puso
al 670%. Sólo el Overworld — en el Nether viajas a 8x y `amplified-nether` es
caro por chunk.

## Operación

```bash
cd ~/.homelab/minecraft-solo
docker compose up -d                            # o /start solo en Discord
docker exec minecraft-solo rcon-cli list
docker exec minecraft-solo rcon-cli 'chunky progress'
./newrun.sh                                     # archivar y empezar otra vez
```

Tras cambiar la lista de mods:

```bash
./scripts/sync-akucraft-automodpack.py --target solo
ssh -A -p 56777 akunito@100.64.0.6 \
  'export DOCKER_HOST=unix:///run/user/1000/docker.sock; docker restart minecraft-solo'
```

El allow-list de AutoModpack es `jars del servidor ∩ set del cliente en nix`,
así que los 22 mods que solo no tiene sencillamente no aparecen y `chunky`
—server-side, sin entradas de registro— cae en el montón de retenidos donde
debe. **No lo "arregles"** metiendo una lista por target: esa derivación es
justo lo que evita el drift que expulsó a todos los clientes en 2026-08-19.

## Quién puede entrar

Tres capas, y la tercera es la que hace que las otras dos den igual.

**Headscale** confina `tag:mc-guest` a `100.64.0.6:25565,8100` — el puerto de
prod y la descarga del modpack. Un invitado **no alcanza el 25567**
(verificado 2026-08-22 en `headscale policy get`). `group:family` llega más
lejos.

**Modo offline**: la identidad sale del nombre, así que cualquiera que alcance
el puerto puede presentarse como quiera. La red por sí sola no basta.

**Whitelist**, que es lo que cierra el tema sin depender del ACL:
`white-list=true` y `enforce-whitelist=true`, con un `data/whitelist.json`
escrito **a mano**:

```json
[{ "uuid": "df728f8f-fa67-3b17-ab96-e1e49d70aee7", "name": "Akunito" }]
```

Ese UUID es el **offline** — `md5("OfflinePlayer:Akunito")` con los bits de
versión y variante puestos, comprobado contra el usercache de prod. La
variable `WHITELIST` de la imagen se queda **sin poner** a propósito: resuelve
el nombre contra Mojang y guardaría el UUID *online* de un desconocido. Y los
nombres distinguen mayúsculas: `akunito` en minúsculas es otro jugador
(`1b831a7b-…`).

Para abrirlo a alguien, añade su UUID offline al fichero y
`docker exec minecraft-solo rcon-cli whitelist reload`. Para desactivarlo,
`ENABLE_WHITELIST: "FALSE"` en el compose.

## AutoModpack — el fingerprint

```
53a00e48a80fcce55eff674aa24391497d54b4967585ef9ac199a83ac14006a7
```

Es lo que el cliente pide confirmar la primera vez que se conecta. Comprobado
por dos vías: lo que imprime el server al arrancar
(`docker logs minecraft-solo | grep -i "Certificate fingerprint"`) y el
SHA-256 del certificado
(`docker exec minecraft-solo cat /data/automodpack/.private/cert.crt | openssl x509 -outform DER | sha256sum`).

`addressToSend` se fijó a `100.64.0.6` (con `portToSend: -1`, así que conserva
su propio puerto), igual que prod y staging desde 2026-08-19. `knownHosts` se
indexa **sólo por hostname**, sin puerto, así que con el campo vacío la clave
dependía de lo que tecleara el cliente. Hoy no cambiaba nada —
`AkuCraft-SOLO-HD` sólo habla con este server y su `servers.dat` lleva la IP
cruda— pero deja de ser cierto en cuanto alguien use el nombre amigable.

Prod imprime `73b00f4d…0034fd` y staging `c4d8172c…b2d539`: son tres
certificados distintos, y por eso cada servidor necesita su propia instancia.

## Pendiente

- **Shader Eclipse**: la instancia nueva nace con Complementary, que es el
  `hdShaderDefault` en nix. Eclipse está instalado a mano (licencia
  all-rights-reserved, no se replica), así que hay que copiarlo a
  `AkuCraft-SOLO-HD/minecraft/shaderpacks/` si lo quieres ahí.
- **Backups**: `~/.homelab/minecraft-solo` debería quedar **excluido** de
  restic. El mundo está para perderse, y `runs/` acumula los cadáveres.
