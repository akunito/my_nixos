"""Infrastructure: Nodes (ssh targets + deploy), Docker (containers over ssh),
Monitoring (Prometheus via the VPS + Grafana link). All remote work runs in
threads; the UI is updated from GLib.idle_add."""
from __future__ import annotations

import subprocess
import threading
import time

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from .. import levels, dockerctl, log, monitoring, paths, swayipc  # noqa: E402
from ..state import SCOPES, Node  # noqa: E402
from . import charts
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
            elif not n.enabled:
                chips.append(("disabled", "warn"))
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
                chips.append((c.health, "ok" if c.health == "healthy" else "err" if c.health == "unhealthy" else "warn"))
            if c.cpu_pct:
                chips.append((f"cpu {c.cpu_pct}", levels.load(levels.parse_pct(c.cpu_pct))))
            if c.mem_usage:
                # mem_pct is against the limit when one is set, else against the host
                chips.append((f"mem {c.mem_usage.split(' / ')[0]}" + (f" / {c.mem_limit // 2**20}M" if c.mem_limit else "") + (f" · {c.mem_pct}" if c.mem_pct else ""),
                              levels.pct(levels.parse_pct(c.mem_pct)) if c.mem_limit else ""))
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
    """Tabs: Nodes · Storage · Backups · Network · Targets. Everything comes from
    ONE ssh round trip to the VPS (monitoring.dashboard), only when shown/refreshed."""

    TABS = (("nodes", "Nodes", "computer-symbolic"), ("storage", "Storage", "drive-harddisk-symbolic"),
            ("backups", "Backups", "document-save-symbolic"), ("network", "Network", "network-wireless-symbolic"),
            ("targets", "Targets", "emblem-ok-symbolic"))

    def __init__(self, win) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win; self.ctl = win.ctl
        self.stack = Adw.ViewStack()
        self.pages: dict[str, Gtk.Box] = {}
        for key, title, icon in self.TABS:
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12); box.add_css_class("sa-detail")
            self.pages[key] = box
            self.stack.add_titled_with_icon(scrolled(box), key, title, icon)
        switcher = Adw.ViewSwitcher(stack=self.stack, policy=Adw.ViewSwitcherPolicy.WIDE)
        self.toolbar = Adw.HeaderBar(); self.toolbar.set_title_widget(switcher)
        self.append(self.toolbar)
        self.toolbar.pack_start(button("Refresh", self.load, icon="view-refresh-symbolic"))
        self.toolbar.pack_end(button("Grafana", lambda: (swayipc.exec_(f"xdg-open {monitoring.GRAFANA_URL}"), None), icon="web-browser-symbolic"))
        self.status = Gtk.Label(xalign=0, wrap=True); self.status.add_css_class("dim-label"); self.status.set_margin_start(14); self.status.set_margin_top(4)
        self.append(self.status)
        self.append(self.stack)
        self.stack.set_vexpand(True)
        self._loading = False; self._loaded = False
        self._legend = (f"green < {levels.PCT_WARN:.0f}% · yellow {levels.PCT_WARN:.0f}–{levels.PCT_ERR:.0f}% · red > {levels.PCT_ERR:.0f}% (disk, memory) · "
                        f"CPU load per core: yellow > {levels.LOAD_WARN:.0f}%, red > {levels.LOAD_ERR:.0f}% · "
                        f"backups: yellow > {levels.BACKUP_WARN_S / 86400:.0f} d, red > {levels.BACKUP_ERR_S / 86400:.0f} d (hourly jobs: > {levels.HOURLY_WARN_S / 3600:.0f} h / > {levels.HOURLY_ERR_S / 3600:.0f} h) · "
                        f"ping (from the VPS): yellow > {levels.RTT_WARN_MS:.0f} ms, red > {levels.RTT_ERR_MS:.0f} ms")

    def on_show(self, tab: str | None = None) -> None:
        if tab in self.pages:
            self.stack.set_visible_child_name(tab)
        if not self._loaded:
            self.load()

    def refresh(self) -> None:
        pass

    @staticmethod
    def _clear(box: Gtk.Box) -> None:
        c = box.get_first_child()
        while c is not None:
            n = c.get_next_sibling(); box.remove(c); c = n

    def _flow(self) -> Gtk.FlowBox:
        fb = Gtk.FlowBox(); fb.set_selection_mode(Gtk.SelectionMode.NONE); fb.set_homogeneous(True)
        fb.set_min_children_per_line(1); fb.set_max_children_per_line(3); fb.set_column_spacing(12); fb.set_row_spacing(12)
        fb.set_valign(Gtk.Align.START)
        return fb

    def load(self) -> None:
        if self._loading:
            return
        self._loading = True
        self.status.set_text("Querying Prometheus through the VPS (one ssh round trip)…")
        st = self.ctl.state

        def done(res, err):
            self._loading = False; self._loaded = True
            if err:
                self.status.set_text(f"Monitoring unavailable: {err}"); self.status.add_css_class("error"); return
            self.status.remove_css_class("error")
            sm = res.get("summary", {})
            when = time.strftime("%H:%M:%S", time.localtime(res.get("generated", time.time())))
            self.status.set_text(f"Updated {when} · targets down {sm.get('targets_down', 0)} · " + " · ".join(
                f"{k} {v or '—'}" for k, v in (("nodes", sm.get("nodes_level")), ("storage", sm.get("storage_level")), ("backups", sm.get("backups_level")), ("network", sm.get("network_level")))))
            for key, _t, _i in self.TABS:
                page = self.stack.get_child_by_name(key)
                page.set_badge_number(0); page.set_needs_attention(False)
            self._build_nodes(res); self._build_storage(res); self._build_backups(res); self._build_network(res); self._build_targets(res)
            for e in res.get("errors", []):
                self.status.set_text(self.status.get_text() + f" · {e}")
        _bg(lambda: monitoring.dashboard(st), done)

    def _attention(self, key: str, items: list[dict]) -> None:
        bad = sum(1 for x in items if x.get("level") == "err")
        page = self.stack.get_child_by_name(key)
        page.set_badge_number(bad); page.set_needs_attention(bad > 0)

    def _legend_label(self) -> Gtk.Label:
        return Gtk.Label(label=self._legend, xalign=0, wrap=True, css_classes=["sa-legend"])

    # ---- tabs ------------------------------------------------------------------
    def _build_nodes(self, res: dict) -> None:
        box = self.pages["nodes"]; self._clear(box)
        box.append(self._legend_label())
        fb = self._flow()
        for c in res["nodes"]:
            up_text = "UP" if c["up"] else ("DOWN" if c["up"] is False else "not scraped")
            card, body = charts.card(f"{c['node']}  ·  {c['name']}", up_text, c["up_level"] or "warn")
            if c["lightweight"]:
                body.append(Gtk.Label(label="lightweight exporter: filesystems only (no CPU / memory series)", xalign=0, wrap=True, css_classes=["sa-legend"]))
            else:
                l1 = c["load1"]; ncpu = c["ncpu"]
                body.append(charts.Gauge("CPU load (1 m) vs cores", c["load_pct"], f"{l1:.2f} on {int(ncpu)} cores · {c['load_pct']:.0f}%" if c["load_pct"] is not None else "—", c["load_level"]))
                body.append(charts.Sparkline(c["load_series"], c["load_level"], ymax=100))
                body.append(charts.Gauge("Memory used", c["mem_pct"], levels.pct_text(c["mem_pct"]), c["mem_level"]))
                body.append(charts.Sparkline(c["mem_series"], c["mem_level"], ymax=100))
                body.append(Gtk.Label(label=f"uptime {c['uptime_text']} · sparklines: last 6 h", xalign=0, css_classes=["sa-legend"]))
            for f in c["fs"]:
                body.append(charts.Gauge(f["mountpoint"], f["used_pct"], levels.pct_text(f["used_pct"]), f["level"], f["text"]))
            if not c["fs"] and c["up"] is False:
                body.append(Gtk.Label(label="no data: the exporter is down", xalign=0, css_classes=["sa-legend"]))
            fb.append(card)
        box.append(fb)
        self._attention("nodes", res["nodes"])

    def _build_storage(self, res: dict) -> None:
        box = self.pages["storage"]; self._clear(box)
        fb = self._flow()
        z = res["storage"]["zfs"]
        if z:
            card, body = charts.card("NAS ZFS pools", "healthy" if all(p["healthy"] for p in z) else "DEGRADED", "ok" if all(p["healthy"] for p in z) else "err")
            for pool in z:
                body.append(charts.Gauge(pool["pool"], pool["used_pct"], levels.pct_text(pool["used_pct"]), pool["level"], pool["text"] + ("" if pool["healthy"] else " · NOT healthy")))
            fb.append(card)
        for c in res["nodes"]:
            if not c["fs"]:
                continue
            worst = levels.worst(*[f["level"] for f in c["fs"]])
            card, body = charts.card(c["node"], f"{len(c['fs'])} filesystems", worst)
            for f in c["fs"]:
                body.append(charts.Gauge(f["mountpoint"], f["used_pct"], levels.pct_text(f["used_pct"]), f["level"], f["text"]))
            fb.append(card)
        for inst, fss in res["storage"].get("other", {}).items():
            card, body = charts.card(f"instance {inst}", "no node entry", "warn")
            for f in fss:
                body.append(charts.Gauge(f["mountpoint"], f["used_pct"], levels.pct_text(f["used_pct"]), f["level"], f["text"]))
            fb.append(card)
        box.append(fb)
        self._attention("storage", z + [f for c in res["nodes"] for f in c["fs"]])

    def _build_backups(self, res: dict) -> None:
        box = self.pages["backups"]; self._clear(box)
        box.append(Gtk.Label(label="The bar shows how close each backup is to its limit (1 week for daily jobs, 24 h for hourly ones). Red = older than the limit or the last run failed.", xalign=0, wrap=True, css_classes=["sa-legend"]))
        fb = self._flow()
        groups: dict[str, list[dict]] = {}
        for b in res["backups"]:
            groups.setdefault(b["group"], []).append(b)
        for g, items in groups.items():
            worst = levels.worst(*[b["level"] for b in items])
            card, body = charts.card(g, {"ok": "all fresh", "warn": "getting old", "err": "ATTENTION", "": "—"}[worst], worst)
            for b in items:
                limit = levels.HOURLY_ERR_S if b["hourly"] else levels.BACKUP_ERR_S
                pct = None if b["age_s"] is None else min(100.0, 100 * b["age_s"] / limit)
                value = ("never" if b["age_s"] is None else f"{b['age_text']} ago") + ("" if b["ok"] in (True, None) else " · FAILED")
                sub = " · ".join(x for x in (b["size_text"], b["detail"]) if x)
                body.append(charts.Gauge(b["name"], pct, value, b["level"], sub))
            fb.append(card)
        box.append(fb)
        self._attention("backups", res["backups"])

    def _build_network(self, res: dict) -> None:
        box = self.pages["network"]; self._clear(box)
        fb = self._flow()
        icmp = [n for n in res["network"] if n["kind"] == "icmp"]; http = [n for n in res["network"] if n["kind"] == "http"]
        if icmp:
            card, body = charts.card("Ping from the VPS", f"{sum(1 for n in icmp if not n['up'])} down", levels.worst(*[n["level"] for n in icmp]))
            for n in icmp:
                pct = None if n["rtt_ms"] is None else min(100.0, 100 * n["rtt_ms"] / levels.RTT_ERR_MS)
                body.append(charts.Gauge(n["instance"], pct if n["up"] else 100, n["text"] if n["up"] else "DOWN", n["level"]))
                if n["series"]:
                    body.append(charts.Sparkline(n["series"], n["level"], height=26))
            body.append(Gtk.Label(label="sparklines: rtt over the last 6 h", xalign=0, css_classes=["sa-legend"]))
            fb.append(card)
        if http:
            card, body = charts.card("HTTP probes", f"{sum(1 for n in http if not n['up'])} failing", levels.worst(*[n["level"] for n in http]))
            for n in http:
                pct = None if n.get("duration_s") is None else min(100.0, 100 * n["duration_s"] / levels.HTTP_ERR_S)
                body.append(charts.Gauge(n["instance"], pct if n["up"] else 100, n["text"] if n["up"] else f"FAILING · {n['text']}", n["level"]))
            fb.append(card)
        box.append(fb)
        self._attention("network", res["network"])

    def _build_targets(self, res: dict) -> None:
        box = self.pages["targets"]; self._clear(box)
        lb = Gtk.ListBox(); lb.add_css_class("sa-list"); lb.set_selection_mode(Gtk.SelectionMode.NONE)
        for t in res["targets"]:
            lb.append(list_row(t["job"], t["instance"], [("UP" if t["up"] else "DOWN", t["level"])]))
        down = sum(1 for t in res["targets"] if not t["up"])
        box.append(Gtk.Label(label=f"{len(res['targets'])} scrape targets · {down} down", xalign=0, css_classes=["sa-legend"]))
        box.append(lb)
        self._attention("targets", res["targets"])
