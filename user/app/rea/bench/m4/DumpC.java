// M4 (AINF-408): write Ghidra's decompiled C for each name=0xVADDR argument (ELF virtual
// address from the unstripped twin) to <outdir>/<name>.c. Args: <outdir> name=0x... ...
//@category REA
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import java.io.FileWriter;

public class DumpC extends GhidraScript {
  @Override
  public void run() throws Exception {
    String[] a = getScriptArgs();
    DecompInterface di = new DecompInterface();
    di.openProgram(currentProgram);
    long base = currentProgram.getImageBase().getOffset();
    for (int i = 1; i < a.length; i++) {
      String[] kv = a[i].split("=");
      long va = Long.parseUnsignedLong(kv[1].substring(2), 16);
      Function f = getFunctionAt(toAddr(va < base ? base + va : va)); // PIE: Ghidra rebases to 0x100000
      String c = "/* no function */\n";
      if (f != null) {
        DecompileResults r = di.decompileFunction(f, 60, monitor);
        if (r != null && r.decompileCompleted()) c = r.getDecompiledFunction().getC();
      }
      try (FileWriter w = new FileWriter(a[0] + "/" + kv[0] + ".c")) { w.write(c); }
    }
    di.dispose();
  }
}
