namespace Dictee.Core;

/// <summary>
/// Pipeline commun (SPEC.md §2) : transcription chez le fournisseur choisi → nettoyage optionnel chez OpenAI
/// (repli sur le brut, sauté sans clé OpenAI) → texte vide = erreur → suppression du fichier audio dans tous les cas.
/// </summary>
public sealed class TranscriptionPipeline
{
    private readonly ITranscriptionClient _transcriber;
    private readonly OpenAiClient? _cleaner;

    /// <summary>Transcription et nettoyage chez OpenAI, avec la même clé.</summary>
    public TranscriptionPipeline(OpenAiClient client) : this(client, client) { }

    /// <param name="transcriber">Client du fournisseur choisi (<see cref="TranscriptionClients.Create"/>).</param>
    /// <param name="cleaner">Client OpenAI du nettoyage ; null ou sans clé : nettoyage sauté sans erreur.</param>
    public TranscriptionPipeline(ITranscriptionClient transcriber, OpenAiClient? cleaner)
    {
        _transcriber = transcriber;
        _cleaner = cleaner;
    }

    /// <returns>Le texte à insérer (jamais vide).</returns>
    /// <exception cref="DicteeException">Message prêt à afficher.</exception>
    public async Task<string> RunAsync(string audioPath, DicteeSettings settings, CancellationToken cancellationToken = default)
    {
        try
        {
            var raw = (await _transcriber.TranscribeAsync(audioPath, settings, cancellationToken).ConfigureAwait(false)).Trim();

            var text = raw;
            if (settings.CleanupEnabled && raw.Length > 0 && _cleaner is { HasApiKey: true })
            {
                try
                {
                    var cleaned = await _cleaner.CleanUpAsync(raw, settings.EffectiveCleanupModel, settings.Vocabulary,
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
