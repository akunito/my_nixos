{ lib, userSettings, ... }:

# US-International dead-keys fix: make the acute dead key (') accent VOWELS only.
#
# The us(intl) layout emits a `dead_acute` keysym for '. The system compose table
# (libxkbcommon-compose / ~/.XCompose) then resolves dead_acute + <letter>. By
# default it maps consonants to Polish/Latin accents (dead_acute + s = ś, c = ć,
# n = ń, z = ź, r = ŕ, l = ĺ, ...), which mangles English contractions:
# "let's" -> "letś". We `include "%L"` (the locale default, keeping vowel accents
# and the '+space -> ' rule) and then override every consonant so dead_acute + X
# yields a literal "'X". Polish accents stay available via the dedicated `pl`
# layout, which doesn't go through this compose path.
let
  consonants = [
    "b" "c" "d" "f" "g" "h" "j" "k" "l" "m"
    "n" "p" "q" "r" "s" "t" "v" "w" "x" "z"
  ];
  # Override both cases so 'S, 'T, etc. also fall back to literal "'X".
  overrideLines = lib.concatMap (c: [
    ''<dead_acute> <${c}> : "'${c}"''
    ''<dead_acute> <${lib.toUpper c}> : "'${lib.toUpper c}"''
  ]) consonants;
  lines = [
    "# Managed by NixOS dotfiles (user/wm/sway/xcompose.nix). Do not edit by hand."
    ''include "%L"''
    ""
    ''# Acute dead key accents vowels only; consonants fall back to literal "'X".''
  ] ++ overrideLines;
in
lib.mkIf userSettings.usIntlApostropheComposeFix {
  home.file.".XCompose".text = lib.concatStringsSep "\n" lines + "\n";
}
