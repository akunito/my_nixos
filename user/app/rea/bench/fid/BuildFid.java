// M2 (AINF-408): build one read-only FID database (.fidbf) from every program in the
// current headless project (the members of a static library imported with -recursive).
// Args: <family> <version> <variant> <out.fidbf> <languageId e.g. x86:LE:64:default>
//@category REA
import ghidra.app.script.GhidraScript;
import ghidra.feature.fid.db.FidDB;
import ghidra.feature.fid.db.FidFile;
import ghidra.feature.fid.db.FidFileManager;
import ghidra.feature.fid.service.FidPopulateResult;
import ghidra.feature.fid.service.FidService;
import ghidra.framework.model.DomainFile;
import ghidra.framework.model.DomainFolder;
import ghidra.program.model.lang.LanguageID;
import java.io.File;
import java.util.ArrayList;
import java.util.List;

public class BuildFid extends GhidraScript {
  private static void collect(DomainFolder f, List<DomainFile> out) {
    for (DomainFile df : f.getFiles()) {
      if ("Program".equals(df.getContentType())) out.add(df);
    }
    for (DomainFolder sub : f.getFolders()) collect(sub, out);
  }

  @Override
  public void run() throws Exception {
    String[] a = getScriptArgs();
    File packed = new File(a[3] + ".fidb");
    FidFileManager fm = FidFileManager.getInstance();
    fm.createNewFidDatabase(packed);
    FidFile ff = fm.addUserFidFile(packed);
    List<DomainFile> progs = new ArrayList<>();
    collect(state.getProject().getProjectData().getRootFolder(), progs);
    try (FidDB db = ff.getFidDB(true)) {
      FidPopulateResult r = new FidService().createNewLibraryFromPrograms(db, a[0], a[1], a[2],
          progs, null, new LanguageID(a[4]), null, null, monitor);
      println("REA-FID " + a[0] + " " + a[1] + ": programs=" + progs.size() + " attempted="
          + r.getTotalAttempted() + " added=" + r.getTotalAdded() + " excluded="
          + r.getTotalExcluded() + " failures=" + r.getFailures());
      db.saveDatabase("rea fid " + a[0], monitor);
    }
    // "Can't save during transaction" when exported from the update handle (measured):
    // reopen read-only, as FidDebugPlugin does.
    try (FidDB ro = ff.getFidDB(false)) {
      ro.saveRawDatabaseFile(new File(a[3]), monitor);
    }
  }
}
