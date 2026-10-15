{ pkgs }:
# Waydroid images (LineageOS 20 = Android 13, x86_64, no Google apps) for the --android lane
# (AINF-408): pinned by the sha256 the Waydroid OTA (ota.waydro.id) publishes, so a newer
# build only arrives when we bump these. `waydroid init -i` uses the directory in place
# (read-only loop mounts).
let
  get = kind: name: sha256: pkgs.fetchurl {
    inherit name sha256;
    url = "https://sourceforge.net/projects/waydroid/files/images/${kind}/${name}/download";
  };
  system = get "system/lineage/waydroid_x86_64" "lineage-20.0-20260927-VANILLA-waydroid_x86_64-system.zip"
    "053552725bf4ae25e2d3f7e6f1947203294aa9d73dc17fe1f3abe646e5d3bd8a";
  vendor = get "vendor/waydroid_x86_64" "lineage-20.0-20260927-MAINLINE-waydroid_x86_64-vendor.zip"
    "d911b8353f6c807b94790b1c41c67e863a9f3dcd1cf3ec0232351398235afd7a";
in
pkgs.runCommand "waydroid-images-lineage-20.0-20260927" { nativeBuildInputs = [ pkgs.unzip ]; passthru.zips = [ system vendor ]; } ''
  mkdir -p $out
  unzip -q ${system} -d $out
  unzip -q ${vendor} -d $out
  ls $out/system.img $out/vendor.img >/dev/null
''
