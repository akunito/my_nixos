// M2 diagnosis (AINF-408): for each name=0xADDR argument, hash the function at ADDR in the
// current program and print it next to every FID record whose name contains NAME, and any
// record sharing the program function's full hash. Why a known library function does not
// match: different full hash (code differs), or the same hash with a score below threshold.
//@category REA
import ghidra.app.script.GhidraScript;
import ghidra.feature.fid.db.FidFileManager;
import ghidra.feature.fid.db.FidQueryService;
import ghidra.feature.fid.db.FunctionRecord;
import ghidra.feature.fid.hash.FidHashQuad;
import ghidra.feature.fid.service.FidService;
import ghidra.program.model.listing.Function;

public class FidDiag extends GhidraScript {
  @Override
  public void run() throws Exception {
    FidService svc = new FidService();
    FidQueryService q = FidFileManager.getInstance().openFidQueryService(currentProgram.getLanguage(), false);
    try {
      for (String arg : getScriptArgs()) {
        String[] kv = arg.split("=");
        Function f = getFunctionAt(toAddr(Long.parseUnsignedLong(kv[1].substring(2), 16)));
        if (f == null) { println("DIAG " + kv[0] + ": no function at " + kv[1]); continue; }
        FidHashQuad h = svc.hashFunction(f);
        if (h == null) { println("DIAG " + kv[0] + ": not hashable (too short?) name=" + f.getName()); continue; }
        println(String.format("DIAG %s prog name=%s cu=%d full=%016x spec=%016x+%d",
            kv[0], f.getName(), h.getCodeUnitSize(), h.getFullHash(), h.getSpecificHash(), h.getSpecificHashAdditionalSize()));
        for (FunctionRecord r : q.findFunctionsByNameSubstring(kv[0])) {
          if (!r.getName().equals(kv[0]) && !r.getName().equals("__libc_" + kv[0]) && !r.getName().equals("_IO_" + kv[0])) continue;
          println(String.format("DIAG %s   db name=%s cu=%d full=%016x spec=%016x+%d lib=%s auto=%s%s%s%s",
              kv[0], r.getName(), r.getCodeUnitSize(), r.getFullHash(), r.getSpecificHash(), r.getSpecificHashAdditionalSize(),
              q.getLibraryForFunction(r).getLibraryFamilyName(),
              r.autoPass() ? "P" : "", r.autoFail() ? "F" : "", r.isForceSpecific() ? "S" : "", r.isForceRelation() ? "R" : ""));
        }
        for (FunctionRecord r : q.findFunctionsByFullHash(h.getFullHash())) {
          println("DIAG " + kv[0] + "   same-full-hash: " + r.getName() + " lib=" + q.getLibraryForFunction(r).getLibraryFamilyName());
        }
      }
    }
    finally {
      q.close();
    }
  }
}
