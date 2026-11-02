namespace Dictee.Core;

/// <summary>
/// Pipeline commun (SPEC.md §2) : transcription → nettoyage optionnel (repli sur le brut) →
/// texte vide = erreur → suppression du fichier audio dans tous les cas.
/// </summary>
public sealed class TranscriptionPipeline
{
    private readonly OpenAiClient _client;

    public TranscriptionPipeline(OpenAiClient client) => _client = client;

    /// <returns>Le texte à insérer (jamais vide).</returns>
    /// <exception cref="DicteeException">Message prêt à afficher.</exception>
    public async Task<string> RunAsync(string audioPath, DicteeSettings settings, CancellationToken cancellationToken = default)
    {
        try
        {
            var raw = (await _client.TranscribeAsync(audioPath, settings.EffectiveModel, settings.Language,
                settings.Vocabulary, cancellationToken).ConfigureAwait(false)).Trim();

            var text = raw;
            if (settings.CleanupEnabled && raw.Length > 0)
            {
                try
                {
                    var cleaned = await _client.CleanUpAsync(raw, settings.EffectiveCleanupModel, settings.Vocabulary,
                        cancellationToken).ConfigureAwait(false);
                    if (!string.IsNullOrWhiteSpace(cleaned)) text = cleaned.Trim();
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    throw;
                }
                catch (Exception)
                {
                    // Nettoyage en échec : on garde le texte brut (SPEC §2.3).
                }
            }

            if (string.IsNullOrWhiteSpace(text)) throw new DicteeException(DicteeMessages.NoSpeech);
            return text;
        }
        finally
        {
            TryDelete(audioPath);
        }
    }

    /// <summary>Supprime le fichier sans jamais lever d'exception.</summary>
    public static void TryDelete(string? path)
    {
        if (string.IsNullOrEmpty(path)) return;
        try { File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
