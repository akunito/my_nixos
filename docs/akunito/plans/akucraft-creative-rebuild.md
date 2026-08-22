---
id: akunito.plans.akucraft-creative-rebuild
summary: The AkuCraft Creative server rebuilt from scratch on Solo's mod list, private to three players, plus per-machine gating of the FreesmLauncher instances
tags: [minecraft, akucraft, creative, terralith, vps]
related_files:
  - system/app/akucraft-bot.py
  - user/app/games/minecraft-client-mods.nix
  - scripts/sync-akucraft-automodpack.py
  - lib/defaults.nix
date: 2026-08-22
status: published
---

# AkuCraft Creative — reconstruido

El creativo se retiró el 2026-08-14 y vuelve el 2026-08-22 **regenerado por
completo**, sobre la lista de mods de Solo en vez de la que tenía. Comparte
casi todo el diseño con [Solo](akucraft-solo-hardcore.md); aquí sólo lo que
cambia.

| | |
|---|---|
| Dirección | `100.64.0.6:25566` (VPN requerida) |
| Contenedor · directorio | `minecraft-creative` · `~/.homelab/minecraft-creative` |
| Mods | **82** |
| Modo | creativo, `force-gamemode=true`, dificultad normal |
| Jugadores | 3 · whitelist **y op**: `Akunito`, `SnizzyChan` |
| Mapa web | ninguno · mapa **en juego** sí (Xaero, vía AutoModpack) |
| Fingerprint | `cc08a279cda108e22a6ff4bbf789ba09450c593bf9d1a34f3dc64df97968f733` |

## Qué cambia frente a Solo

**82 = los 78 de Solo + 4.** Hereda todos los recortes de Solo — colaboración,
IA/NPC, mapa web, red de seguridad ante la muerte — y en creativo la mitad de
eso además no tendría función: no se pierde nada y no hay escasez.

| Vuelve | Por qué aquí sí |
|---|---|
| `warputils` | `/tpa` y `/warp` **son** el transporte de un mundo de construcción compartido. En Solo se quitaron porque en hardcore el viaje de vuelta es la tensión |
| `explorers-compass` | En Solo mataba el descubrimiento; aquí es una herramienta para ir a ver una estructura |
| `multiworld` + `icommon` | Instalados **sin usarse**: hay un mundo. Están para poder añadir un segundo sin volver a tocar la lista |

`shadowborders` **no** está: sólo sirve para bordes *distintos* por mundo, y con
un mundo no hay nada que separar. Una línea cuando llegue el momento.

`force-gamemode=true` aquí, al revés que en Solo, donde devolvía al espectador
a survival y deshacía la muerte permanente.

## Dos cosas que casi se cuelan

**El `data/` viejo entero, no sólo el mundo.** Los jars de la lista de agosto
seguirían cargándose junto a los nuevos. Archivado como
`data-decommissioned-20260822`.

**El `.env` viejo pisaba cinco valores.** Seguía definiendo `MC_MEMORY=4G`,
`MC_DIFFICULTY=hard`, `MC_MAX_PLAYERS=10`, `MC_VIEW_DISTANCE=12` y
`MC_SIMULATION_DISTANCE=8`, y el compose los lee como `${VAR:-default}`: el
servidor habría arrancado con **10 jugadores y 4G** en vez de 3 y 6G. Ahora el
`.env` sólo lleva la contraseña de RCON y el compose es la única fuente de
verdad. El viejo está en `.env.bak-old-creative-20260822`.

## Spawn

`-16, 131, 1292`, en `terralith:cloud_forest`. Elegido por lo que hay **alrededor**,
no por el bioma en sí: a 96 bloques un `lush_valley` a y=164 — o sea 30+ bloques
de desnivel real, que es de donde salen las cascadas —, un río a 115, un
`blooming_valley` a 115 y `moonlight_valley` a 524. Bosque montañoso, exótico y
colorido, con valles, en un radio caminable.

