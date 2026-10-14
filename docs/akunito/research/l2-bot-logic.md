---
id: akunito.research.l2-bot-logic
summary: Lógica de bots/asistentes de Lineage 2 open-source (árbol de combate, triage de heal/buff/recharge para soporte Elven Elder, gestión HP/MP/CP/pociones, targeting, retorno a pueblo) y protocolo/cifrado de red L2 (login Blowfish estático→dinámico + RSA, juego XOR dinámico con clave en el primer paquete y contador que avanza) para construir el asistente RPA del plan l2-rpa-testbed; cada afirmación citada al repo+fichero y marcada MEDIDO/INFERIDO
tags: [l2, lineage2, interlude, highfive, rpa, bot, healer, protocol, crypto, blowfish, xor, opcodes, packets, research]
tickets: [AINF-416]
date: 2026-10-14
status: draft
related_files:
  - docs/akunito/plans/l2-rpa-testbed.md
---

# L2 bot/assistant logic + network protocol/crypto (fase L-study)

Investigación para el plan `docs/akunito/plans/l2-rpa-testbed.md` (AINF-416). Objetivo: extraer la lógica de combate/soporte reutilizable y el protocolo/cifrado de L2 para (a) un asesor/copiloto de clase **soporte (Elven Elder)** y (b) un lector **pasivo** del propio tráfico. Cada hecho cita repo+fichero; `MEDIDO` = leído del código, `INFERIDO` = deducido. Leído con WebFetch (sin clonar). Nota: el summariser de WebFetch recorta el literal a ~125 chars, así que las constantes largas son fieles pero no byte-a-byte salvo donde se marca exacto.

## Fuentes y qué es cada una

| Repo | Lang / licencia | Chronicle | Rol | Sirve para |
|---|---|---|---|---|
| `Elfocrash/L2jRoboto` (branch `master`) | Java / **MIT** | Interlude/HighFive skill IDs | fake-players lado servidor (aCis) | lógica de combate/heal/buff reutilizable **literal** |
| `EligiusSantori/L2Apf` | Scheme-Racket / GPL-3.0 | C4 | artificial-player sobre protocolo | **mejor** modelo mundo↔comportamiento y triage de heal |
| `L2-Net/L2Net` | C# / GPL-2.0 | — | asistente a nivel paquete + scripting | tablas de reglas y taxonomía de triggers |
| `ellysh/l2bot` | AutoIt / GPL-3.0 | — | bot por pixel+hotkey | sensado por pantalla y heal por click de UI |
| `fobus1289/l2js-hf-client` (= npm `l2js-client`) | TS | **HighFive (267-273)** | cliente | login + cifrado + tabla de opcodes (lo más completo) |
| `MrTREX/lineage2ts` (gitea.com, `master`) | TS+Zig | **Interlude 746** | servidor | cross-check del cifrado de juego 746 |
| `gigabelka/l2ts-interlude-client-l2jmobius` | TS | Interlude 746 | cliente | **INACCESIBLE** (404 en todo, incl. API GitHub) |

GPL solo para aprender la lógica. **Solo L2jRoboto (MIT) es copiable literal** en nuestro repo (ver §3).

---

## 1. Lógica de combate y asistencia

### 1.1 L2jRoboto — árbol de combate server-side (MIT, lo más concreto)

Código en `src/com/elfocrash/roboto/`. Cada clase activa hereda `ai/CombatAI.java` (que hereda `ai/FakePlayerAI.java`); el task manager del servidor llama `thinkAndAct()` por tick.

**Orden del tick de combate** (MEDIDO, `ai/SoultakerAI.thinkAndAct()` y la base): `super.thinkAndAct()`→`handleDeath()` → `setBusyThinking(true)` (guard de reentrada) → `applyDefaultBuffs()` → `handleConsumable()` (si `IConsumableSpender`) → `handleShots()` → `tryTargetRandomCreatureByTypeInRadius(Monster.class, 2000)` → `tryAttackingUsing{Mage|Fighter}OffensiveSkill()` → `setBusyThinking(false)`. Fighter/archer insertan `selfSupportBuffs()` antes del targeting.

