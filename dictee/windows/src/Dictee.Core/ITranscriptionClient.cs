namespace Dictee.Core;

/// <summary>Transcription d'un fichier audio chez un fournisseur (SPEC.md §2 bis).</summary>
public interface ITranscriptionClient
{
    TranscriptionProvider Provider { get; }

    /// <summary>Texte brut transcrit, avec le modèle, la langue et le vocabulaire des réglages.</summary>
    /// <exception cref="DicteeException">Message prêt à afficher (clé manquante, erreur HTTP, délai, réseau…).</exception>
    Task<string> TranscribeAsync(string audioPath, DicteeSettings settings, CancellationToken cancellationToken = default);
}

/// <summary>Choix du client de transcription selon le fournisseur.</summary>
public static class TranscriptionClients
{
    /// <param name="apiKey">Clé du fournisseur choisi (jamais journalisée) ; absente → « Clé API … manquante » à l'appel.</param>
    public static ITranscriptionClient Create(TranscriptionProvider provider, HttpClient http, string? apiKey) => provider switch
    {
        TranscriptionProvider.Mistral => new MistralClient(http, apiKey),
        TranscriptionProvider.Microsoft => new AzureSpeechClient(http, apiKey),
        _ => new OpenAiClient(http, apiKey),
    };
}
