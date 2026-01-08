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
(\Q            Timer {\E\s*
                //SDDM has a bug in 0.13 where even though we set the focus on the right item within the window, the window doesn'\''t have focus\s*
                //it is fixed in 6d5b36b28907b16280ff78995fef764bb0c573db which will be 0.14\s*
                //we need to call "window->activate()" *After* it'\''s been shown. We can'\''t control that in QML so we use a shoddy timer\s*
                //it'\''s been this way for all Plasma 5.x without a huge problem\s*
                running: true\s*
                repeat: false\s*
                interval: 200\s*
                onTriggered: mainStack.forceActiveFocus\(\)\s*
            }\s*)@
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