**Selección de skill** (MEDIDO, `CombatAI.java`): lista ordenada ASC por `getPriority()`, se recorre y se coge el **primero** que pasa `_fakePlayer.checkUseMagicConditions(skill,true,false)` (gate de MP/cooldown/castabilidad, que es **código del core aCis, NO del mod** → cualquier reuso debe reimplementar MP/reuse). Rango/LOS vía `GeoEngine.canSeeTarget`; si bloqueado se mueve 100 y devuelve null ese tick. Fighters: `forceAutoAttack` siempre y skill solo si `Rnd.nextDouble() < changeOfUsingSkill()` (base 1.0; `DuelistAI` 0.5; `SaggitariusAI` 0.15).

**BUG MEDIDO reutilizable-con-cuidado**: `model/BotSkill.java` ctor de 4 args **nunca asigna `_priority`** → `getPriority()` devuelve 0 para todas; como `Collections.sort` es estable, el orden real = orden de `.add()`. Las prioridades numéricas de cada clase son cosméticas. Si copiamos esta lógica, arreglar el ctor o tratar el orden de lista como prioridad.

### 1.2 L2jRoboto — HEALER (CardinalAI + IHealer) — núcleo para Elven Elder

**Tick del healer** (MEDIDO, `ai/CardinalAI.thinkAndAct()`): `super` → `applyDefaultBuffs()` → `handleShots()` → `tryTargetingLowestHpTargetInRadius(self, FakePlayer.class, 2000)` → `tryHealingTarget(self)`.

A quién curar (MEDIDO, `ai/addon/IHealer.tryTargetingLowestHpTargetInRadius`): solo si `getTarget()==null`; pool = creatures vivas de la clase en radio 2000, **incluye a sí mismo**; elige **HP absoluto más bajo** (NO %, `Double.compare(getCurrentHp(...))`); no comprueba pertenencia a party, se basa en tipo+radio. Decisión de heal (MEDIDO, `IHealer.tryHealingTarget`): `switch(skill.getCondition())` **solo implementa `LESSHPPERCENT`** (el resto no-op); `hp% = Math.round(100.0/maxHp*currentHp)`; castea si `hp% <= conditionValue`. Spells (MEDIDO, `CardinalAI.getHealingSpells`): `HealingSpell(1218,…,70,1)` y `HealingSpell(1217,…,80,3)` → skill 1218 (Greater Heal) cuando HP%≤70, 1217 (Heal) cuando HP%≤80, ambos `TARGET_ONE`.

**Buffs** (MEDIDO, `FakePlayerAI.applyDefaultBuffs`): cada tick, por cada buff de `getBuffs()`, aplica si falta o **refresca cuando quedan ≤20 unidades de tiempo** (así se rastrea presencia+timer en la effect list). **Solo auto-buffs**, NO buff a party. `CardinalAI.getBuffs()` = `FakeHelpers.getMageBuffs()` (20 buffs, IDs en `helpers/FakeHelpers.java`).

**AUSENTE en L2jRoboto** (MEDIDO por búsqueda): gestión de MP, recharge, pociones HP/MP/CP, resurrect de aliados, buff a party, targeting por aggro, unstuck. El único "potion/MP" es que el core rechaza el cast sin MP. → todo eso lo añadimos nosotros para el Elven Elder.

**Self-support fighter** (MEDIDO, `CombatAI.selfSupportBuffs`): `LESSHPPERCENT` por HP%; `MISSINGCP` castea si `maxCP-currentCP >= value` (p.ej. `DuelistAI` skill 440 con MISSINGCP≥1000); `NONE` siempre.

### 1.3 L2Apf — triage de soporte (la mejor referencia de diseño para el healer)

`program/support.scm` (MEDIDO) — tunables verbatim: `hp-steady=9/10` (herido), `hp-danger=1/5` (emergencia→battle-heal), `mp-steady=2/3` (necesita recharge), `mp-reserve=1/3` (mi MP debe estar ENCIMA antes de rechargear a otros), `economy=1/3` (techo: no gastar en daño leve), `resurrect?=#f`, `distance=1000`. Handler `check-and-treat` dispara en eventos `creature-update`/`change-target`/`skill-*`/`die`/party-join-leave; **no hace nada mientras `casting?`**; prioridad estricta (cada paso solo si el anterior no actuó):
1. **Heal HP**: heridos (corte hp-steady/hp-danger) ordenados por hp-ratio asc luego object-id; si ratio≤hp-danger → battle-heal urgente→heal simple; si >2 heridos y group-heal listo → group heal; si no, heal simple.
2. **Recharge MP**: solo si mi mp-ratio>mp-reserve; miembros con mp-ratio≤mp-steady, salta a clases de soporte.
3. **Resurrect** (si habilitado): mass-res si >1 muerto, si no single.
4. **Standby**: si estoy de pie y mp-ratio<97/100 → sentarse a regenerar.
`do-treatment`: sentar si de pie → targetear miembro → usar skill.

