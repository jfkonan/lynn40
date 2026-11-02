using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Dictee.Core;

/// <summary>Identifiants des raccourcis proposés sur Windows (valeur de la clé <c>hotkey</c>).</summary>
public static class HotkeyIds
{
    public const string RightCtrl = "rightCtrl";
    public const string RightAlt = "rightAlt";
    public const string F8 = "f8";
    public const string CtrlShiftSpace = "ctrlShiftSpace";

    public static readonly IReadOnlyList<string> All = [RightCtrl, RightAlt, F8, CtrlShiftSpace];

    /// <summary>Les combinaisons ne savent que basculer : RegisterHotKey ne signale pas le relâchement.</summary>
    public static bool IsCombination(string id) => id == CtrlShiftSpace;
}

/// <summary>Valeurs de la clé <c>hotkeyMode</c>.</summary>
public static class HotkeyModes
{
    public const string Hold = "hold";
    public const string Toggle = "toggle";
}

/// <summary>
/// Réglages de Dictée (SPEC.md §3), sérialisés en JSON avec les mêmes clés camelCase que les autres plateformes.
/// La clé API n'est JAMAIS stockée ici.
/// </summary>
public sealed class DicteeSettings
{
    public const string DefaultModel = "gpt-4o-transcribe";
    public const string DefaultLanguage = "fr";
    public const string DefaultVocabulary = "OHADA, AUSCGIE, AUDCG, AUPCAP, AUPSRVE, CCJA, SARL, SA, SAS, SNC, GIE, RCCM, assemblée générale, conseil d'administration, commissaire aux comptes, gérant, statuts, capital social";
    public const bool DefaultCleanupEnabled = false;
    public const string DefaultCleanupModel = "gpt-4o-mini";
    public const string DefaultHotkey = HotkeyIds.RightCtrl;
    public const string DefaultHotkeyMode = HotkeyModes.Hold;

    public static readonly IReadOnlyList<string> ModelChoices = ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"];
    public static readonly IReadOnlyList<string> CleanupModelChoices = ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"];

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        // Garde les accents lisibles dans le fichier (« assemblée » plutôt que « assemblée »).
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    private static readonly JsonDocumentOptions DocumentOptions = new()
    {
        CommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    public string Model { get; set; } = DefaultModel;
    public string Language { get; set; } = DefaultLanguage;
    public string Vocabulary { get; set; } = DefaultVocabulary;
    public bool CleanupEnabled { get; set; } = DefaultCleanupEnabled;
    public string CleanupModel { get; set; } = DefaultCleanupModel;

    // Réglages propres aux ordinateurs.
    public string Hotkey { get; set; } = DefaultHotkey;
    public string HotkeyMode { get; set; } = DefaultHotkeyMode;
    public bool SoundsEnabled { get; set; } = true;
    public bool RestoreClipboard { get; set; } = true;
    public bool LaunchAtLogin { get; set; } = false;

    /// <summary>Modèle à utiliser : une valeur vide ou faite d'espaces revient au défaut.</summary>
    [JsonIgnore] public string EffectiveModel => string.IsNullOrWhiteSpace(Model) ? DefaultModel : Model.Trim();

    [JsonIgnore] public string EffectiveCleanupModel => string.IsNullOrWhiteSpace(CleanupModel) ? DefaultCleanupModel : CleanupModel.Trim();

    /// <summary>Raccourci reconnu, sinon le défaut.</summary>
    [JsonIgnore] public string EffectiveHotkey => HotkeyIds.All.Contains(Hotkey) ? Hotkey : DefaultHotkey;

    /// <summary>Mode reconnu ; une combinaison impose « basculer ».</summary>
    [JsonIgnore]
    public string EffectiveHotkeyMode =>
        HotkeyIds.IsCombination(EffectiveHotkey) ? HotkeyModes.Toggle
        : HotkeyMode == HotkeyModes.Toggle ? HotkeyModes.Toggle
        : HotkeyModes.Hold;

    public DicteeSettings Clone() => (DicteeSettings)MemberwiseClone();

    public string ToJson() => JsonSerializer.Serialize(this, JsonOptions);

    /// <summary>
    /// Lit le JSON clé par clé : une valeur absente, nulle ou mal typée garde son défaut sans toucher aux autres
    /// (comme UserDefaults sur macOS). Contenu entièrement illisible → réglages par défaut.
    /// </summary>
    public static DicteeSettings FromJson(string? json)
    {
        var s = new DicteeSettings();
        if (string.IsNullOrWhiteSpace(json)) return s;
        try
        {
            if (JsonNode.Parse(json, documentOptions: DocumentOptions) is not JsonObject node) return s;
            string? Str(string key) => node[key] is JsonValue v && v.TryGetValue<string>(out var x) ? x : null;
            bool? Bool(string key) => node[key] is JsonValue v && v.TryGetValue<bool>(out var x) ? x : null;

            s.Model = Str("model") ?? s.Model;
            s.Language = Str("language") ?? s.Language;
            s.Vocabulary = Str("vocabulary") ?? s.Vocabulary;
            s.CleanupEnabled = Bool("cleanupEnabled") ?? s.CleanupEnabled;
            s.CleanupModel = Str("cleanupModel") ?? s.CleanupModel;
            s.Hotkey = Str("hotkey") ?? s.Hotkey;
            s.HotkeyMode = Str("hotkeyMode") ?? s.HotkeyMode;
            s.SoundsEnabled = Bool("soundsEnabled") ?? s.SoundsEnabled;
            s.RestoreClipboard = Bool("restoreClipboard") ?? s.RestoreClipboard;
            s.LaunchAtLogin = Bool("launchAtLogin") ?? s.LaunchAtLogin;
            return s;
        }
        catch (Exception ex) when (ex is JsonException or ArgumentException) // ArgumentException : clé en double
        {
            return new DicteeSettings();
        }
    }

    /// <summary>Fichier absent, illisible ou corrompu → réglages par défaut.</summary>
    public static DicteeSettings Load(string path)
    {
        try
        {
            return File.Exists(path) ? FromJson(File.ReadAllText(path)) : new DicteeSettings();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return new DicteeSettings();
        }
    }

    /// <summary>Écriture atomique : fichier temporaire puis remplacement.</summary>
    public void Save(string path)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        var temp = path + ".tmp";
        File.WriteAllText(temp, ToJson());
        File.Move(temp, path, overwrite: true);
    }
}
