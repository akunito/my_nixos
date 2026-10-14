---
id: akunito.plans.docker-rootless-workstations
summary: Docker rootless por defecto en DESK y LAPTOP_X13 (modelo híbrido como NAS_PROD) — el daemon root queda solo para lo que no puede ir rootless y exige sudo; migración perezosa proyecto a proyecto con notas para que cualquier sesión adapte su stack
tags: [docker, rootless, security, desk, x13, workstation, krun, migration]
tickets: [AINF-407]
date: 2026-10-14
status: draft
related_files:
  - system/app/docker.nix
  - system/app/docker-rootless-maintenance.nix
  - system/security/docker-firewall.nix
  - profiles/work/configuration.nix
  - profiles/homelab/base.nix
  - profiles/DESK-config.nix
  - profiles/LAPTOP_X13-config.nix
  - lib/defaults.nix
  - docs/akunito/plans/rea-sandbox/README.md
---

# Docker rootless en DESK y X13

Decisión de Diego (2026-10-14): **rootless por defecto; root solo cuando no haya otra opción.** Motivo inmediato: el sandbox de REA (`rea-sandbox/README.md`). Motivo de fondo: hoy Docker en DESK corre como root (`dockerd` root, `/var/lib/docker`) y akunito está en el grupo `docker`, y estar en ese grupo equivale a ser root. Cualquier proceso de akunito (un `postinstall` de npm, un MCP, un agente) puede montar `/` en un contenedor.

## Estado actual (medido 2026-10-14 en DESK)

- `dockerEnable = true` (por defecto en `lib/defaults.nix:1405`) y `dockerRootlessEnable = false`. El daemon root viene de `profiles/work/configuration.nix:34` → `system/app/docker.nix`, con `userlandProxy = false` y `docker-firewall.nix` (cadena DOCKER-USER) protegiendo los puertos publicados.
- Contenedores: 2 `mcp/grafana` en marcha (MCP de sesiones de Claude abiertas) y 8 parados de leftyworkout/leftyworkout2 (postgres 17, redis, backend, frontend). 22 volúmenes (3,2 GB), 19 imágenes (9,1 GB), 5,9 GB de caché de build.
- Excepciones dockerFirewall en DESK: 3110/3111/3210/3211/6006/6007 por `tailscale0` (dev de leftyworkout y Storybook).
- Uso que necesita root de verdad: el meter de AION 2 capturó tráfico con `--net=host --pid=host --cap-add NET_RAW`. En rootless, `--net=host` es el namespace de rootlesskit, no las interfaces del host.
- X13: mismo `profiles/work/configuration.nix`, `dockerEnable = true` (`LAPTOP_X13-config.nix:421`). Estaba apagado; inventario pendiente.
- NAS_PROD ya funciona en híbrido (`dockerEnable` + `dockerRootlessEnable`, `profiles/homelab/base.nix:186`). Las lecciones aprendidas están en `system/app/docker-rootless-maintenance.nix` (`/etc/static` resistente al GC, prune semanal, recarga del user manager) y en las memorias de rootless (`index_nixos_repo.md`).

## Diseño

1. **Daemon rootless por defecto.**
   - `virtualisation.docker.rootless = { enable = true; setSocketVariable = true; … }` en los perfiles de estación de trabajo.
   - `DOCKER_HOST` apunta a `$XDG_RUNTIME_DIR/docker.sock`, así que `docker` y `docker compose` sin más usan rootless.
   - `daemon.settings`: `log-opts`, el límite de caché de BuildKit y **`"ip" = "127.0.0.1"`**, para que un `-p 5432:5432` publique por defecto solo en loopback.
   - **Sin `dns` forzado:** DESK y X13 tienen `resolvedEnable = false` y `/etc/resolv.conf` apunta a pfSense (192.168.8.1), que slirp alcanza. Copiar el `1.1.1.1` del NAS rompería el split-horizon dentro de los contenedores.
   - `docker-rootless-maintenance.nix` importado también aquí; se autoactiva con el flag.
     - `DISABLE_HOST_LOOPBACK` pasa a ser un flag por perfil: hoy está fijo a `false` (`:97`), y entonces cualquier contenedor rootless alcanza el `127.0.0.1` del host vía 10.0.2.2. En estaciones, `true`; si un stack necesita un servicio del host, se publica explícitamente.
     - El script de activación también arranca el `docker.service` del usuario, no solo los timers (`:139-143`). Si no, tras el deploy `docker` falla hasta volver a iniciar sesión.
   - `linger` activado, para que los stacks de dev no mueran al cerrar sesión.
   - Lo que trae nixpkgs: rootlesskit 2.3.6 y slirp4netns 1.3.5, sin pasta. El contenedor ve como IP de origen 127.0.0.1/10.0.2.100, no la real. La IP real y un `--net=host` de verdad llegan con RootlessKit 3.0 (Docker ≥ 29.5 upstream). Si un proyecto necesita la IP de origen, se usa `DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER=slirp4netns` solo para él.
