"""Infrastructure: Nodes (ssh targets + deploy), Docker (containers over ssh),
Monitoring (Prometheus via the VPS + Grafana link). All remote work runs in
threads; the UI is updated from GLib.idle_add."""
from __future__ import annotations

import subprocess
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from .. import dockerctl, log, monitoring, paths, swayipc  # noqa: E402
from ..state import SCOPES, Node  # noqa: E402
from .panels import Panel  # noqa: E402
from .widgets import button, chip, combo_row, combo_value, confirm, entry_row, list_row, scrolled, switch_row  # noqa: E402

_log = log.get("gui.infra")


def _bg(fn, done):
    """Run fn() in a thread, call done(result, error) on the main loop."""
    def worker():
        try:
            r = fn(); err = None
        except Exception as exc:  # noqa: BLE001
            r, err = None, exc
            _log.warning("background task failed: %s", exc)
        GLib.idle_add(lambda: (done(r, err), False)[1])
    threading.Thread(target=worker, daemon=True).start()


# ==========================================================================
# Nodes

class NodesPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Nodes")
        self.header_button("Probe all", self.probe_all, icon="network-transmit-receive-symbolic")
        self.header_button("Add profile…", self.add_profile, icon="list-add-symbolic", style="suggested-action", start=False)
        self._probe: dict[str, tuple[bool, str]] = {}

    def refresh(self) -> None:
        self.ctl.reload_state()
        rows = []
        for n in self.ctl.state.nodes():
            if self.query() and self.query() not in (n.id + n.name + n.ssh + n.profile).lower():
                continue
            chips = [(",".join(n.daemons) or "no docker", "common" if n.daemons else ""), (n.scope, n.scope)]
            pr = self._probe.get(n.id)
            if pr:
                chips.append(("up" if pr[0] else "DOWN", "ok" if pr[0] else "err"))
            rows.append((n.id, list_row(f"{n.id}  ·  {n.name}", (n.ssh or "this machine") + (f"  ·  {pr[1]}" if pr and pr[0] else ""), chips, disabled=not n.enabled), n))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(self.ctl.state.nodes())} nodes · deploy, docker, monitoring targets")

    def probe_all(self) -> None:
        nodes = list(self.ctl.state.nodes())
        self.win.toast(f"Probing {len(nodes)} nodes…")

        def work():
            return {n.id: dockerctl.reachable(n) for n in nodes}

        def done(res, err):
            if err:
                self.win.toast(f"Probe failed: {err}", error=True); return
            self._probe = res; self.refresh()
            down = [k for k, v in res.items() if not v[0]]
            self.win.toast(f"Probe: {len(res) - len(down)} up" + (f", down: {', '.join(down)}" if down else ""), error=bool(down))
        _bg(work, done)

    def add_profile(self) -> None:
        import glob, os
        have = {n.profile for n in self.ctl.state.nodes()}
        profs = sorted(os.path.basename(p)[:-len("-config.nix")] for p in glob.glob(str(paths.DOTFILES / "profiles" / "*-config.nix")))
        pop = Gtk.Popover(); lb = Gtk.ListBox(); lb.add_css_class("sa-list")
        for p in profs:
            row = list_row(p, "already a node" if p in have else "profiles/" + p + "-config.nix", [("node", "ok")] if p in have else []); row.prof = p; lb.append(row)  # type: ignore[attr-defined]

        def chosen(_lb, row):
            pop.popdown()
            self.listbox.unselect_all(); self.selected_id = None
            self.show_detail(Node(id=row.prof, name=row.prof, profile=row.prof, scope="common"), is_new=True)
        lb.connect("row-activated", chosen)
        sw = scrolled(lb); sw.set_size_request(380, 320); pop.set_child(sw); pop.set_parent(self.toolbar); pop.popup()

    def show_detail(self, n: Node, is_new: bool = False) -> None:
        self.clear_detail()
        self.attach_banner(lambda: do_save())
        self.detail_header(("New node: " if is_new else "") + n.id, n.ssh or "this machine")
        g = Adw.PreferencesGroup(title="Node")
        name = entry_row("Name", n.name); profile = entry_row("Profile (deploy.sh --profile)", n.profile)
        ssh = entry_row("ssh target user@host[:port] (empty = local)", n.ssh)
        d_rootful = switch_row("Docker rootful", "rootful" in n.daemons); d_rootless = switch_row("Docker rootless", "rootless" in n.daemons)
        sudo = switch_row("Rootful via sudo -n", n.sudo_rootful, "when the user is not in the docker group")
        prom = entry_row("Prometheus instance label", n.prometheus_instance)
        order = Adw.SpinRow.new_with_range(0, 9999, 10); order.set_title("Order"); order.set_value(n.order)
        enabled = switch_row("Enabled", n.enabled); scope = combo_row("Scope", list(SCOPES), n.scope); notes = entry_row("Notes", n.notes)
        for r in (name, profile, ssh, d_rootful, d_rootless, sudo, prom, order, enabled, scope, notes):
            g.add(r)
        self.detail.append(g)

        def collect() -> Node:
            return Node(id=n.id, name=name.get_text().strip(), profile=profile.get_text().strip(), ssh=ssh.get_text().strip(),
                        daemons=[d for d, w in (("rootful", d_rootful), ("rootless", d_rootless)) if w.get_active()],
                        sudo_rootful=sudo.get_active(), prometheus_instance=prom.get_text().strip(), enabled=enabled.get_active(),
                        order=int(order.get_value()), notes=notes.get_text(), updated_at=n.updated_at, scope=combo_value(scope))

        def _dirty(*_a): self.mark_dirty(do_save)
        for r in (name, profile, ssh, prom, notes): r.connect("changed", _dirty)
        for r in (d_rootful, d_rootless, sudo, enabled): r.connect("notify::active", _dirty)
        order.connect("notify::value", _dirty); scope.connect("notify::selected", _dirty)
        if is_new: self.mark_dirty(do_save)

        def do_save():
            x = collect()
            out = self.win.run_outcome(lambda: self.ctl.save_node(x, x.scope))
            if out is not None and out.ok:
                self.clear_dirty(); self.selected_id = x.id; self.refresh()

        def do_probe():
            self.win.toast(f"Probing {n.id}…")
            _bg(lambda: dockerctl.reachable(collect()), lambda r, e: self.win.toast(f"{n.id}: {r[1] if r and r[0] else (r[1] if r else e)}", error=not (r and r[0])))

        def do_deploy():
            x = collect(); prof = x.profile or x.id
            script = (f"cd {paths.DOTFILES} && ./install.sh {paths.DOTFILES} {prof} -s -u" if x.is_local else f"cd {paths.DOTFILES} && ./deploy.sh --profile {prof}")
            inner = f"{script}; echo; echo '--- deploy finished (exit '$?') --- press Enter to close'; read -r _"
            import shlex
            confirm(self.win, f"Deploy {prof}?", ("Runs install.sh here" if x.is_local else "Runs deploy.sh --profile " + prof) + " in a terminal. Push your changes first: it resets the target to origin/main.", "Deploy",
                    lambda: (swayipc.exec_(f"kitty --class sway-apps-deploy --title 'Deploy {prof}' -e bash -lc {shlex.quote(inner)}"), self.win.toast(f"Deploy of {prof} opened in a terminal")))

        def do_delete():
            confirm(self.win, f"Remove node {n.id}?", n.ssh or "local", "Remove", lambda: (self.win.run_outcome(lambda: self.ctl.delete_node(n)), self.show_placeholder(), self.refresh()))

        btns = [button("Probe", do_probe, icon="network-transmit-receive-symbolic"), button("Deploy…", do_deploy, icon="software-update-available-symbolic"),
                button("Docker", lambda: (self.win.panels["docker"].set_node(n.id), self.win.show_section("docker")), icon="package-x-generic-symbolic"),
                button("Save & apply", do_save, style="suggested-action", icon="document-save-symbolic")]
        if not is_new:
            btns.insert(0, button("Delete", do_delete, style="destructive-action"))
        self.action_bar(*btns)


