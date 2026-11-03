using System.Diagnostics;
using Dictee.Core;

namespace Dictee.Windows;

/// <summary>Fenêtre « Réglages de Dictée », construite en code (pas de concepteur ni de fichier .resx).</summary>
internal sealed class SettingsForm : Form
{
    private readonly SettingsStore _settings;
    private readonly ApiKeyStore _keys;

    private readonly ComboBox _provider = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    private readonly ComboBox _model = new() { DropDownStyle = ComboBoxStyle.DropDown, Dock = DockStyle.Fill };
    private readonly ComboBox _azureRegion = new() { DropDownStyle = ComboBoxStyle.DropDown, Width = 160 };
    private readonly FlowLayoutPanel _azureRegionRow = new() { AutoSize = true, WrapContents = false, Margin = Padding.Empty };
    private Label? _azureRegionLabel;
    private readonly TextBox _language = new() { Width = 80 };
    private readonly TextBox _vocabulary = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Height = 72, Dock = DockStyle.Fill, AcceptsReturn = true };
    private readonly CheckBox _cleanup = new() { Text = "Nettoyer le texte (ponctuation, hésitations) avec un second appel à OpenAI", AutoSize = true };
    private readonly ComboBox _cleanupModel = new() { DropDownStyle = ComboBoxStyle.DropDown, Dock = DockStyle.Fill };
    private readonly ComboBox _hotkey = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    private readonly ComboBox _mode = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    private readonly Label _hotkeyNote = new() { AutoSize = true, ForeColor = SystemColors.GrayText };
    private readonly CheckBox _sounds = new() { Text = "Sons de début et de fin", AutoSize = true };
    private readonly CheckBox _restoreClipboard = new() { Text = "Restaurer le presse-papiers après l'insertion", AutoSize = true };
    private readonly CheckBox _launchAtLogin = new() { Text = "Lancer Dictée à l'ouverture de session", AutoSize = true };

    /// <summary>Une ligne de clé par fournisseur : aperçu, saisie d'une nouvelle clé, suppression.</summary>
    private sealed record KeyRow(TranscriptionProvider Provider, Label Status, TextBox Input, Button Delete);

    private readonly KeyRow[] _keyRows;

    // Modèle saisi pour chaque fournisseur : la liste « Modèle » n'affiche que celui du fournisseur choisi.
    private readonly Dictionary<TranscriptionProvider, string> _modelTexts = [];
    private TranscriptionProvider _modelShownFor;

    private static readonly (TranscriptionProvider Id, string Label)[] Providers =
    [
        (TranscriptionProvider.OpenAI, "OpenAI"),
        (TranscriptionProvider.Mistral, "Mistral (Voxtral)"),
        (TranscriptionProvider.Microsoft, "Microsoft (Azure AI Speech, MAI-Transcribe-2)"),
    ];

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
        _keyRows = TranscriptionProviders.All.Select(p => new KeyRow(p,
            new Label { AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(3, 8, 3, 3) },
            new TextBox { UseSystemPasswordChar = true, PlaceholderText = KeyPlaceholder(p), Dock = DockStyle.Fill, MinimumSize = new Size(340, 0) },
            new Button { Text = "Supprimer la clé", AutoSize = true })).ToArray();

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
        _provider.MinimumSize = new Size(300, 0);
        _model.MinimumSize = new Size(300, 0);
        _vocabulary.MinimumSize = new Size(420, 72);
        _cleanupModel.MinimumSize = new Size(300, 0);
        _hotkey.MinimumSize = new Size(300, 0);
        _mode.MinimumSize = new Size(300, 0);

        var root = new TableLayoutPanel { ColumnCount = 1, AutoSize = true, Dock = DockStyle.Fill, AutoSizeMode = AutoSizeMode.GrowAndShrink };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.Controls.Add(BuildTranscriptionGroup());
        root.Controls.Add(BuildKeyGroup());
        root.Controls.Add(BuildHotkeyGroup());
        root.Controls.Add(BuildBehaviorGroup());
        root.Controls.Add(BuildButtons());
        Controls.Add(root);

        LoadValues();
    }

    // ---- Construction ----

    private GroupBox BuildKeyGroup()
    {
        var grid = Grid(2);
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        foreach (var row in _keyRows)
        {
            var provider = row.Provider;
            row.Delete.Click += (_, _) =>
            {
                if (MessageBox.Show(this, $"Supprimer la clé API {ProviderName(provider)} enregistrée sur cet ordinateur ?", "Dictée",
                        MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                _keys.Delete(provider);
                RefreshKeyStatus();
            };
            var (linkText, url) = KeyLink(provider);
            var link = new LinkLabel { Text = linkText, AutoSize = true, Margin = new Padding(3, 0, 3, 6) };
            link.LinkClicked += (_, _) => OpenUrl(url);

            var statusRow = grid.RowCount++;
            grid.Controls.Add(row.Status, 0, statusRow);
            grid.SetColumnSpan(row.Status, 2);
            var inputRow = grid.RowCount++;
            grid.Controls.Add(row.Input, 0, inputRow);
            grid.Controls.Add(row.Delete, 1, inputRow);
            var linkRow = grid.RowCount++;
            grid.Controls.Add(link, 0, linkRow);
            grid.SetColumnSpan(link, 2);
        }
        var note = Note("Une clé par fournisseur, chiffrée par Windows (DPAPI) pour votre seul compte, dans %APPDATA%\\Dictee.\n" +
                        "Le nettoyage du texte utilise toujours la clé OpenAI : sans elle, il est sauté.");
        var noteRow = grid.RowCount++;
        grid.Controls.Add(note, 0, noteRow);
        grid.SetColumnSpan(note, 2);
        return Group("Clés API", grid);
    }

    private GroupBox BuildTranscriptionGroup()
    {
        foreach (var (_, label) in Providers) _provider.Items.Add(label);
        _provider.SelectedIndexChanged += (_, _) => OnProviderChanged();
        _azureRegion.Items.AddRange(DicteeSettings.AzureRegionChoices.Cast<object>().ToArray());
        _azureRegionRow.Controls.Add(_azureRegion);
        _azureRegionRow.Controls.Add(Note("région de votre ressource Azure Speech"));
        _cleanupModel.Items.AddRange(DicteeSettings.CleanupModelChoices.Cast<object>().ToArray());
        _cleanup.CheckedChanged += (_, _) => _cleanupModel.Enabled = _cleanup.Checked;

        var grid = Grid(2);
        AddRow(grid, "Fournisseur :", _provider);
        AddNoteRow(grid, Note("OpenAI : fournisseur par défaut.\n" +
                              "Mistral : hébergé dans l'UE.\n" +
                              "Microsoft : preview, prix promotionnel jusqu'au 31/12/2026."));
        AddRow(grid, "Modèle :", _model);
        _azureRegionLabel = AddRow(grid, "Région Azure :", _azureRegionRow);
        var languageRow = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = Padding.Empty };
        languageRow.Controls.Add(_language);
        languageRow.Controls.Add(Note("code ISO (fr, en…) ; vide = détection automatique"));
        AddRow(grid, "Langue :", languageRow);
        AddRow(grid, "Vocabulaire :", _vocabulary);
        AddNoteRow(grid, Note("Termes séparés par des virgules, points-virgules ou retours à la ligne\n" +
                              "(Mistral et Microsoft : 100 termes au maximum)."));
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
        _modelTexts[TranscriptionProvider.OpenAI] = s.EffectiveModel;
        _modelTexts[TranscriptionProvider.Mistral] = s.EffectiveMistralModel;
        _modelTexts[TranscriptionProvider.Microsoft] = s.EffectiveMicrosoftModel;
        _modelShownFor = s.EffectiveProvider;
        ShowModelChoices(s.EffectiveProvider);
        _provider.SelectedIndex = Math.Max(0, Array.FindIndex(Providers, p => p.Id == s.EffectiveProvider));
        _azureRegion.Text = s.EffectiveAzureRegion;
        UpdateProviderRows();
        RefreshKeyStatus();
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
        var selected = SelectedProvider;
        foreach (var row in _keyRows)
        {
            var hint = ApiKeyHint.Preview(_keys.Load(row.Provider));
            var chosen = row.Provider == selected ? " (fournisseur choisi)" : "";
            row.Status.Text = hint is null
                ? $"{ProviderName(row.Provider)}{chosen} : aucune clé enregistrée."
                : $"{ProviderName(row.Provider)}{chosen} : clé enregistrée {hint}";
            row.Delete.Enabled = hint is not null;
        }
    }

    private TranscriptionProvider SelectedProvider => Providers[Math.Max(0, _provider.SelectedIndex)].Id;

    private void OnProviderChanged()
    {
        var provider = SelectedProvider;
        if (provider == _modelShownFor) return;
        _modelTexts[_modelShownFor] = _model.Text.Trim();
        _modelShownFor = provider;
        ShowModelChoices(provider);
        UpdateProviderRows();
        RefreshKeyStatus();
    }

    /// <summary>Liste modifiable des modèles du fournisseur, avec la valeur saisie pour lui.</summary>
    private void ShowModelChoices(TranscriptionProvider provider)
    {
        var choices = provider switch
        {
            TranscriptionProvider.Mistral => DicteeSettings.MistralModelChoices,
            TranscriptionProvider.Microsoft => DicteeSettings.MicrosoftModelChoices,
            _ => DicteeSettings.ModelChoices,
        };
        _model.Items.Clear();
        _model.Items.AddRange(choices.Cast<object>().ToArray());
        _model.Text = _modelTexts.TryGetValue(provider, out var text) ? text : "";
    }

    /// <summary>« Région Azure » n'apparaît que pour Microsoft.</summary>
    private void UpdateProviderRows()
    {
        var azure = SelectedProvider == TranscriptionProvider.Microsoft;
        _azureRegionRow.Visible = azure;
        if (_azureRegionLabel is not null) _azureRegionLabel.Visible = azure;
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
        foreach (var row in _keyRows)
        {
            var key = row.Input.Text.Trim();
            if (key.Length == 0 || (key.Length >= 20 && !key.Any(char.IsWhiteSpace))) continue;
            var hint = row.Provider == TranscriptionProvider.OpenAI ? " (elle commence en général par « sk- »)" : "";
            MessageBox.Show(this, $"Cette clé ne ressemble pas à une clé API {ProviderName(row.Provider)}{hint}.",
                "Dictée", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            row.Input.Focus();
            return;
        }

        var region = _azureRegion.Text.Trim();
        if (region.Length > 0 && !IsValidAzureRegion(region))
        {
            MessageBox.Show(this, DicteeMessages.InvalidAzureRegion, "Dictée", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            _azureRegion.Focus();
            return;
        }

        var provider = SelectedProvider;
        _modelTexts[provider] = _model.Text.Trim();

        var s = _settings.Current.Clone();
        s.Provider = TranscriptionProviders.Id(provider);
        s.Model = ModelOrDefault(TranscriptionProvider.OpenAI, DicteeSettings.DefaultModel);
        s.MistralModel = ModelOrDefault(TranscriptionProvider.Mistral, DicteeSettings.DefaultMistralModel);
        s.MicrosoftModel = ModelOrDefault(TranscriptionProvider.Microsoft, DicteeSettings.DefaultMicrosoftModel);
        s.AzureRegion = region.Length == 0 ? DicteeSettings.DefaultAzureRegion : region.ToLowerInvariant();
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
            foreach (var row in _keyRows)
            {
                var key = row.Input.Text.Trim();
                if (key.Length > 0) _keys.Save(row.Provider, key);
            }
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

    private string ModelOrDefault(TranscriptionProvider provider, string fallback) =>
        _modelTexts.TryGetValue(provider, out var text) && !string.IsNullOrWhiteSpace(text) ? text.Trim() : fallback;

    private static bool IsValidAzureRegion(string region)
    {
        try
        {
            AzureSpeechClient.Endpoint(region);
            return true;
        }
        catch (DicteeException)
        {
            return false;
        }
    }

    private static string ProviderName(TranscriptionProvider provider) => TranscriptionProviders.DisplayName(provider);

    private static string KeyPlaceholder(TranscriptionProvider provider) => provider switch
    {
        TranscriptionProvider.Mistral => "Collez une nouvelle clé Mistral",
        TranscriptionProvider.Microsoft => "Collez une nouvelle clé Azure Speech (clé 1 ou 2)",
        _ => "Collez une nouvelle clé OpenAI (sk-…)",
    };

    private static (string Text, string Url) KeyLink(TranscriptionProvider provider) => provider switch
    {
        TranscriptionProvider.Mistral => ("Obtenir une clé sur console.mistral.ai", "https://console.mistral.ai/api-keys"),
        TranscriptionProvider.Microsoft => ("Clé et région : portail Azure > ressource Speech > Clés et point de terminaison", "https://portal.azure.com"),
        _ => ("Obtenir une clé sur platform.openai.com", "https://platform.openai.com/api-keys"),
    };

    // ---- Aides de mise en page ----

    private static TableLayoutPanel Grid(int columns) =>
        new() { ColumnCount = columns, AutoSize = true, Dock = DockStyle.Fill, AutoSizeMode = AutoSizeMode.GrowAndShrink };

    private static Label AddRow(TableLayoutPanel grid, string label, Control control)
    {
        if (grid.ColumnStyles.Count == 0)
        {
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        }
        var row = grid.RowCount++;
        var caption = new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(3, 7, 3, 3) };
        grid.Controls.Add(caption, 0, row);
        grid.Controls.Add(control, 1, row);
        return caption;
    }

    /// <summary>Note grise dans la colonne des valeurs, sous la ligne précédente.</summary>
    private static void AddNoteRow(TableLayoutPanel grid, Label note)
    {
        var row = grid.RowCount++;
        note.Margin = new Padding(3, 0, 3, 6);
        grid.Controls.Add(note, 1, row);
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
