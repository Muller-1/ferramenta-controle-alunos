import java.lang.instrument.Instrumentation;

/** Agente do lab: dá operador a UM jogador conectado no mundo aberto em LAN deste PC (o /op não existe em mundo LAN).
 *  Uso: java --add-modules jdk.attach -cp lab-op.jar Anexar PID lab-op.jar NOME */
public class LabOp {
    /** op:NOME — dá operador a um jogador conectado no mundo aberto (o /op não existe em mundo LAN). */
    static void darOp(String nome, Instrumentation inst) throws Exception {
        Class<?> mcC = null;
        for (Class<?> c : inst.getAllLoadedClasses()) if (c.getName().equals("net.minecraft.client.Minecraft")) { mcC = c; break; }
        if (mcC == null) { System.out.println("[lab-agente] jogo não encontrado"); return; }
        Object mc = mcC.getMethod("getInstance").invoke(null);
        Object srv = mcC.getMethod("getSingleplayerServer").invoke(mc);
        if (srv == null) { System.out.println("[lab-agente] nenhum mundo aberto neste PC"); return; }
        Object pl = srv.getClass().getMethod("getPlayerList").invoke(srv);
        Object sp = pl.getClass().getMethod("getPlayerByName", String.class).invoke(pl, nome);
        if (sp == null) { System.out.println("[lab-agente] jogador " + nome + " não está conectado"); return; }
        Object nid = sp.getClass().getMethod("nameAndId").invoke(sp);
        java.lang.reflect.Method op = pl.getClass().getMethod("op", nid.getClass());
        java.lang.reflect.Method isOp = pl.getClass().getMethod("isOp", nid.getClass());
        java.util.concurrent.CompletableFuture<Object> f = new java.util.concurrent.CompletableFuture<>();
        srv.getClass().getMethod("executeIfPossible", Runnable.class).invoke(srv, (Runnable) () -> {
            try { op.invoke(pl, nid); f.complete(isOp.invoke(pl, nid)); } catch (Throwable x) { f.completeExceptionally(x); }
        });
        System.out.println("[lab-agente] operador " + nome + ": " + f.get(10, java.util.concurrent.TimeUnit.SECONDS));
    }

    public static void agentmain(String nome, Instrumentation inst) {
        try { darOp(nome == null ? "" : nome.trim(), inst); }
        catch (Throwable x) { System.out.println("[lab-agente] ERRO: " + x); }
    }
}
