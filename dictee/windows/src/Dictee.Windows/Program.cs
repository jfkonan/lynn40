namespace Dictee.Windows;

internal static class Program
{
    // « Local\ » : une instance par session Windows (plusieurs utilisateurs connectés peuvent chacun lancer Dictée).
    private const string MutexName = @"Local\Dictee.SingleInstance.7C1F2B";

    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        if (!createdNew)
        {
            MessageBox.Show("Dictée est déjà lancée : son icône se trouve dans la zone de notification, près de l'horloge.",
                "Dictée", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        ApplicationConfiguration.Initialize(); // DPI PerMonitorV2, styles visuels (voir le .csproj)
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) =>
            MessageBox.Show("Erreur inattendue : " + e.Exception.Message, "Dictée", MessageBoxButtons.OK, MessageBoxIcon.Error);
        // Exception sur un autre fil (NAudio, pool de fils, crochet) : le processus s'arrête, mais l'utilisateur sait pourquoi.
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            MessageBox.Show("Dictée doit s'arrêter après une erreur inattendue : " + (e.ExceptionObject as Exception)?.Message,
                "Dictée", MessageBoxButtons.OK, MessageBoxIcon.Error);

        // Contexte de synchronisation installé avant la création des objets qui postent sur le fil d'interface.
        SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
        using var context = new TrayApplicationContext();
        Application.Run(context);
        GC.KeepAlive(mutex);
    }
}
