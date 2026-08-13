// Sine mod-manager bootloader.
//
// Vendored verbatim from sineorg/bootloader @ d3914368981fe71d0829f03dbc7990338d9f5a6d
// (program/config.js, MPL-2.0). Appended to $libDir/mozilla.cfg by wrapFirefox's
// `extraPrefsFiles`, which is the autoconfig script Zen evaluates at startup.
//
// All it does: register the profile's chrome/utils/chrome.manifest and import
// Sine's ES module from there. Everything else lives in the (mutable) profile.
// Re-check this file against upstream whenever Sine is upgraded.
if (!Services.appinfo.inSafeMode) {
  try {
    const cmanifest = Services.dirsvc.get("UChrm", Ci.nsIFile);
    cmanifest.append("utils");
    cmanifest.append("chrome.manifest");

    if (cmanifest.exists()) {
      Components.manager.QueryInterface(Ci.nsIComponentRegistrar).autoRegister(cmanifest);
      ChromeUtils.importESModule("chrome://userscripts/content/sine.sys.mjs");
    }
  } catch (err) {}
}
