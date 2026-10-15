// REA triage rules (AINF-408). Our own rules, matching product names and well-known
// section/magic markers only. meta.action:
//   reject — hold for Diego (anti-cheat, DRM): propose REJECT so he explicitly confirms before analysing; overridable, only a proposal
//   tier2  — packed/protected: treat as suspicious
// False positives are expected (a name in a string table is not proof); triage only
// proposes a tier, Diego decides.

rule rea_anticheat
{
  meta:
    action = "reject"
    why = "anti-cheat component, or a client protected by one — analyse only with Diego's explicit go-ahead"
  strings:
    $eac1 = "EasyAntiCheat" nocase ascii wide
    $be1  = "BattlEye" nocase ascii wide
    $be2  = "BEService" ascii wide
    $xc1  = "XIGNCODE" nocase ascii wide
    $np1  = "nProtect GameGuard" nocase ascii wide
    $np2  = "GameGuard.des" nocase ascii wide
    $vg1  = "vgk.sys" nocase ascii wide
    $vg2  = "vgc.exe" nocase ascii wide
    $eq1  = "EQU8" ascii wide
    $mh1  = "mhyprot" nocase ascii wide
    $ace1 = "AntiCheatExpert" nocase ascii wide
    $ace2 = "ACE-Guard" nocase ascii wide
    $fa1  = "FACEIT AC" nocase ascii wide
    $pb1  = "PnkBstrA" nocase ascii wide
  condition:
    any of them
}

rule rea_drm
{
  meta:
    action = "reject"
    why = "DRM / licence protection — analyse to understand it only with Diego's explicit go-ahead; do not build a circumvention"
  strings:
    $d1 = "Denuvo" nocase ascii wide
    $d2 = "SecuROM" nocase ascii wide
    $d3 = "StarForce" nocase ascii wide
    $d4 = "Arxan" nocase ascii wide
    $d5 = "FlexNet Licensing" nocase ascii wide
    $d6 = "Sentinel LDK" nocase ascii wide
    $d7 = "CodeMeter" nocase ascii wide
  condition:
    any of them
}

rule rea_protector
{
  meta:
    action = "tier2"
    why = "commercial protector / obfuscator"
  strings:
    $vmp1 = ".vmp0" ascii
    $vmp2 = ".vmp1" ascii
    $vmp3 = "VMProtect" nocase ascii wide
    $th1  = "Themida" nocase ascii wide
    $th2  = "WinLicense" nocase ascii wide
    $en1  = "Enigma Protector" nocase ascii wide
    $asp  = "ASProtect" nocase ascii wide
    $obs  = "Obsidium" nocase ascii wide
    $cfx  = "ConfuserEx" nocase ascii wide
  condition:
    any of them
}

rule rea_packer_upx
{
  meta:
    action = "tier2"
    why = "UPX-packed: the real code is hidden until unpacked"
  strings:
    $u1 = "UPX!" ascii
    $u2 = "UPX0" ascii
    $u3 = "UPX1" ascii
  condition:
    2 of them
}