`program/bless.scm` (MEDIDO, buffs): NO comprueba si el buff está activo; usa un **min-heap por `last-usage+reuse-delay`** (cooldown, no duración restante) y castea cuando `now>=ready`; eventos de skill mantienen la cola. L2Apf rastrea "timers" de buff como pura matemática de cooldown.

`program/slay.scm` (MEDIDO, ataque): **sin umbrales de HP**; recorre skills en orden y usa `skill-ready? && me.mp>=skill.mp-cost && predicado-del-skill`; `attack` básico solo si `not (attacking? me)`.

### 1.4 L2Apf — modelo de mundo (patrón world-model vs behavior)

`model/world.scm` (MEDIDO): un struct mutable; **todos los objetos en UNA hash table** `objects` keyed por object-id (no hay colecciones separadas por tipo, se consulta con predicado). Campos: `objects me inventory shortcuts skills quests party clans alliances`. Accessors: `near` (radio), `object-ref`, `find-character`, `find-skill`, `get-target`/`get-angle`/`get-destination`, `get-weapon`/`get-shield`, `party-*`. Tipos componibles como LISTA de símbolos (object⊂creature⊂character); `object-of-type?` comprueba pertenencia.
- `model/creature.scm`: `level name title target-id hp mp max-hp max-mp sitting? walking? in-combat? alike-dead?(muerte) bleeding? poisoned? stunned? sleeping? silenced? rooted? paralyzed? burning? casting angle position destination run-speed …` + helpers `hp-ratio`/`mp-ratio`. target es `target-id`, no ref.
- `model/character.scm` añade `cp max-cp karma race gender class-id pvp? clan-id ally-id …`.
- `model/skill.scm`: `id level active? enabled? last-usage reuse-delay mp-cost hp-cost item-id …`; `skill-ready? = active? && now > last-usage+reuse-delay` (tiempo restante implícito, no se almacena).
- `model/party.scm`: lista inmutable `(loot-mode leader-id member-ids…)`.
Separación limpia (MEDIDO, dirs): `packet/game/server/*` parsea estado y **escribe el modelo**; `api/*` emite paquetes de acción; `program/*` decide reaccionando a eventos.

### 1.5 L2Net — tablas de reglas y taxonomía de triggers

`Code/Logic/BotAIThread.cs` `BotAI()` (MEDIDO, orden): `DoItems()` (pociones: HP si `Cur_HP/Max_HP < Min_Per/100`, igual MP/CP) → `DoBuffsPart1/2()` → pickup → spoil → `RestBelow()` (si `Cur_HP<RestBelowHealth`) → stuck/move/follow/target → `DoCombat()` (por cada `CombatTargets`: activo + tick + `Cur_MP>=Min_MP` + `hp_per<=Min_Per/100` → `Use_ShortCut`; **esta es la vía de auto-heal**: heals como CombatTargets keyed en HP%) → `Attack()`. **Ningún umbral hardcodeado**: todo viene de config de usuario (`Min_Per`, `Min_MP`, `RestBelowHealth`).

Buff-timer (MEDIDO, `CharBuffTimer.cs`): solo guarda `LastTickTime` (ticks absolutos), NO cuenta atrás; expiry `if LastTickTime < now - TickDuration` → recast. Backoff de cast fallido: `Add_Time(id, FAILED_BUFF)`.

**Taxonomía de triggers reutilizable** (MEDIDO, `BuffTriggers:byte`): `Always=0, CP=1, HP=2, MP=3, Dead=4, Charges=5, Souls=6, DeathPenalty=7, AB_Bleeding=8, AB_Poison=9, AB_Ice=10, AB_Wind=11, AB_Fear=12, AB_Stun=13, AB_Sleep=14, AB_Muted=15, AB_Root=16, AB_Paralysis=17, AB_Petrified=18, AB_Invulnerable=19`. Mapea limpio a deberes de healer: heal (HP), recharge (MP), cleanse (AB_*), rez (Dead), buff (Always). Scripting `.l2s` (MEDIDO): lenguaje imperativo con `GET_NPCS/PLAYERS/PARTY/EFFECTS/SKILLS` que leen estado a listas tipadas, targeting/acciones y hasta `BLOCK`/`INJECT` de paquetes.

