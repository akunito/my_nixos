# aiPresets (Nix data, see ai-presets.nix) -> llama-server router-mode preset INI
# (--models-preset). Section name = model id = preset name: clients select a
# preset just by naming it in the request's `model`.
#
# Keys are llama-server flags without dashes (README "Model presets"); the
# preset's `extra` list ("--temp" "1.0" "--jinja" "-fa" "on" …) is turned into
# key = value pairs, a flag without a value becoming `= true`.
{ lib, modelsDir ? "/var/lib/llama-server/models" }:
presets:
let
  extraPairs = extra:
    let
      n = builtins.length extra;
      go = i:
        if i >= n then [ ]
        else
          let
            tok = builtins.elemAt extra i;
            key = lib.removePrefix "-" (lib.removePrefix "-" tok);
            next = if i + 1 < n then builtins.elemAt extra (i + 1) else null;
            hasValue = next != null && !(lib.hasPrefix "-" next);
          in
          if !(lib.hasPrefix "-" tok) then go (i + 1)    # stray value: skip
          else [ "${key} = ${if hasValue then next else "true"}" ] ++ go (i + (if hasValue then 2 else 1));
    in go 0;
  section = name: p: lib.concatStringsSep "\n" ([
    "[${name}]"
    "model = ${modelsDir}/${p.model}"
    "c = ${toString p.ctx}"
    "np = ${toString (p.slots or 1)}"
    "ngl = 999"
  ]
  ++ lib.optionals ((p.kv or "") != "") [ "ctk = ${p.kv}" "ctv = ${p.kv}" ]
  ++ lib.optional ((p.template or null) != null) "chat-template-file = ${p.template}"
  ++ extraPairs (p.extra or [ "--jinja" ]));
in
"version = 1\n\n" + lib.concatStringsSep "\n\n" (lib.mapAttrsToList section presets) + "\n"
