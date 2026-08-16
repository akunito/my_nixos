---
id: akunito.infra.services.akucraft-staging-client-setup
summary: How to set up a Minecraft client for the AkuCraft STAGING test server, for someone helping test map sharing
tags: [minecraft, akucraft, staging, onboarding]
related_files: [user/app/games/minecraft-client-mods.nix]
date: 2026-08-16
status: published
---

# AkuCraft STAGING — client setup

This is the **test** server, not the one people play on. It runs a throwaway copy
of the world, so nothing you do here affects anybody's builds. Breaking things is
the point.

We are testing map sharing: seeing each other on the map, sharing explored areas,
and turning exploration into something you can trade.

**You need two people for this to mean anything**, which is why you are here.

---

## Before you start

- The VPN must be on. Everything below is only reachable through it.
- You will end up with a **new, separate instance**. Do not modify an instance
  you already use for the live server — the two have different mods and mixing
  them breaks both.

---

## 1. Install the launcher

**FreeSM Launcher** — https://github.com/FreesmTeam/FreesmLauncher/releases

---

## 2. Import the pack

With the VPN on, download:

```
http://100.64.0.6:8100/downloads/AkuCraft-STAGING-auto.mrpack
```

In the launcher: **Add Instance → Import →** choose that file.

**If it asks which Java: pick 21.** Not 8, not 17, not 25. If it offers to
download its own Java, say **no**.

---

## 3. Add your account

Add an **offline account** using your normal in-game name.

**Capitals matter.** The name is your identity on the server — `Komi` and `komi`
are two different players with different inventories. Use exactly the same
spelling you use on the live server.

---

## 4. First connect

The instance looks almost empty on purpose. It contains one mod, AutoModpack.
When you connect, the server hands over the real mod list — about 40 mods — your
game downloads them and restarts once.

Server address (already in your list after importing):

```
100.64.0.6:25599
```

### The fingerprint screen

The first time you connect you get **Certificate Verification** asking for a
fingerprint. That check is what stops someone impersonating the server and
putting files on your machine, so it is worth doing properly.

Paste this and press **Verify**:

```
c4d8172c89a5e3436d599fe128ffbe39bf0564ab2d22003c09e848ab8cb2d539
```

**Do not press Skip.** If the code shown on your screen does not match the one
above, stop and tell Diego before continuing.

> This is the STAGING fingerprint. The live server has a different one — each
> server has its own certificate, and each instance asks once.

### Register

On your first join:

```
/auth register <password> <password>
```

On later joins: `/auth login <password>`

---

## 5. What is different here

Two mods on this server are not on the live one:

- **Surveyor** — keeps your explored map on the *server* and can share it with
  people you choose.
- **Antique Atlas** — the map itself. **Press M.**

Sharing is **off by default**. Nobody sees your position or your explored map
until you deliberately share with them.

---

## What we need you to test

Say what actually happens, including the boring parts. "It worked" is less
useful than "it worked but took ages" or "the map was blank for a minute".

### A. Sharing with each other

```
/surveyor share Akunito
```
Diego runs the same command back with your name. Then:

- Open the atlas (**M**). Can you see where Diego is?
- Can you see terrain **he** explored and you have not?
- Walk somewhere new. Does it show up on his map?
- Run `/surveyor unshare Akunito`. Does it all stop?

### B. Does it survive the second world?

There is a second world on this server, reached with `/mw tp frontier`.

- Go there. Does the atlas record terrain in that world too?
- With one of you in each world, can you still see each other's position?
- Come back with `/mw tp overworld`. Is your original map still intact?

This is the one we are least sure about, so take your time with it.

### C. Turning exploration into an item

The idea is that exploring somewhere becomes something you can sell.

- Explore an area nobody has been to.
- Find or place a **cartography table**.
- **Sneak + use** the table while holding a blank map. It should produce a map
  containing the area you explored.
- Give that map to Diego. He **sneak + uses** it at a cartography table.
- Does the area you explored now appear on *his* map, without him going there?

If that works end to end, the whole idea works.

---

## If something goes wrong

- **"Received N registry entries that are unknown to this client"** — your mods
  are out of step with the server. Tell Diego; do not try to fix it by hand.
- **"Restart your game! Successfully updated the modpack"** on every single
  launch — it is stuck in a loop. Tell Diego, do not keep restarting.
- **The game will not start at all** — copy the whole error text.

The test server is restarted often and may be down at any moment. That is normal
and not something you broke.