2. **El daemon root se queda, pero hay que pedirlo.** Flag nuevo `dockerRootRequiresSudo` (por defecto `false`; DESK y X13 `true`):
   - akunito **sale del grupo `docker`**. Lo añade `docker.nix:85`; el flag lo condiciona allí.
   - sway-apps (`dockerctl.py:36`) usa `sudo -n docker` para el daemon root, y con askpass `sudo -n` falla. En estaciones, sway-apps gestiona solo el daemon rootless.
   - `enableOnBoot = false`: el daemon solo arranca por socket cuando se usa.
   - Se usa con `sudo docker …` (o un contexto `root` que también exige sudo). Claude puede usar sudo con el askpass gráfico; Diego aprueba cada uso.
   - `docker-firewall.nix` sigue protegiendo los puertos del daemon root.
3. **Cuándo está justificado root** (lista cerrada; ampliarla requiere decisión):
   - capturar tráfico de las interfaces del host (`--net=host` + `NET_RAW`/`NET_ADMIN`), como el meter;
   - contenedores que gestionan red o dispositivos del host (VPN, `NET_ADMIN`);
   - acceso a un dispositivo que no se puede delegar al usuario.

   **No** justifican root: puertos < 1024 (sysctl `net.ipv4.ip_unprivileged_port_start`), permisos de bind mounts (se arreglan), ni "antes funcionaba".
4. **Firewall en rootless.** Los puertos publicados los abre `rootlesskit` en el host y pasan por INPUT. Pero **el firewall de NixOS no basta en `tailscale0`**:
   - `ts-input -i tailscale0 -j ACCEPT` va antes que `nixos-fw`.
   - La guarda raw/PREROUTING de `docker-firewall.nix:136-139` lee el nat del daemon **root**; el de rootless vive dentro del netns de rootlesskit y no lo ve.

   Sin cambios, un Postgres de dev publicado en `0.0.0.0` quedaría abierto a toda la tailnet: portátiles de Aga, VPS, móvil.

   Por eso:
   - Bind por defecto en `127.0.0.1` (punto 1).
   - Los seis puertos de dev que hoy tienen excepción (3110/3111/3210/3211/6006/6007) se publican **explícitamente en la IP tailscale** de la máquina en el compose (`100.64.x.y:3110:3110`). La nota para sesiones lo explica.
   - Pruebas en R1: `nc` desde X13 **por tailscale** y desde la LAN contra un puerto publicado sin IP (debe fallar) y contra uno publicado en la IP tailscale (debe responder). También IPv6 (`[::]`).
