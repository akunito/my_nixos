{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "sddm-breeze-patched-theme";
  version = "1";

  dontUnpack = true;

  nativeBuildInputs = [
    pkgs.perl
  ];

  installPhase = ''
    set -euo pipefail

    mkdir -p "$out/share/sddm/themes"

    # Copy upstream Breeze SDDM theme from Plasma Desktop
    cp -R "${pkgs.kdePackages.plasma-desktop}/share/sddm/themes/breeze" \
      "$out/share/sddm/themes/breeze-patched"

    # Ensure the copied QML files are writable so we can patch them
    chmod -R u+w "$out/share/sddm/themes/breeze-patched"

    # Patch: after any screenModel.count change (monitor add/remove/sync), re-assert focus
    # to avoid the password field losing keyboard focus on multi-monitor setups.
    perl -0777 -i -pe '
      s@
(\s*Timer\s*\{\s*[\s\S]*?interval:\s*200\s*[\s\S]*?onTriggered:\s*mainStack\.forceActiveFocus\(\)\s*[\s\S]*?\}\s*)@
$1

            Timer {
                id: focusRepairTimer
                interval: 250
                repeat: false
                onTriggered: {
                    mainStack.forceActiveFocus()
                    if (userListComponent && userListComponent.mainPasswordBox) {
                        userListComponent.mainPasswordBox.forceActiveFocus()
                    }
                }
            }

            Connections {
                target: screenModel
                function onCountChanged() {
                    focusRepairTimer.restart()
                }
            }
@s;
    ' "$out/share/sddm/themes/breeze-patched/Main.qml"
  '';
}


