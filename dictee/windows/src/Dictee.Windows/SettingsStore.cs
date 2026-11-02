using Dictee.Core;

namespace Dictee.Windows;

/// <summary>Réglages en mémoire, lus et écrits dans %APPDATA%\Dictee\settings.json.</summary>
internal sealed class SettingsStore
{
    private readonly string _path;

    public SettingsStore(string? path = null)
    {
        _path = path ?? AppPaths.SettingsFile;
        Current = DicteeSettings.Load(_path);
    }

    /// <summary>Ne pas modifier directement : passer par <see cref="Save"/>.</summary>
    public DicteeSettings Current { get; private set; }

    public event Action? Changed;

    public void Save(DicteeSettings settings)
    {
        settings.Save(_path);
        Current = settings.Clone();
        Changed?.Invoke();
    }
}
