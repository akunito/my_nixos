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
| Jugadores | 3 · whitelist: `Akunito`, `Snizzy_Chan` |
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

- **Desplegar a DESK_A** cuando esté comprobado en DESK, y limpiar allí las
  instancias que sobren.
- **Shader Eclipse**: copiado a mano desde `AkuCraft-HD` (all-rights-reserved,
  no se replica en nix). Es el único paso manual: `options.txt` sí es ya
  declarativo y la instancia nace con los keybinds, fov y audio correctos.
