import com.sun.tools.attach.VirtualMachine;
/** java -cp agente.jar Anexar PID agente.jar LIMITE */
public class Anexar {
    public static void main(String[] a) throws Exception {
        VirtualMachine vm = VirtualMachine.attach(a[0]);
        try { vm.loadAgent(a[1], a[2]); System.out.println("agente carregado em " + a[0]); } finally { vm.detach(); }
    }
}
