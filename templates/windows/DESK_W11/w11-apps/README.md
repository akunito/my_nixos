# w11-apps: retired

Started 2026-09-20 as a Python twin of `user/wm/sway/sway-apps` for the
Windows desk, parked the same day when the decision became one application
(AkuWM) instead of GlazeWM + AutoHotkey + a config tool.

It never ran as a tool: `pyproject.toml` names a `w11_apps.cli:main` that
does not exist, and there is no generator, template or test. What is here is
the state model (`model.py`, `state.py`) and an importer that reads today's
`glazewm/config.yaml` and the `AppToggle` table of `hyper-desktops.ahk`.

Its review, and what carries over as design into AkuWM's configuration, is
section 13 of `docs/akunito/infrastructure/desk-w11-akuwm-plan.md`. The
package is deleted in AkuWM's M0 once `akuwm config import glazewm`
reproduces the importer's output (21 rules, 20 workspaces, 13 apps).