# ==========================================================================
# Docker

class DockerPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Docker")
        self.node_combo = Gtk.DropDown.new_from_strings(["all nodes"])
        self.node_combo.connect("notify::selected", lambda *_: self.load())
        self.toolbar.pack_start(self.node_combo)
        self.header_button("Refresh", self.load, icon="view-refresh-symbolic")
        self.stats_toggle = Gtk.ToggleButton(label="stats", active=True); self.stats_toggle.set_tooltip_text("CPU/mem per container (docker stats)")
        self.toolbar.pack_start(self.stats_toggle)
        self.header_button("Disk usage", self.show_df, icon="drive-harddisk-symbolic", start=False)
        self._containers: list[dockerctl.Container] = []
        self._errors: list[str] = []
        self._loading = False
        self._logs_proc: subprocess.Popen | None = None
        self.progress = Gtk.Label(xalign=0); self.progress.add_css_class("dim-label"); self.progress.set_margin_start(12)
        self.insert_child_after(self.progress, self.toolbar)

    def _node_ids(self) -> list[str]:
        return [n.id for n in self.ctl.state.nodes() if n.enabled and n.daemons]

    def set_node(self, node_id: str) -> None:
        ids = self._node_ids()
        if node_id in ids:
            self.node_combo.set_selected(ids.index(node_id) + 1)

    def on_show(self) -> None:
        self.ctl.reload_state()
        ids = self._node_ids()
        cur = self.node_combo.get_selected()
        self.node_combo.set_model(Gtk.StringList.new(["all nodes"] + ids))
        self.node_combo.set_selected(min(cur, len(ids)))
        if not self._containers:
            self.load()
        else:
            self.refresh()

    def load(self) -> None:
        if self._loading:
            return
        self._loading = True
        ids = self._node_ids()
        sel = self.node_combo.get_selected()
        nodes = [n for n in self.ctl.state.nodes() if n.id in ids and (sel == 0 or n.id == ids[sel - 1])]
        with_stats = self.stats_toggle.get_active()
        self.progress.set_text(f"Loading containers from {', '.join(n.id for n in nodes)}…")

        def work():
            out, errs = [], []
            for n in nodes:
                for dmn in n.daemons:
                    try:
                        out += dockerctl.containers(n, dmn, with_stats=with_stats, with_inspect=True)
                    except dockerctl.DockerError as exc:
                        errs.append(str(exc))
            return out, errs

        def done(res, err):
            self._loading = False
            if err:
                self.progress.set_text(f"Error: {err}"); return
            self._containers, self._errors = res
            self.progress.set_text(("Errors: " + " · ".join(self._errors)) if self._errors else "")
            self.refresh()
        _bg(work, done)

    def refresh(self) -> None:
        q = self.query()
        rows = []
        items = sorted(self._containers, key=lambda c: (c.node, c.daemon, c.project or "~", c.name))
        last_group = None
        for c in items:
            if q and q not in (c.name + c.image + c.project + c.node).lower():
                continue
            grp = f"{c.node} · {c.daemon} · {c.project or 'no stack'}"
            if grp != last_group:
                hdr = Gtk.ListBoxRow(selectable=False, activatable=False)
                lbl = Gtk.Label(label=grp.upper(), xalign=0); lbl.add_css_class("sa-section-title"); lbl.set_margin_start(6); lbl.set_margin_top(8)
                hdr.set_child(lbl); rows.append((f"hdr:{grp}", hdr, None)); last_group = grp
            chips = [(c.state, "ok" if c.state == "running" else "err" if c.state in ("exited", "dead") else "warn")]
            if c.health:
                chips.append((c.health, "ok" if c.health == "healthy" else "warn"))
            if c.cpu_pct:
                chips.append((f"cpu {c.cpu_pct}", ""))
            if c.mem_usage:
                chips.append((f"mem {c.mem_usage.split(' / ')[0]}" + (f" / {c.mem_limit // 2**20}M" if c.mem_limit else ""), ""))
            rows.append((f"{c.node}/{c.daemon}/{c.name}", list_row(c.name, f"{c.image}  ·  {c.status}", chips, disabled=c.state != "running"), c))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(self._containers)} containers · {sum(1 for c in self._containers if c.state == 'running')} running")

    def _node(self, c: dockerctl.Container) -> Node:
        return self.ctl.state.node(c.node)

    def show_detail(self, c: dockerctl.Container) -> None:
        if c is None:
            return
        self._stop_logs()
        self.clear_detail()
        self.detail_header(c.name, f"{c.node} · {c.daemon} · {c.image}")
        g = Adw.PreferencesGroup(title="Container")
        for t, v in (("State", f"{c.state} · {c.status}" + (f" · {c.health}" if c.health else "")), ("Stack", c.project or "—"), ("Service", c.service or "—"),
                     ("Compose directory", c.working_dir or "—"), ("Compose files", c.config_files or "—"), ("Restart policy", c.restart_policy or "—"),
                     ("Ports", c.ports or "—"), ("Created", c.created)):
            r = Adw.ActionRow(title=t, subtitle=str(v)); r.set_subtitle_selectable(True); g.add(r)
        self.detail.append(g)
        g2 = Adw.PreferencesGroup(title="Resources", description="live usage · configured limits")
        for t, v in (("CPU", f"{c.cpu_pct or '—'}  ·  limit {c.cpu_limit:g} cpus" if c.cpu_limit else f"{c.cpu_pct or '—'}  ·  no limit"),
                     ("Memory", f"{c.mem_usage or '—'} ({c.mem_pct or '—'})" + (f"  ·  limit {c.mem_limit // 2**20} MiB" if c.mem_limit else "  ·  no limit")),
                     ("Network I/O", c.net_io or "—"), ("Block I/O", c.block_io or "—"), ("PIDs", c.pids or "—")):
            g2.add(Adw.ActionRow(title=t, subtitle=v))
        self.detail.append(g2)
        g3 = Adw.PreferencesGroup(title=f"Mounts ({len(c.mounts)})")
        for m in c.mounts:
            r = Adw.ActionRow(title=f"{m['destination']}  ({m['type']}, {m['rw']})", subtitle=m['source']); r.set_subtitle_selectable(True); g3.add(r)
        if not c.mounts:
            g3.add(Adw.ActionRow(title="none"))
        self.detail.append(g3)
        self.logs_view = Gtk.TextView(editable=False, monospace=True, cursor_visible=False)
        self.logs_view.set_size_request(-1, 220)
        frame = Gtk.Frame(); frame.set_child(scrolled(self.logs_view))
        self.detail.append(Gtk.Label(label="LOGS (last 200 lines, follows)", xalign=0, css_classes=["sa-section-title"]))
        self.detail.append(frame)
        self._start_logs(c)

        def act(what: str, confirm_first: bool = False):
            def run():
                self.progress.set_text(f"{what} {c.name}…")
                _bg(lambda: dockerctl.action(self._node(c), c.daemon, c, what),
                    lambda r, e: (self.progress.set_text(""), self.win.toast(f"{what} {c.name}: {'ok' if not e else e}", error=bool(e)), self.load()))
            if confirm_first:
                confirm(self.win, f"{what} {c.name}?", c.working_dir or c.image, what, run)
            else:
                run()
        self.action_bar(button("Stop", lambda: act("stop", True), style="destructive-action"), button("Restart", lambda: act("restart")),
                        button("Start", lambda: act("start")), button("Pull + up", lambda: act("pull", True), icon="software-update-available-symbolic"),
                        button("Recreate", lambda: act("recreate", True)))

    def _start_logs(self, c: dockerctl.Container) -> None:
        try:
            self._logs_proc = dockerctl.follow_logs(self._node(c), c.daemon, c.name, tail=200)
        except Exception as exc:
            self.logs_view.get_buffer().set_text(f"logs unavailable: {exc}"); return
        proc = self._logs_proc; view = self.logs_view

        def reader():
            for line in proc.stdout:  # type: ignore[union-attr]
                if proc is not self._logs_proc:
                    break
                GLib.idle_add(lambda l=line: (self._append_log(view, l), False)[1])
        threading.Thread(target=reader, daemon=True).start()

    def _append_log(self, view, line: str) -> None:
        buf = view.get_buffer()
        buf.insert(buf.get_end_iter(), line)
        if buf.get_line_count() > 2000:
            start = buf.get_start_iter(); end = buf.get_iter_at_line(500)[1] if isinstance(buf.get_iter_at_line(500), tuple) else buf.get_iter_at_line(500)
            buf.delete(start, end)
        view.scroll_to_iter(buf.get_end_iter(), 0.0, False, 0, 0)

    def _stop_logs(self) -> None:
        if self._logs_proc is not None:
            try:
                self._logs_proc.terminate()
            except Exception:
                pass
            self._logs_proc = None

    def show_df(self) -> None:
        ids = self._node_ids(); sel = self.node_combo.get_selected()
        node = self.ctl.state.node(ids[sel - 1]) if sel > 0 and ids else (self.ctl.state.node(ids[0]) if ids else None)
        if node is None:
            self.win.toast("Pick a node first", error=True); return
        self.progress.set_text(f"docker system df on {node.id}…")

        def done(res, err):
            self.progress.set_text("")
            if err:
                self.win.toast(f"df failed: {err}", error=True); return
            self._stop_logs(); self.clear_detail()
            self.detail_header(f"Disk usage · {node.id}", "docker system df -v")
            for dmn, d in res.items():
                g = Adw.PreferencesGroup(title=dmn + (f"  (error: {d['error']})" if d.get("error") else ""))
                for s in d["summary"]:
                    g.add(Adw.ActionRow(title=f"{s.get('Type')}: {s.get('Size')}", subtitle=f"{s.get('TotalCount')} total · {s.get('Active')} active · reclaimable {s.get('Reclaimable')}"))
                self.detail.append(g)
                vols = d["volumes"]
                if vols:
                    gv = Adw.PreferencesGroup(title=f"{dmn} volumes ({len(vols)})")
                    for v in vols[:60]:
                        r = Adw.ActionRow(title=f"{v['name']}  ·  {v['size']}", subtitle=(v.get("mountpoint") or "") + (f"  ·  used by {v['links']}" if v.get("links") not in (None, "") else "")); r.set_subtitle_selectable(True); gv.add(r)
                    self.detail.append(gv)
        _bg(lambda: {dmn: dockerctl.disk_usage(node, dmn) for dmn in node.daemons}, done)