### 1.6 l2bot — sensado por pixel + heal por click (para RPA sin leer memoria)

`tactics/support.au3` (MEDIDO): loop `FollowLider(); SearchTarget(); Attack()`. Sensado de barras (MEDIDO, `source/functions.au3 GetBarValue`): `% = (x_borde_color - x_izq)/(x_der - x_izq)*100` con `PixelSearch` tolerancia 4; clamp de cordura (rechaza <-10 o >110 = lectura fallida). Umbrales hardcodeados (MEDIDO, `run/healer.au3`): `$kBarHalf=50`, `$kBarThird=30`, `$kPartyHealthMin=80` → HP<50%→HP pot, MP<30%→MP pot, miembro<80%→heal. Heal a party (MEDIDO): click en el slot de la ventana de party para targetear + pulsar hotkey de heal (`$kHealKey={F2}`). Buffs por **intervalo fijo** (MEDIDO, `$kTimeouts="10,20"` min), sin detección de presencia. Targeting por color (`$kTargetColors`) excluyendo la propia región de pantalla. Input por driver raw (`tools/InpOut32`) para parecer hardware.

### 1.7 Patrones reutilizables → asistente/copiloto Elven Elder

- **Modelo mundo↔comportamiento** (L2Apf): una verdad única que escribe la capa de sensado (nuestro plugin JSONL 5 Hz + lector de paquetes); comportamientos = pequeñas máquinas de estado dirigidas por evento que solo leen el modelo. Tipos componibles con una sola hash+predicado.
- **Triage de heal** (L2Apf `support.scm`, la mejor): orden lowest-HP-first; dos tiers (steady vs danger→heal grande/instantáneo); group-heal cuando >N heridos; `economy` floor para no malgastar en daño leve; `mp-reserve` para no fundir tu MP curando a otros; sit-to-regen al estar idle con MP bajo; **nunca actuar mientras casteas**.
- **Cooldown math, no cuenta-atrás** (L2Apf + L2Net): guardar `last_usage`+`reuse_delay` o `cast_time`, comparar con now; "¿buff sigue arriba?" = `now - cast >= duration`.
- **Tablas de reglas en config** (L2Net): tablas paralelas pociones/buffs/combate, fila = {trigger, Min_Per HP/MP/CP, gate Min_MP, cooldown, skill/item, filtro de target, rango}; nunca hardcodear umbrales.
- **Taxonomía de triggers** (L2Net): Always / resource-threshold / state-cure(AB_*) / combat-resource / Dead. Cubre heal+recharge+cleanse+rez+buff del Elder.
- **Backoff de acción fallida** (L2Net): tras cast fallido empujar el retry un intervalo fijo para no spinear.
- **Tick del healer** (L2jRoboto, literal MIT): refrescar auto-buffs (falta o <~20 restante) → restock de shots → targetear aliado con HP más bajo en radio cuando idle → si HP%≤umbral, castear el primer heal castable en orden de lista. Umbrales reales en código: heal 70%/80%, self-CP missing≥1000, radio 2000, vuelta a pueblo tras 10 ticks muerto.
- **Sin memoria/paquetes** (l2bot): barras por pixel con clamp; heal = click slot + hotkey; rebuff por intervalo fijo. (Fallback si el lector de paquetes no cubre algo.)

Lo que falta en TODAS las fuentes MIT y hay que diseñar para el Elder: **recharge de MP a party, resurrect de aliados, gestión de CP con pociones, buff a party con timers, cleanse de debuffs** — L2Apf `support.scm` y la taxonomía de L2Net son los mejores planos.

### 1.8 Retorno a pueblo / stuck (MEDIDO, L2jRoboto `FakePlayerAI`)

Muerte: `handleDeath()` cuenta `iterationsOnDeath`; tras `toVillageIterationsOnDeath=10` ticks → `toVillageOnDeath()` revive+teleporta a pueblo (coords desde el MapRegion del core, INFERIDO — no están en el mod). Movimiento: `maybeMoveToPawn`, offset −30 si el target se mueve (min 5), 50 si LOS bloqueado, `_moveToPawnTimeout=1000ms`, geodata si disponible. **No hay unstuck explícito** más allá de geodata+offsets.

