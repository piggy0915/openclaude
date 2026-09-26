// Decompile functions whose name matches a regex, print C to console.
// @category Hermes
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.util.task.ConsoleTaskMonitor;
import java.util.regex.Pattern;

public class DecompileSelected extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        String regex = (args != null && args.length > 0 && args[0].length() > 0) ? args[0] : "main";
        int max = (args != null && args.length > 1) ? Integer.parseInt(args[1]) : 5;
        int chars = (args != null && args.length > 2) ? Integer.parseInt(args[2]) : 1200;

        Pattern p = Pattern.compile(regex);
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);

        println("[hermes] program=" + currentProgram.getName() + " pattern=" + regex);
        int matched = 0;
        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        while (it.hasNext() && matched < max) {
            Function f = it.next();
            if (!p.matcher(f.getName()).find()) continue;
            matched++;
            println("[hermes] FUNC " + f.getName() + " @ " + f.getEntryPoint());
            DecompileResults r = di.decompileFunction(f, 60, new ConsoleTaskMonitor());
            if (r != null && r.getDecompiledFunction() != null) {
                String c = r.getDecompiledFunction().getC();
                println(c.length() > chars ? c.substring(0, chars) + "\n... [truncated]" : c);
            } else {
                println("  (decompile failed or timed out)");
            }
        }
        println("[hermes] matched_functions=" + matched);
    }
}
