// M1 (AINF-408): dump every function Ghidra found after auto-analysis — entry offset,
// name, symbol source, thunk flag — and try to decompile each one (30 s cap), timing it.
// Usage: analyzeHeadless … -postScript BenchDump.java <out.json>
//@category REA
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import java.io.FileWriter;
import java.io.Writer;

public class BenchDump extends GhidraScript {
  private static String esc(String s) {
    StringBuilder b = new StringBuilder(s.length() + 8);
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      if (c == '"' || c == '\\') b.append('\\').append(c);
      else if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
      else b.append(c);
    }
    return b.toString();
  }

  @Override
  public void run() throws Exception {
    String out = getScriptArgs()[0];
    DecompInterface di = new DecompInterface();
    di.openProgram(currentProgram);
    long base = currentProgram.getImageBase().getOffset();
    long t0 = System.nanoTime();
    int fails = 0, total = 0;
    try (Writer w = new FileWriter(out)) {
      w.write("{\"image_base\":" + base + ",\"functions\":[");
      FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
      boolean first = true;
      while (it.hasNext() && !monitor.isCancelled()) {
        Function f = it.next();
        if (f.isExternal()) continue;
        total++;
        boolean ok = true;
        long ft = System.nanoTime();
        if (!f.isThunk()) {
          DecompileResults r = di.decompileFunction(f, 30, monitor);
          ok = r != null && r.decompileCompleted();
          if (!ok) fails++;
        }
        long ms = (System.nanoTime() - ft) / 1_000_000;
        if (!first) w.write(',');
        first = false;
        w.write("{\"off\":" + f.getEntryPoint().getOffset()
            + ",\"name\":\"" + esc(f.getName(true)) + "\""
            + ",\"src\":\"" + f.getSymbol().getSource() + "\""
            + ",\"thunk\":" + f.isThunk()
            + ",\"ok\":" + ok + ",\"ms\":" + ms + "}");
      }
      w.write("],\"total\":" + total + ",\"decompile_fail\":" + fails
          + ",\"decompile_ms\":" + (System.nanoTime() - t0) / 1_000_000 + "}");
    }
    di.dispose();
  }
}