---

## 2. Protocolo y cifrado de L2

Dos fases con cifrado distinto: **login server** (Blowfish+RSA+checksum) y **game server** (XOR simétrico con contador). Fuente principal: `l2js-client`/`fobus1289/l2js-hf-client` (HighFive); cross-check Interlude 746 con `lineage2ts`. **Aviso de chronicle**: los VALORES de opcode difieren entre chronicles; la tabla HighFive de abajo NO vale tal cual para Interlude 746 — hay que usar el mapa de opcodes del chronicle exacto del servidor objetivo (nuestro Mobius 746).

### 2.1 Login server — flujo y cifrado (MEDIDO, l2js-client)

Flujo: **Init → AuthGameGuard → GGAuth → RequestAuthLogin → LoginOk → RequestServerList → ServerList → RequestServerLogin → PlayOk** (orden INFERIDO del set de paquetes + `LoginPacketHandler.ts`). Opcodes login S→C (MEDIDO, `LoginPacketHandler.ts`, `data[0]&0xff`): `0x00 Init, 0x01 LoginFail, 0x02 AccountKicked, 0x03 LoginOk, 0x04 ServerList, 0x06 PlayFail, 0x07 PlayOk, 0x0b GGAuth`.

- **Blowfish estático→dinámico** (MEDIDO, `network/LoginCrypt.ts`): clave estática `STATIC_BLOWFISH_KEY` 16 bytes **exacta** `6b 60 cb 5b 82 ce 90 b1 cc 2b 6c 55 6c 6c 6c 6c` descifra el paquete Init; `incoming/login/Init.ts` lee los 16 bytes de clave dinámica al final del Init (`readB(16)`) y `LoginClient` la instala (`setKey`) para todo lo posterior.
- **RSA de credenciales** (MEDIDO, `Init.ts` + `outgoing/login/RequestAuthLogin.ts`): módulo = 128 bytes "scrambled" de Init, de-scrambled por `unscrambleModulus` en 4 pasos (XOR 0x40-0x7F con 0x00-0x3F; XOR 0x0D-0x10 con 0x34-0x37; XOR 0x00-0x3F con 0x40-0x7F; swap 0x00-0x03 con 0x4D-0x50). Cifrado **RSA crudo sin padding**, exponente `e=65537`, bloque 128 bytes: byte `0x5b=0x24`, usuario ASCII en offset `0x5e` (≤14), password en `0x6c` (≤16).
- **Checksum + XOR extra** (MEDIDO, `mmocore/crypt/NewCrypt.ts`): `appendChecksum` XORea cada word LE de 4 bytes (menos el último) y lo escribe al final; `verifyChecksum` lo comprueba. Solo en el **primer** paquete de login hay una capa XOR extra (`encXORPass`/`decXORPass`: `ecx+=edx; edx^=ecx` hacia delante / `edx^=ecx; ecx-=edx` hacia atrás) con clave de los bytes `[size-8..size-5]`.

### 2.2 Game server — cifrado XOR (MEDIDO, l2js-client + lineage2ts, idéntico)

No es Blowfish (pese al nombre `BlowfishKey` en el código): es un **stream XOR simétrico** con estado determinista (`network/GameCrypt.ts`). Cada dirección mantiene su copia de 16 bytes (`_inKey`/`_outKey`), ambas sembradas con la MISMA clave; flag `_istEnabled` arranca `false`.
- **Primer paquete en claro**: el primer `decrypt()` solo pone `_istEnabled=true` y devuelve el buffer intacto; `encrypt()` es no-op hasta entonces. Así el primer paquete de juego (la clave) va **sin cifrar**.
- **decrypt** por byte: `out = raw[i] ^ key[i&15] ^ prevCipherByte` (encadena con ciphertext). **encrypt**: `out = raw[i] ^ key[i&15] ^ prevOutByte`. `prev` se **resetea a 0 al inicio de cada paquete**.
- **Avance de clave** (MEDIDO, la rutina crítica): tras cada call, el contador LE de 32 bits en **bytes 8..11** se incrementa por `size` (bytes procesados) y se reescribe LE (wrap mod 2³²); bytes 0-7 y 12-15 no cambian; **cada dirección avanza su propio contador**. (Confirmado idéntico en lineage2ts `readInt32LE(8)+data.length`.)
- **Clave dinámica** (MEDIDO, `incoming/game/KeyPacket.ts`, opcode `0x2e`, HighFive): lee **8 bytes** del servidor y les añade la cola **exacta** `c8 27 93 01 a1 6c 31 97` → clave de 16. En **Interlude 746** (`lineage2ts BlowfishKeyGenerator`) la clave se genera **aleatoria de 16 bytes por conexión** server-side, así que el split 8+8 y esa cola **pueden no aplicar** en 746 (INFERIDO — no se pudo abrir `BlowfishKeyGenerator.ts`; el cliente gigabelka, que sería la respuesta directa, es inaccesible).
- **Framing** (MEDIDO, ambos): prefijo de longitud **2 bytes LE que INCLUYE los 2 de cabecera**; cabecera en claro; cuerpo = bytes `[2..len)` cifrados.