# ==========================================================================
# Monitoring

class MonitoringPanel(Gtk.Box):
    def __init__(self, win) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win; self.ctl = win.ctl
        self.toolbar = Adw.HeaderBar(); self.toolbar.set_title_widget(Adw.WindowTitle(title="Monitoring", subtitle="Prometheus via the VPS · backups"))
        self.append(self.toolbar)
        self.toolbar.pack_start(button("Refresh", self.load, icon="view-refresh-symbolic"))
        self.toolbar.pack_end(button("Open Grafana", lambda: (swayipc.exec_(f"xdg-open {monitoring.GRAFANA_URL}"), None), icon="web-browser-symbolic"))
        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12); self.body.add_css_class("sa-detail")
        self.append(scrolled(self.body))
        self._loading = False; self._loaded = False

    def on_show(self) -> None:
        if not self._loaded:
            self.load()

    def refresh(self) -> None:
        pass

    def _clear(self):
        c = self.body.get_first_child()
        while c is not None:
            n = c.get_next_sibling(); self.body.remove(c); c = n

    def load(self) -> None:
        if self._loading:
            return
        self._loading = True
        self._clear(); self.body.append(Gtk.Label(label="Querying Prometheus through the VPS…", xalign=0, css_classes=["dim-label"]))
        st = self.ctl.state

        def done(res, err):
            self._loading = False; self._loaded = True; self._clear()
            if err:
                self.body.append(Gtk.Label(label=f"Monitoring unavailable: {err}", xalign=0, css_classes=["error"])); return
            down = [t for t in res["targets"] if not t["up"]]
            g = Adw.PreferencesGroup(title=f"Targets: {len(res['targets']) - len(down)} up · {len(down)} down")
            for t in down:
                g.add(Adw.ActionRow(title=f"{t['job']}", subtitle=t["instance"], css_classes=["error"]))
            if not down:
                g.add(Adw.ActionRow(title="Everything scraped by Prometheus is up"))
            self.body.append(g)
            for card in res["nodes"]:
                m = card["metrics"]
                gn = Adw.PreferencesGroup(title=f"{card['node']}  ·  {m['up']['text']}", description=card["name"])
                for key, label in (("load1", "Load (1m)"), ("mem_used_pct", "Memory used"), ("root_used_pct", "Root filesystem used"), ("uptime_s", "Uptime")):
                    gn.add(Adw.ActionRow(title=label, subtitle=m[key]["text"]))
                self.body.append(gn)
            gl = Adw.PreferencesGroup(title="Backups")
            gb = res["global"]
            for key, label in (("nas_backup_age_s", "NAS backup age"), ("nas_backup_status", "NAS backup status (1 = ok)"), ("nas_offsite_backup_last_success", "NAS offsite backup, last success"),
                               ("mariadb_backup_daily_age_s", "MariaDB daily backup age"), ("backup_repo_size_bytes", "Backup repo size")):
                gl.add(Adw.ActionRow(title=label, subtitle=gb.get(key, {}).get("text", "—")))
            self.body.append(gl)
            for e in res["errors"]:
                self.body.append(Gtk.Label(label=e, xalign=0, css_classes=["error"]))
        _bg(lambda: monitoring.overview(st), done)