5. **gVisor no funciona hoy sobre Docker rootless.** google/gvisor#12575 está abierto desde febrero de 2026 con Docker 29.x (`cannot read client sync file… EOF`). Solo arranca con `--ignore-cgroups --TESTONLY-unsafe-nonroot`, y **esa opción queda prohibida**. El arreglo (PR #14578) no está fusionado y nixpkgs trae `gvisor` 20260406.0, anterior.
   - Además, runsc habla siempre con el bus systemd del sistema (#11543), lo que obliga a `--ignore-cgroups` y anula los límites.
   - **Decisión: la segunda capa es `krun` (crun + libkrun):** cada contenedor en su propia microVM KVM, en rootless, con límites. Se registra en `rootless.daemon.settings.runtimes.krun.path = "${pkgs.crun}/bin/krun"`.
     - R1 prueba que el daemon rootless arranca un contenedor con `--runtime krun`: `uname -r` dentro ≠ host.
     - Si no, el plan B es Podman rootless solo para REA (ver el plan de REA).

## Migración: perezosa y sin cortar a nadie

- **Activar rootless no para el daemon root.** Los contenedores en marcha (los `mcp/grafana` de otras sesiones) siguen funcionando; `liveRestore` está activado. La salida del grupo `docker` solo cuenta desde el siguiente login, así que las sesiones abiertas no lo notan.
- El deploy se hace cuando Diego diga, después de commit y push, sin otro deploy en curso, con **`./install.sh ~/.dotfiles DESK -s -d`**. Sin `-d`, `handle_docker.sh` y `stop_external_drives.sh` paran todos los contenedores, incluidos los MCP de otras sesiones. Las sesiones nuevas cogen el `DOCKER_HOST` rootless.
- **No se migra todo de golpe.** Cada proyecto pasa a rootless la próxima vez que una sesión lo arranque, siguiendo la nota de abajo. Mientras tanto sus volúmenes siguen en el daemon root, que aún existe.
- Copia de volúmenes, por cada volumen (preserva los uid de dentro del contenedor, que rootless remapea bien):
  ```
  sudo docker run --rm -v VOL:/from alpine tar -C /from -cf - . | docker run --rm -i -v VOL:/to alpine tar -C /to -xpf -
  ```
- Cuando ningún proyecto dependa del daemon root: limpiar `/var/lib/docker` (imágenes y caché) con confirmación de Diego.

## Notas para otras sesiones

Se escriben **a mano en cuanto R1 esté desplegado y probado**, no antes; antes serían falsas. `~/.claude/CLAUDE.md` no lo genera Nix: es un fichero que sincroniza claude-sync.

- **`~/.claude/CLAUDE.md` (global, se carga en todos los proyectos y en las tres máquinas)**, sección corta "Docker en DESK/X13 es rootless", **condicionada a `ENV_PROFILE`** (DESK y LAPTOP_X13 tras R2). DESK_W11 y el VPS no cambian.
  - `docker` = rootless; root solo con `sudo docker` y solo en los casos de la lista cerrada.
  - Si un stack que antes iba en root falla al arrancar, adaptarlo antes de recurrir a root. Fallos típicos y su arreglo:
    - **Bind mount con `permission denied`:** el uid del contenedor no es akunito. Arreglo: `docker run --rm -v DIR:/d alpine chown -R <uid>:<gid> /d`, o `user:` en el compose.
    - **Volumen nombrado vacío:** sus datos siguen en el daemon root. Arreglo: copiarlo con la receta de arriba.
    - **Puerto < 1024:** usar uno ≥ 1024, o el sysctl.
    - **`--net=host` / `NET_ADMIN`:** no hay host real; si de verdad hace falta, pedir root a Diego.
    - **No responde desde la LAN o tailscale:** por defecto se publica en `127.0.0.1`. Publicarlo en la IP tailscale de forma explícita, nunca en `0.0.0.0`.
    - **La app ve 127.0.0.1 o 10.0.2.100 como IP del cliente:** es una limitación de rootlesskit 2.x.
    - **No alcanza un servicio del host por `localhost` o `host.docker.internal`:** el loopback del host está cerrado a propósito.
  - Al terminar, apuntar en la memoria del proyecto que ya corre rootless y qué hubo que cambiar.
- **Memoria de dotfiles:** `reference_docker_rootless_workstations.md` con los detalles y gotchas medidos; una línea en `index_nixos_repo.md`.

## Fases

**R1: DESK.**
1. Módulo y flags; corregir el comentario de `lib/defaults.nix:1406`, que dice "mutually exclusive" y no lo es (el NAS es híbrido).
2. Deploy.
3. Pruebas:
   - `docker info` muestra `rootless`;
   - `hello-world` y un compose con volumen;
   - un puerto publicado no es accesible desde la LAN y sí por `tailscale0` cuando está en la lista;
   - `docker` sin sudo no llega al daemon root;
   - `sudo docker ps` sí llega;
   - un contenedor no alcanza servicios en `127.0.0.1` del host;
   - `docker` funciona en una sesión nueva sin volver a iniciar sesión.
4. Notas globales y memoria.
5. Migrar leftyworkout (dev y dev2) como primer caso real, con su sesión o con Diego.

**Estado R1 (2026-10-14):** desplegado en DESK (`64cc7aab`) y probado.
- `docker info` muestra `rootless` con los runtimes `runc` y `krun`.
- Los contenedores root de otras sesiones sobrevivieron al deploy.
- Grupo `docker` vacío; se aplica en el próximo login.
- `-p` sin IP escucha solo en `127.0.0.1`, cerrado desde el NAS por la LAN y por tailscale. Con la IP de tailscale explícita, abierto.
- El loopback del host está bloqueado.
- **krun:** kernel del guest 6.12.91, sin red, montaje `:ro` legible y no escribible, `memory.max`/`pids.max` aplicados, VMM como uid 100999 con ~87 MB.
- Notas para otras sesiones escritas en `~/.claude/CLAUDE.md` y en la memoria `reference_docker_rootless_workstations.md`.

Pendiente de R1:
- Comprobar `sudo docker ps` y que `docker` sin sudo no llega al daemon root, tras el próximo login.
- Migrar leftyworkout (dev y dev2) la próxima vez que se use.

**R2: X13**, cuando esté encendido. Hoy no tiene `dockerFirewallEnable`, así que los puertos del daemon root van a la LAN, ni `virtualizationEnable` (sin qemu/kvm). Antes del deploy:
- inventario de contenedores y volúmenes;
- activar `dockerFirewallEnable` para el daemon root que queda;
- activar `virtualizationEnable` si X13 va a tener la microVM de REA.

Después, mismo deploy (`-s -d`) y mismas pruebas.

Disco: rootless guarda sus imágenes en `~/.local/share/docker` (overlay2 sobre btrfs, kernel 7.2.9). Mientras dure la migración, las imágenes estarán duplicadas (DESK: 9,1 GB más caché; `/home` tiene 426 GB libres).

**R3: ver si quedan dependencias del daemon root.** Si no queda ninguna, valorar quitarlo de las estaciones (solo con decisión de Diego).

Lo que no cambia: VPS_PROD, NAS_PROD, DESK_W11, LXC y Aga. Los módulos rootless de `homelab/base.nix` y `vps/base.nix` no se tocan. Si al hacer R1 sale un módulo compartido mejor, la deduplicación va en un commit aparte con su propia comprobación de evaluación de los perfiles afectados.