### 2.3 Lectura de paquetes (MEDIDO, `mmocore/ReceivablePacket.ts`)

`readC`=byte unsigned; `readH`=uint16 LE; `readD`=**int32 LE con signo**; `readF`=double LE; `readQ`=64-bit (lo+2³²·hi, pierde precisión >2⁵³); `readB(n)`=n bytes; `readS`=**UTF-16LE terminado en null** (2 bytes por code unit, incl. terminador).

### 2.4 Tabla de opcodes game S→C (MEDIDO, `GamePacketHandler.ts`, HighFive — NO Interlude)

Los que un lector pasivo necesita para reconstruir estado (HP/MP/CP propio, target, cercanos, buffs, mensajes):

| op | paquete | op | paquete |
|---|---|---|---|
| 0x00 | Die | 0x48 | MagicSkillUse |
| 0x08 | DeleteObject | 0x4a | CreatureSay |
| 0x0c | NpcInfo | 0x54 | MagicSkillLaunched |
| 0x16 | DropItem | 0x5f | SkillList |
| 0x18 | StatusUpdate (HP/MP/CP/stats) | 0x62 | SystemMessage |
| 0x1f | ActionFailed | 0x6b | SetupGauge (cast bar) |
| 0x21 | InventoryUpdate | 0x72 | MoveToPawn |
| 0x23/0x24 | Target(Un)Selected | 0x79 | ValidateLocation |
| 0x25/0x26 | AutoAttackStart/Stop | 0x85 | AbnormalStatusUpdate (debuffs) |
| 0x2e | KeyPacket (clave de cifrado) | 0xb9 | MyTargetSelected |
| 0x31 | CharInfo (otros chars) | 0xc7 | SkillCoolTime |
| 0x32 | UserInfo (propio) | 0xf4 | PartySpelled (buffs party) |
| 0x33 | Attack | 0xf9 | EtcStatusUpdate |
| 0x47 | StopMove | 0xfe | extended (sub-op 16-bit LE) |

Extended `0xfe` (MEDIDO): `sub = data[1] | data[2]<<8`; p.ej. 0x0039 ExShowScreenMessage, 0x00da ExBrExtraUserInfo. (L2Apf nombra equivalentes C4: `status_update, user_info, char_info, npc_info, magic_effects, skill_list, party_*, my_target_selected, die, revive`.)

### 2.5 Diferencias por chronicle (MEDIDO, lineage2ts 746)

- Cifrado de juego **idéntico** entre 746 y HighFive (mismo XOR, `&15`, contador en byte 8). Framing idéntico. **PERO no entre todas las familias** (corrección auditoría 2026-10-14, MEDIDO en L2Apf C4 `system/crypter.scm`/`key_packet.scm`): **C1-C5 usan clave de 8 bytes, índice mod 8, contador en bytes 0-3, bytes 4-7 estáticos, KeyPacket de 4 bytes**; el esquema 16 bytes/`&15`/contador 8-11/cola de 8 es **Interlude+**; Classic/GoD (protocolo 110, el de Reborn hoy) añade clave de ofuscación. Parametrizar el lector por familia `{key_len, counter_offset, static_tail, keypacket}`. El "746 = 16 aleatorios sin cola" de §2.2 está al revés: 746 lleva la cola (servidor envía 8, cliente añade `c8 27…`) — verificar en `BlowFishKeygen.java`/`KeyPacket.java` de Mobius.
- Mapas de opcode **por etapa**, no una tabla plana: `InitialConnection` (0x0e RequestEncryptionKey, 0x2b RequestAuthorizedLogin) → `VerifiedPacket` (0x12 CharacterSelect) → `SelectingCharacter` (0x11 RequestEnterWorld) → `HighFivePacket` in-world (0x00 Logout, 0x01 Attack, 0x0f MoveToLocation, 0x39 RequestMagicSkillUse). El primer paquete sin cifrar es el `RequestEncryptionKey` (0x0e) del cliente.
- Extended **C→S usa 0xD0** (no 0xFE) en 746.
- lineage2ts nombra su mapa in-world `HighFive*` aun targeteando 746 y su `proxy/` soporta ambos → tratar sus nombres como guía, no verdad para 746.

