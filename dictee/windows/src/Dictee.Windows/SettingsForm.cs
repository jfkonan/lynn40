using System.Diagnostics;
using Dictee.Core;

namespace Dictee.Windows;

/// <summary>Fenêtre « Réglages de Dictée », construite en code (pas de concepteur ni de fichier .resx).</summary>
internal sealed class SettingsForm : Form
{
    private readonly SettingsStore _settings;
    private readonly ApiKeyStore _keys;

    private readonly Label _keyStatus = new() { AutoSize = true };
    private readonly TextBox _keyInput = new() { UseSystemPasswordChar = true, PlaceholderText = "Collez une nouvelle clé (sk-…)", Dock = DockStyle.Fill };
    private readonly Button _deleteKey = new() { Text = "Supprimer la clé", AutoSize = true };
    private readonly ComboBox _model = new() { DropDownStyle = ComboBoxStyle.DropDown, Dock = DockStyle.Fill };
    private readonly TextBox _language = new() { Width = 80 };
    private readonly TextBox _vocabulary = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Height = 72, Dock = DockStyle.Fill, AcceptsReturn = true };
    private readonly CheckBox _cleanup = new() { Text = "Nettoyer le texte (ponctuation, hésitations) avec un second appel", AutoSize = true };
    private readonly ComboBox _cleanupModel = new() { DropDownStyle = ComboBoxStyle.DropDown, Dock = DockStyle.Fill };
    private readonly ComboBox _hotkey = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    private readonly ComboBox _mode = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    private readonly Label _hotkeyNote = new() { AutoSize = true, ForeColor = SystemColors.GrayText };
    private readonly CheckBox _sounds = new() { Text = "Sons de début et de fin", AutoSize = true };
    private readonly CheckBox _restoreClipboard = new() { Text = "Restaurer le presse-papiers après l'insertion", AutoSize = true };
    private readonly CheckBox _launchAtLogin = new() { Text = "Lancer Dictée à l'ouverture de session", AutoSize = true };

    private static readonly (string Id, string Label)[] Hotkeys =
    [
        (HotkeyIds.RightCtrl, "Ctrl droit"),
        (HotkeyIds.RightAlt, "Alt droit (= AltGr sur clavier AZERTY)"),
        (HotkeyIds.F8, "F8"),
        (HotkeyIds.CtrlShiftSpace, "Ctrl+Maj+Espace"),
    ];

    private static readonly (string Id, string Label)[] Modes =
    [
        (HotkeyModes.Hold, "Maintenir pour parler"),
        (HotkeyModes.Toggle, "Appuyer pour démarrer, appuyer pour arrêter"),
    ];

    public SettingsForm(SettingsStore settings, ApiKeyStore keys)
    {
        _settings = settings;
        _keys = keys;

        Text = "Réglages de Dictée";
        Font = SystemFonts.MessageBoxFont ?? Control.DefaultFont;
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoScaleDimensions = new SizeF(96f, 96f);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ShowInTaskbar = true;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Padding = new Padding(12);

        // Largeurs minimales explicites : la fenêtre s'ajuste à son contenu (AutoSize) et se met à l'échelle avec le DPI.
        _keyInput.MinimumSize = new Size(340, 0);
        _model.MinimumSize = new Size(300, 0);
        _vocabulary.MinimumSize = new Size(420, 72);
        _cleanupModel.MinimumSize = new Size(300, 0);
        _hotkey.MinimumSize = new Size(300, 0);
        _mode.MinimumSize = new Size(300, 0);

        var root = new TableLayoutPanel { ColumnCount = 1, AutoSize = true, Dock = DockStyle.Fill, AutoSizeMode = AutoSizeMode.GrowAndShrink };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.Controls.Add(BuildKeyGroup());
        root.Controls.Add(BuildTranscriptionGroup());
        root.Controls.Add(BuildHotkeyGroup());
        root.Controls.Add(BuildBehaviorGroup());
        root.Controls.Add(BuildButtons());
        Controls.Add(root);

        LoadValues();
    }

    // ---- Construction ----

    private GroupBox BuildKeyGroup()
    {
        var link = new LinkLabel { Text = "Obtenir une clé sur platform.openai.com", AutoSize = true };
        link.LinkClicked += (_, _) => OpenUrl("https://platform.openai.com/api-keys");
        _deleteKey.Click += (_, _) =>
        {
            if (MessageBox.Show(this, "Supprimer la clé API enregistrée sur cet ordinateur ?", "Dictée",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            _keys.Delete();
            RefreshKeyStatus();
        };

        var grid = Grid(2);
        grid.Controls.Add(_keyStatus, 0, 0);
        grid.SetColumnSpan(_keyStatus, 2);
        grid.Controls.Add(_keyInput, 0, 1);
        grid.Controls.Add(_deleteKey, 1, 1);
        grid.Controls.Add(Note("Chiffrée par Windows (DPAPI) pour votre seul compte, dans %APPDATA%\\Dictee."), 0, 2);
        grid.Controls.Add(link, 0, 3);
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        return Group("Clé API OpenAI", grid);
    }

    private GroupBox BuildTranscriptionGroup()
    {
        _model.Items.AddRange(DicteeSettings.ModelChoices.Cast<object>().ToArray());
        _cleanupModel.Items.AddRange(DicteeSettings.CleanupModelChoices.Cast<object>().ToArray());
        _cleanup.CheckedChanged += (_, _) => _cleanupModel.Enabled = _cleanup.Checked;

        var grid = Grid(2);
        AddRow(grid, "Modèle :", _model);
        var languageRow = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = Padding.Empty };
        languageRow.Controls.Add(_language);
        languageRow.Controls.Add(Note("code ISO (fr, en…) ; vide = détection automatique"));
        AddRow(grid, "Langue :", languageRow);
        AddRow(grid, "Vocabulaire :", _vocabulary);
        var cleanupRow = grid.RowCount++;
        grid.Controls.Add(_cleanup, 0, cleanupRow);
        grid.SetColumnSpan(_cleanup, 2);
        AddRow(grid, "Modèle de nettoyage :", _cleanupModel);
        return Group("Transcription", grid);
    }

    private GroupBox BuildHotkeyGroup()
    {
        foreach (var (_, label) in Hotkeys) _hotkey.Items.Add(label);
        foreach (var (_, label) in Modes) _mode.Items.Add(label);
        _hotkey.SelectedIndexChanged += (_, _) => UpdateHotkeyNote();
        _mode.SelectedIndexChanged += (_, _) => UpdateHotkeyNote();

        var grid = Grid(2);
        AddRow(grid, "Raccourci :", _hotkey);
        AddRow(grid, "Mode :", _mode);
        var noteRow = grid.RowCount++;
        grid.Controls.Add(_hotkeyNote, 0, noteRow);
        grid.SetColumnSpan(_hotkeyNote, 2);
        var esc = Note("Échap pendant l'enregistrement annule la dictée.");
        var escRow = grid.RowCount++;
        grid.Controls.Add(esc, 0, escRow);
        grid.SetColumnSpan(esc, 2);
        return Group("Raccourci", grid);
    }

    private GroupBox BuildBehaviorGroup()
    {
        var panel = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Fill, WrapContents = false };
        panel.Controls.Add(_sounds);
        panel.Controls.Add(_restoreClipboard);
        panel.Controls.Add(_launchAtLogin);
        return Group("Comportement", panel);
    }

    private FlowLayoutPanel BuildButtons()
    {
        var save = new Button { Text = "Enregistrer", AutoSize = true, DialogResult = DialogResult.None };
        var cancel = new Button { Text = "Annuler", AutoSize = true };
        save.Click += (_, _) => SaveAndClose();
        // Fenêtre non modale (Show) : DialogResult ne la fermerait pas. Échap passe aussi par ce clic (CancelButton).
        cancel.Click += (_, _) => Close();
        AcceptButton = save;
        CancelButton = cancel;
        var panel = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 8, 0, 0) };
        panel.Controls.Add(cancel);
        panel.Controls.Add(save);
        return panel;
    }

    // ---- Valeurs ----

    private void LoadValues()
    {
        var s = _settings.Current;
        RefreshKeyStatus();
        _model.Text = s.EffectiveModel;
        _language.Text = s.Language;
        _vocabulary.Text = s.Vocabulary;
        _cleanup.Checked = s.CleanupEnabled;
        _cleanupModel.Text = s.EffectiveCleanupModel;
        _cleanupModel.Enabled = s.CleanupEnabled;
        _hotkey.SelectedIndex = Math.Max(0, Array.FindIndex(Hotkeys, h => h.Id == s.EffectiveHotkey));
        _mode.SelectedIndex = Math.Max(0, Array.FindIndex(Modes, m => m.Id == s.EffectiveHotkeyMode));
        _sounds.Checked = s.SoundsEnabled;
        _restoreClipboard.Checked = s.RestoreClipboard;
        _launchAtLogin.Checked = s.LaunchAtLogin;
        UpdateHotkeyNote();
    }

    private void RefreshKeyStatus()
    {
        var hint = ApiKeyHint.Preview(_keys.Load());
        _keyStatus.Text = hint is null ? "Aucune clé enregistrée." : $"Clé enregistrée : {hint}";
        _deleteKey.Enabled = hint is not null;
    }

    private void UpdateHotkeyNote()
    {
        var hotkey = Hotkeys[Math.Max(0, _hotkey.SelectedIndex)].Id;
        var combination = HotkeyIds.IsCombination(hotkey);
        _mode.Enabled = !combination;
        if (combination) _mode.SelectedIndex = Array.FindIndex(Modes, m => m.Id == HotkeyModes.Toggle);

        _hotkeyNote.Text = hotkey switch
        {
            HotkeyIds.RightAlt => "Attention : sur un clavier AZERTY, Alt droit est la touche AltGr (@, #, €…).\nUn AltGr+touche annule la dictée, mais préférez Ctrl droit ou F8.",
            HotkeyIds.CtrlShiftSpace => "Une combinaison fonctionne toujours en mode « appuyer pour démarrer, appuyer pour arrêter ».",
            HotkeyIds.F8 => "F8 n'est plus transmise aux autres applications tant que ce raccourci est actif.",
            _ => "Ctrl droit + une autre touche (Ctrl+C…) garde son effet habituel et annule la dictée.",
        };
    }

    private void SaveAndClose()
    {
        var newKey = _keyInput.Text.Trim();
        if (newKey.Length > 0 && (newKey.Length < 20 || newKey.Any(char.IsWhiteSpace)))
        {
            MessageBox.Show(this, "Cette clé ne ressemble pas à une clé API OpenAI (elle commence en général par « sk- »).",
                "Dictée", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            _keyInput.Focus();
            return;
        }

        var s = _settings.Current.Clone();
        s.Model = string.IsNullOrWhiteSpace(_model.Text) ? DicteeSettings.DefaultModel : _model.Text.Trim();
        s.Language = _language.Text.Trim();
        s.Vocabulary = _vocabulary.Text.Trim();
        s.CleanupEnabled = _cleanup.Checked;
        s.CleanupModel = string.IsNullOrWhiteSpace(_cleanupModel.Text) ? DicteeSettings.DefaultCleanupModel : _cleanupModel.Text.Trim();
        s.Hotkey = Hotkeys[Math.Max(0, _hotkey.SelectedIndex)].Id;
        s.HotkeyMode = Modes[Math.Max(0, _mode.SelectedIndex)].Id;
        s.SoundsEnabled = _sounds.Checked;
        s.RestoreClipboard = _restoreClipboard.Checked;
        s.LaunchAtLogin = _launchAtLogin.Checked;

        try
        {
            if (newKey.Length > 0) _keys.Save(newKey);
            _settings.Save(s);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.Cryptography.CryptographicException)
        {
            MessageBox.Show(this, "Impossible d'enregistrer les réglages : " + ex.Message, "Dictée",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        var startupError = StartupRegistration.Apply(s.LaunchAtLogin);
        if (startupError is not null)
            MessageBox.Show(this, startupError, "Dictée", MessageBoxButtons.OK, MessageBoxIcon.Warning);

        Close();
    }

    // ---- Aides de mise en page ----

    private static TableLayoutPanel Grid(int columns) =>
        new() { ColumnCount = columns, AutoSize = true, Dock = DockStyle.Fill, AutoSizeMode = AutoSizeMode.GrowAndShrink };

    private static void AddRow(TableLayoutPanel grid, string label, Control control)
    {
        if (grid.ColumnStyles.Count == 0)
        {
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        }
        var row = grid.RowCount++;
        grid.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(3, 7, 3, 3) }, 0, row);
        grid.Controls.Add(control, 1, row);
    }

    private static Label Note(string text) =>
        new() { Text = text, AutoSize = true, ForeColor = SystemColors.GrayText, Anchor = AnchorStyles.Left, Margin = new Padding(3, 6, 3, 3) };

    private static GroupBox Group(string title, Control content)
    {
        var box = new GroupBox { Text = title, AutoSize = true, Dock = DockStyle.Fill, Padding = new Padding(10), Margin = new Padding(0, 0, 0, 8) };
        box.Controls.Add(content);
        return box;
    }

    private static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception) { /* pas de navigateur par défaut : sans gravité */ }
    }
}
