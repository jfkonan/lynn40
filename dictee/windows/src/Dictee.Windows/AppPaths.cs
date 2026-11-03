namespace Dictee.Windows;

/// <summary>Emplacements des fichiers de Dictée : %APPDATA%\Dictee\.</summary>
internal static class AppPaths
{
    public static string DataDirectory { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Dictee");

    public static string SettingsFile => Path.Combine(DataDirectory, "settings.json");
}