### 2.6 Lector PASIVO del propio tráfico — receta y gotchas (MEDIDO)

El cifrado de juego es XOR simétrico con estado determinista, así que descifrar una captura solo necesita:
1. **La clave dinámica del primer paquete de juego** (HighFive KeyPacket 0x2e: 8 bytes + cola `c8 27 93 01 a1 6c 31 97`; en 746 ver §2.2, probablemente 16 bytes directos). Ese primer paquete va **en claro**, legible directo de la captura.
2. Replay de cada paquete siguiente, en orden, por dirección, avanzando el contador (bytes 8-11) por la suma acumulada de bytes de esa dirección.

Gotchas MEDIDOS: (a) hay que **capturar desde el inicio de sesión** — el contador es una suma acumulada y no hay material de clave en el cable tras el primer paquete; una captura a mitad no descifra nada. (b) Mantener **dos estados de cifrado independientes** (C→S y S→C), misma clave inicial pero contador propio cada uno. (c) Quitar los 2 bytes LE de longitud antes de XOR (nunca cifrados; la longitud se incluye a sí misma; cuerpo = `[2..len)`). (d) El encadenado prev resetea por paquete, así que cada paquete se descifra independiente mientras el contador se haya avanzado por la suma de los cuerpos previos de su dirección. (e) Login es distinto: Blowfish (clave estática, luego dinámica de Init) + XOR extra en el primer paquete + checksum de 4 bytes.

Esto cuadra con la estrategia del plan (§4.2): correr el lector junto al plugin de servidor (verdad) y validar que pos/HP/MP/target coinciden ≥95%.

---

## 3. Nota de licencias

- **`L2jRoboto` = MIT**: único **copiable literal** en nuestro repo (ten en cuenta el bug de `_priority`, §1.1). Mantener el aviso de copyright MIT al reusar ficheros.
- **`L2Net` (GPL-2.0), `l2bot` (GPL-3.0), `L2Apf` (GPL-3.0)**: solo **estudiar la lógica**; copiar código contagiaría GPL a todo el repo. Reimplementar las ideas (triage, tablas de reglas, taxonomía de triggers, world-model) desde cero.
- **`l2js-client`/`lineage2ts`**: referencia del protocolo/cifrado. El algoritmo de cifrado y las constantes bien conocidas de L2 (clave Blowfish estática, cola de juego, módulo scrambled) son hechos de interoperabilidad, no expresión creativa; reimplementar el lector en nuestro lenguaje sin copiar su código.

---

## 4. Incógnitas no resueltas

- **Interlude 746 exacto**: `gigabelka/l2ts-interlude-client-l2jmobius` inaccesible (404 total). No se confirmó si 746 usa split clave 8+8 con cola `c8 27…` o 16 bytes aleatorios directos (lineage2ts sugiere lo segundo, server-side). **La tabla de opcodes de arriba es HighFive**; falta una tabla 746 S→C verificada — habrá que sacarla del propio datapack/core de Mobius 746 o capturando contra nuestro servidor (verdad disponible).
- No se abrió `BlowfishKeyGenerator.ts` (constantes de clave 746) ni `src/socket/adapters/` (framing de recepción, INFERIDO del lado de envío simétrico).
- L2Net: cuerpos de `BuffState`/`Has_Buff`/`IsReady`/`CanAttack` no leídos completos (ficheros >100KB); confirmados los 3 valores `Has/Needs/DoesntHave`.
- l2bot: `IsPartyDamaged`/`IsHealthDecrease` no localizados; coords de slots de party 2-8 parecen placeholders sin calibrar.
- Mapeo de skill IDs de L2jRoboto a nombres (1217=Heal, 1218=Greater Heal, etc.) INFERIDO por convención HighFive; validar contra el datapack de Mobius.
