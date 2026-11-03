using System.ComponentModel;
using Dictee.Core;

namespace Dictee.Windows;

/// <summary>
/// Application de zone de notification : icône (couleur selon l'état), menu, pastille, raccourcis.
/// Possède tous les objets de longue durée et les libère à la fermeture.
/// </summary>
internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly SettingsStore _settings = new();
    private readonly ApiKeyStore _keys = new();
    private readonly HotkeyManager _hotkeys = new();
    private readonly OverlayForm _overlay = new();
    private readonly DictationController _controller;
    private readonly NotifyIcon _tray;
    private readonly ContextMenuStrip _menu;
    private readonly ToolStripMenuItem _stateItem;
    private readonly ToolStripMenuItem _lastItem;
    private readonly Dictionary<DictationState, Icon> _icons = [];
    private SettingsForm? _settingsForm;

    public TrayApplicationContext()
    {
        PurgeLeftoverRecordings();
        _controller = new DictationController(_settings, _keys, _hotkeys, _overlay);
        _controller.StateChanged += RefreshState;

        _stateItem = new ToolStripMenuItem { Enabled = false };
        _lastItem = new ToolStripMenuItem("Dernière transcription");
        _lastItem.Click += async (_, _) => await CopyLastTranscriptAsync();
        var settingsItem = new ToolStripMenuItem("Réglages…", null, (_, _) => ShowSettings());
        settingsItem.Font = new Font(settingsItem.Font, FontStyle.Bold); // action par défaut (double-clic)
        var quitItem = new ToolStripMenuItem("Quitter", null, (_, _) => ExitThread());

        _menu = new ContextMenuStrip();
        _menu.Items.AddRange([_stateItem, new ToolStripSeparator(), _lastItem, settingsItem, new ToolStripSeparator(), quitItem]);
        _menu.Opening += (_, _) => RefreshMenu();

        _tray = new NotifyIcon { ContextMenuStrip = _menu, Text = "Dictée", Visible = true };
        _tray.MouseDoubleClick += (_, e) => { if (e.Button == MouseButtons.Left) ShowSettings(); };
        _settings.Changed += ApplySettings;

        RefreshState();
        try
        {
            _hotkeys.Install();
        }
        catch (Win32Exception ex)
        {
            ShowBalloon("Raccourci clavier indisponible : " + ex.Message +
                        " Un antivirus bloque peut-être la surveillance du clavier.", ToolTipIcon.Error);
        }
        ApplySettings();
        if (_settings.Current.LaunchAtLogin) StartupRegistration.Apply(true); // met à jour le chemin si l'exe a bougé

        var provider = _settings.Current.EffectiveProvider;
        if (!_keys.HasKey(provider))
        {
            ShowBalloon($"Ajoutez votre clé API {TranscriptionProviders.DisplayName(provider)} pour commencer à dicter.", ToolTipIcon.Info);
            ShowSettings();
        }
        else
        {
            var s = _settings.Current;
            ShowBalloon($"Prêt. {HotkeyManager.Describe(s.EffectiveHotkey, s.EffectiveHotkeyMode)} pour dicter.", ToolTipIcon.None);
        }
    }

    /// <summary>
    /// WAV laissés par un plantage ou un arrêt forcé (SPEC §8 : l'audio ne reste pas sur le disque).
    /// Sans risque pour une autre instance : le mutex garantit une seule Dictée par session.
    /// </summary>
    private static void PurgeLeftoverRecordings()
    {
        try
        {
            foreach (var file in Directory.EnumerateFiles(Path.GetTempPath(), "dictee-*.wav"))
                Dictee.Core.TranscriptionPipeline.TryDelete(file);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    private void ApplySettings()
    {
        var error = _controller.ApplySettings();
        if (error is not null) ShowBalloon(error, ToolTipIcon.Warning);
        RefreshState();
    }

    private void RefreshState()
    {
        var state = _controller.State;
        if (!_icons.TryGetValue(state, out var icon))
        {
            icon = TrayIconRenderer.Create(state, Math.Max(16, SystemInformation.SmallIconSize.Width));
            _icons[state] = icon;
        }
        _tray.Icon = icon;
        var text = "Dictée — " + StateLabel(state);
        _tray.Text = text.Length > 127 ? text[..127] : text;
    }

    private string StateLabel(DictationState state) => state switch
    {
        DictationState.Recording => "Écoute…",
        DictationState.Transcribing => "Transcription…",
        DictationState.Error => "Erreur",
        _ => "Prête (" + HotkeyManager.Describe(_settings.Current.EffectiveHotkey, _settings.Current.EffectiveHotkeyMode) + ")",
    };

    private void RefreshMenu()
    {
        var state = _controller.State;
        _stateItem.Text = state == DictationState.Error && _controller.LastError is { } error
            ? "Erreur : " + Shorten(error, 80)
            : StateLabel(state);

        var last = _controller.LastTranscript;
        _lastItem.Enabled = last is not null;
        _lastItem.Text = last is null ? "Dernière transcription : aucune" : $"Dernière transcription (copier) : « {Shorten(last, 40)} »";
        _lastItem.ToolTipText = last is null ? null : Shorten(last, 400);
    }

    private async Task CopyLastTranscriptAsync()
    {
        if (_controller.LastTranscript is not { } text) return;
        try
        {
            await TextInjector.CopyAsync(text);
        }
        catch (System.Runtime.InteropServices.ExternalException)
        {
            ShowBalloon("Le presse-papiers est occupé par une autre application. Réessayez.", ToolTipIcon.Warning);
        }
    }

    private void ShowSettings()
    {
        if (_settingsForm is { IsDisposed: false })
        {
            _settingsForm.WindowState = FormWindowState.Normal;
            _settingsForm.Activate();
            return;
        }
        _settingsForm = new SettingsForm(_settings, _keys);
        _settingsForm.FormClosed += (_, _) => _settingsForm = null;
        _settingsForm.Show();
        _settingsForm.Activate();
    }

    private void ShowBalloon(string text, ToolTipIcon icon)
    {
        _tray.BalloonTipTitle = "Dictée";
        _tray.BalloonTipText = text;
        _tray.BalloonTipIcon = icon;
        _tray.ShowBalloonTip(4000);
    }

    private static string Shorten(string text, int max)
    {
        var single = text.ReplaceLineEndings(" ");
        return single.Length <= max ? single : single[..(max - 1)] + "…";
    }

    protected override void ExitThreadCore()
    {
        _tray.Visible = false; // sinon l'icône reste affichée jusqu'au survol
        base.ExitThreadCore();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _settingsForm?.Dispose();
            _controller.Dispose();
            _hotkeys.Dispose();
            _overlay.Dispose();
            _tray.Dispose();
            _menu.Dispose();
            foreach (var icon in _icons.Values) icon.Dispose();
        }
        base.Dispose(disposing);
    }
}
