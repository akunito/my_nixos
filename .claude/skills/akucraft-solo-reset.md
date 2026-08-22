---
name: akucraft-solo-reset
description: Restart the AkuCraft Solo hardcore run after a death — restores the map from a master copy instead of regenerating it, moves the spawn ~500 m, and verifies the new spawn cannot kill you on arrival.
---

# AkuCraft Solo — empezar otra vez tras morir

Hardcore: al morir te quedas de espectador y el mundo se queda como está. Esto
es el botón de empezar de nuevo. **No hay automatismo** — se ejecuta a mano,
fue una decisión explícita.

## El comando

```bash
ssh -A -p 56777 akunito@100.64.0.6 'cd ~/.homelab/minecraft-solo && ./reset-run.sh --yes'
```

Tarda menos de dos minutos. Opciones: `--radio 800` si a 500 m no encuentra
sitio seguro; sin `--yes` pregunta antes.

## Qué hace, y por qué así

**Restaura el mapa desde un maestro, no lo regenera.** Es lo que convierte
cuarenta minutos en segundos. `master/master.tgz` es una copia intacta del
mapa (semilla `1020210412285842058`) **con sus 16 km² ya generados**, sacada
del servidor creativo antes de que nadie construyera nada. Sin esto, cada run
nueva empieza con tirones de generación en cuanto te alejas del spawn.

**Devuelve el mundo a hardcore.** El maestro viene del creativo, así que su
`level.dat` trae `hardcore=0`, `GameType=1` y `Difficulty=2`. Esas tres
banderas viven **en el mundo, no en `server.properties`**, y en un mundo ya
creado mandan sobre él: sin corregirlas, la run nueva no sería hardcore. Se
editan como bytes en sitio, sin cambiar la longitud del fichero.

⚠️ `Difficulty` aparece **dos veces** en `level.dat`, porque también existe
`DifficultyLocked`. El script aborta si una búsqueda no da exactamente una
coincidencia, en vez de escribir a ciegas.

**Mueve el spawn ~500 m** del anterior, en uno de ocho rumbos **en orden
aleatorio**, para que dos muertes seguidas no te manden al mismo sitio.

**Comprueba que el spawn no te mate al llegar.** Esto es lo que más cuesta
acertar:

- La altura del terreno se **mide**, no se estima: `forceload` del chunk,
  soltar un `armor_stand` desde y=250 y leer su `Pos` al posarse. Sin el
  forceload el chunk no tickea y la entidad nunca cae.
- Ni agua ni lava a la altura de los pies, el cuerpo **ni la cabeza**. Lo
  tercero importa: una sonda se hunde hasta el fondo de un lago y aterriza
  sobre arena, así que el suelo puede parecer bueno estando bajo el agua.
- Se descarta cualquier punto por debajo del nivel del mar (y < 63).
- **No** se exige `minecraft:air` donde vas a estar de pie. Fue el primer
  intento y rechazaba todos los valles floridos, porque la hierba alta y la
  lavanda ocupan el bloque sin estorbar. Si la sonda se posó ahí, cabes.

**Archiva, nunca borra.** El mundo que muere va a `runs/world-<fecha>/` con un
`.txt` al lado que anota semilla, días sobrevividos, causa de muerte y el
spawn que tenía. Poda a mano cuando ocupe.

## Comprobar el resultado

El script imprime la verificación final; tiene que verse así:

```
y=74   sólido
y=75   air
y=76   air
```

Suelo sólido con dos bloques de aire encima. Si sale `water` o `lava` en
cualquier línea, **no entres** y vuelve a lanzarlo con otro radio.

## Si algo falla

| Síntoma | Qué pasa |
|---|---|
| `ningún rumbo seguro a 500 m` | Vuelve a lanzarlo con `--radio 800`. El mundo viejo ya está archivado y el nuevo restaurado; sólo falta el spawn. |
| `ABORTO: Difficulty -> 2` | La estructura de `level.dat` cambió. No lo fuerces: revisa a mano antes. |
| `no llegó a healthy` | `docker compose logs -f` en `~/.homelab/minecraft-solo`. |
| El mundo no se restaura | Se aborta dejando el viejo en `runs/`. Nada se pierde. |

## Ficheros

| | |
|---|---|
| `~/.homelab/minecraft-solo/reset-run.sh` | el reset completo |
| `~/.homelab/minecraft-solo/find-safe-spawn.sh` | el buscador de spawn seguro (reutilizable en otros servidores) |
| `~/.homelab/minecraft-solo/master/master.tgz` | el mapa maestro, 606 MB |
| `.../gameservers/akucraft-master-map/` (NAS) | copia durable del mismo maestro |
| `runs/` | mundos de runs anteriores |

Diseño completo del servidor: `docs/akunito/plans/akucraft-solo-hardcore.md`.
