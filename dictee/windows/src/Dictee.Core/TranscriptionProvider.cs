namespace Dictee.Core;

/// <summary>Fournisseurs de transcription (SPEC.md §2 bis).</summary>
public enum TranscriptionProvider
{
    OpenAI,
    Mistral,
    Microsoft,
}

/// <summary>Identifiants du réglage <c>provider</c>, noms affichés et fichiers de clé.</summary>
public static class TranscriptionProviders
{
    public const string OpenAIId = "openai";
    public const string MistralId = "mistral";
    public const string MicrosoftId = "microsoft";

    public static readonly IReadOnlyList<TranscriptionProvider> All =
        [TranscriptionProvider.OpenAI, TranscriptionProvider.Mistral, TranscriptionProvider.Microsoft];

    /// <summary>Valeur stockée dans <c>settings.json</c>.</summary>
    public static string Id(TranscriptionProvider provider) => provider switch
    {
        TranscriptionProvider.Mistral => MistralId,
        TranscriptionProvider.Microsoft => MicrosoftId,
        _ => OpenAIId,
    };

    /// <summary>Nom employé dans les messages : « OpenAI », « Mistral » ou « Microsoft ».</summary>
    public static string DisplayName(TranscriptionProvider provider) => provider switch
    {
        TranscriptionProvider.Mistral => "Mistral",
        TranscriptionProvider.Microsoft => "Microsoft",
        _ => "OpenAI",
    };

    /// <summary>Valeur du réglage <c>provider</c> ; vide ou inconnue → OpenAI.</summary>
    public static TranscriptionProvider Parse(string? id) => id?.Trim().ToLowerInvariant() switch
    {
        MistralId => TranscriptionProvider.Mistral,
        MicrosoftId => TranscriptionProvider.Microsoft,
        _ => TranscriptionProvider.OpenAI,
    };

    /// <summary>Fichier DPAPI de la clé dans %APPDATA%\Dictee (SPEC.md §4) ; celui d'OpenAI est inchangé.</summary>
    public static string ApiKeyFileName(TranscriptionProvider provider) => provider switch
    {
        TranscriptionProvider.Mistral => "apikey-mistral.bin",
        TranscriptionProvider.Microsoft => "apikey-microsoft.bin",
        _ => "apikey.bin",
    };
}