La altura se midió, no se adivinó: al teleportar a y=190 el jugador cayó a
130,003, así que la superficie está en 130. `setworldspawn` quedó en 131.

## `SnizzyChan`, no `Snizzy_Chan`

La whitelist se creó con `Snizzy_Chan` y su launcher manda **`SnizzyChan`**. En
modo offline son **dos jugadores distintos**:

```
SnizzyChan   993e7eed-5b25-398f-99ce-6a5f358d3c02   <- lo que manda su cliente
Snizzy_Chan  e4116f9c-8175-3b02-8907-134509b06997
```

Se habría llevado un rechazo en el primer intento. El nombre bueno es el de
`~/.local/share/FreesmLauncher/accounts.json` en su máquina, que es la única
fuente de verdad de lo que el cliente envía.

`ops.json` se escribió **a mano** por lo mismo: `/op <nombre>` resuelve contra
Mojang igual que `whitelist add` y habría guardado el UUID *online* de un
desconocido. Ambos ficheros se escribieron con el servidor **parado**, porque
al apagarse los reescribe desde memoria y se habría comido la edición.

## Instancias por máquina

Cuatro perfiles activan FreeSM (DESK, DESK_A, LAPTOP_A, LAPTOP_X13) y hasta
ahora **todos recibían todas las instancias**, incluida una apuntando a un
mundo privado de un solo jugador en el escritorio de Aga.

Ahora `systemSettings.akucraftInstances` lo decide por máquina, con claves
(`prod`, `staging`, `solo`, `creative`) y no comprobando el hostname, que los
módulos aquí no pueden hacer:

| Máquina | Instancias |
|---|---|
| DESK | `prod`, `staging`, `solo`, `creative` |
| DESK_A | `creative` y nada más |
| LAPTOP_X13 · LAPTOP_A | `prod`, `staging` (el default) |

El default en `lib/defaults.nix` es el **par público**: un mundo privado se
opta explícitamente.

⚠️ El seeder sólo **crea**; no borra instancias que ya existan. Si DESK_A ya
tiene instancias de prod/staging de un sync anterior, seguirán ahí y hay que
quitarlas a mano.

## Pregeneración — pendiente

Sin lanzar, a propósito: se hará de noche.

```bash
docker exec minecraft-creative rcon-cli "chunky spawn"
docker exec minecraft-creative rcon-cli "chunky shape square"
docker exec minecraft-creative rcon-cli "chunky radius 2000"     # 16 km²
docker exec minecraft-creative rcon-cli "chunky quiet 60"
docker exec minecraft-creative rcon-cli "chunky start"
```

El temporizador de inactividad del bot ya no para un servidor con chunky
trabajando, así que puede correr toda la noche con nadie dentro.

## Pendiente

- ~~Desplegar a DESK_A~~ **hecho 2026-08-22**. `AkuCraft-CREATIVE-HD` sembrada
  y verificada contra la de DESK: shaderpacks, shader activo y Eclipse (751
  ficheros, 50 MB) idénticos; `options.txt` sólo difiere en las nubes y un
  keybind de MCA que su juego descartará al arrancar. `AutomaticJava=true`,
  igual que su instancia de prod que ya funciona.
  `AkuCraft-SOLO-HD` se borró de su máquina: nunca se abrió, no contenía nada
  suyo y apuntaba a un mundo privado al que no puede entrar. Siguen ahí
  `AkuCraft`, `AkuCraft-HD`, `AkuCraft-STAGING*` y su `1.21.1` de siempre —
  ninguna tiene datos de Xaero, pero se dejan por si quiere prod.
- **Pregeneración**: pendiente, para cuando acabe la de Solo (dos a la vez se
  comerían los 12 núcleos).
- **Shader Eclipse**: copiado a mano desde `AkuCraft-HD` (all-rights-reserved,
  no se replica en nix). Es el único paso manual: `options.txt` sí es ya
  declarativo y la instancia nace con los keybinds, fov y audio correctos.
