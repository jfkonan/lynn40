using Microsoft.Win32;

namespace Dictee.Windows;

/// <summary>Lancement à l'ouverture de session via HKCU\Software\Microsoft\Windows\CurrentVersion\Run.</summary>
internal static class StartupRegistration
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Dictee";

    /// <summary>Inscrit ou retire l'exe courant. Renvoie un message d'erreur, ou null si tout va bien.</summary>
    public static string? Apply(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
            if (enabled)
            {
                var exe = Environment.ProcessPath;
                if (string.IsNullOrEmpty(exe)) return "Chemin de Dictée introuvable : lancement au démarrage non activé.";
                var command = $"\"{exe}\"";
                // Réécrit aussi la valeur si l'exe a été déplacé depuis.
                if (!string.Equals(key.GetValue(ValueName) as string, command, StringComparison.OrdinalIgnoreCase))
                    key.SetValue(ValueName, command, RegistryValueKind.String);
            }
            else
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }
            return null;
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            return "Impossible de modifier le lancement au démarrage : " + ex.Message;
        }
    }
}
