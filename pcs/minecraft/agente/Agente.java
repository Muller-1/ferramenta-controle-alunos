import java.lang.classfile.*;
import java.lang.classfile.instruction.ConstantInstruction;
import java.lang.instrument.*;
import java.security.ProtectionDomain;

/** Agente do lab: muda o limite de jogadores de um mundo aberto em LAN (IntegratedServer.getMaxPlayers, fixo em 8) sem reiniciar. */
public class Agente {
    static final String ALVO = "net.minecraft.client.server.IntegratedServer";

    static byte[] patch(byte[] b, int n, ClassLoader cl) {
        ClassFile cf = ClassFile.of(ClassFile.ClassHierarchyResolverOption.of(
                ClassHierarchyResolver.defaultResolver().orElse(ClassHierarchyResolver.ofClassLoading(cl))));
        ClassModel cm = cf.parse(b);
        return cf.transformClass(cm, ClassTransform.transformingMethods(
                mm -> mm.methodName().equalsString("getMaxPlayers") && mm.methodType().equalsString("()I"),
                MethodTransform.transformingCode((cb, e) -> {
                    if (e instanceof ConstantInstruction ci && ci.constantValue() instanceof Integer) cb.loadConstant(n);
                    else cb.with(e);
                })));
    }

    public static void agentmain(String args, Instrumentation inst) {
        try {
            int n = Integer.parseInt(args == null || args.isBlank() ? "25" : args.trim());
            if (n < 1 || n > 100) throw new IllegalArgumentException("limite fora de 1..100");
            Class<?> alvo = null;
            for (Class<?> c : inst.getAllLoadedClasses()) if (c.getName().equals(ALVO)) { alvo = c; break; }
            if (alvo == null) { System.out.println("[lab-agente] nenhum mundo aberto (classe não carregada)"); return; }
            final Class<?> A = alvo;
            final Throwable[] erro = new Throwable[1];
            ClassFileTransformer t = new ClassFileTransformer() {
                public byte[] transform(Module m, ClassLoader l, String name, Class<?> cls, ProtectionDomain pd, byte[] b) {
                    if (cls != A) return null;
                    try { return patch(b, n, A.getClassLoader()); } catch (Throwable x) { erro[0] = x; return null; }
                }
            };
            inst.addTransformer(t, true);
            try { inst.retransformClasses(A); } finally { inst.removeTransformer(t); }
            if (erro[0] != null) { System.out.println("[lab-agente] ERRO na transformação: " + erro[0]); return; }
            Class<?> mcC = Class.forName("net.minecraft.client.Minecraft", true, A.getClassLoader());
            Object mc = mcC.getMethod("getInstance").invoke(null);
            Object srv = mcC.getMethod("getSingleplayerServer").invoke(mc);
            System.out.println("[lab-agente] limite agora = " + (srv == null ? "(sem mundo aberto)" : A.getMethod("getMaxPlayers").invoke(srv)));
        } catch (Throwable x) {
            System.out.println("[lab-agente] ERRO: " + x);
        }
    }

    /** Teste offline: java Agente teste ENTRADA.class SAIDA.class N */
    public static void main(String[] a) throws Exception {
        byte[] b = java.nio.file.Files.readAllBytes(java.nio.file.Path.of(a[1]));
        java.nio.file.Files.write(java.nio.file.Path.of(a[2]), patch(b, Integer.parseInt(a[3]), Agente.class.getClassLoader()));
    }
}
