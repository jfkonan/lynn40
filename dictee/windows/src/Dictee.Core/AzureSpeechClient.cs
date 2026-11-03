using System.Net.Http.Headers;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Dictee.Core;

/// <summary>
/// Transcription par Azure AI Speech, MAI-Transcribe-2, API « fast transcription »
/// (SPEC.md §2 bis, fournisseur <c>microsoft</c>). Format à confirmer à la première recette.
/// </summary>
public sealed class AzureSpeechClient : ITranscriptionClient
{
    public const string ApiVersion = "2025-10-15";
    public const string SubscriptionKeyHeader = "Ocp-Apim-Subscription-Key";
    public const string AudioFileName = "audio.wav";

    private static readonly JsonWriterOptions DefinitionWriterOptions = new()
    {
        // Termes accentués lisibles (« assemblée ») : le corps est en UTF-8.
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private readonly HttpClient _http;
    private readonly string _apiKey;

    /// <param name="http">Client HTTP partagé, sans délai global (<see cref="ApiHttp.CreateHttpClient"/>).</param>
    /// <param name="apiKey">Clé de la ressource Azure Speech. Ne jamais la journaliser.</param>
    public AzureSpeechClient(HttpClient http, string? apiKey)
    {
        _http = http;
        _apiKey = apiKey?.Trim() ?? "";
    }

    public TranscriptionProvider Provider => TranscriptionProvider.Microsoft;

    public Task<string> TranscribeAsync(string audioPath, DicteeSettings settings, CancellationToken cancellationToken = default) =>
        TranscribeAsync(audioPath, settings.EffectiveAzureRegion, settings.EffectiveMicrosoftModel, settings.Language,
            settings.Vocabulary, cancellationToken);

    public async Task<string> TranscribeAsync(string audioPath, string region, string model, string? language,
        string? vocabulary, CancellationToken cancellationToken = default)
    {
        ApiHttp.EnsureApiKey(_apiKey, Provider);
        var endpoint = Endpoint(region); // région invalide : erreur avant toute lecture ou envoi
        var audio = await File.ReadAllBytesAsync(audioPath, cancellationToken).ConfigureAwait(false);
        using var request = BuildTranscriptionRequest(endpoint, _apiKey, audio, model, language, vocabulary);
        var body = await ApiHttp.SendAsync(_http, request, DicteeConstants.TranscriptionTimeout, Provider, _apiKey,
            cancellationToken).ConfigureAwait(false);
        return ParseTranscription(body);
    }

    /// <summary>
    /// <c>https://&lt;région&gt;.api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15</c>.
    /// La région n'accepte que lettres, chiffres et tirets : la clé ne peut pas partir vers un autre hôte.
    /// </summary>
    public static Uri Endpoint(string? region)
    {
        var value = region?.Trim().ToLowerInvariant() ?? "";
        if (!Regex.IsMatch(value, "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$"))
            throw new DicteeException(DicteeMessages.InvalidAzureRegion);
        return new Uri($"https://{value}.api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe?api-version={ApiVersion}");
    }

    public static HttpRequestMessage BuildTranscriptionRequest(string region, string apiKey, ReadOnlySpan<byte> audio,
        string model, string? language, string? vocabulary, string? boundary = null)
    {
        ApiHttp.EnsureApiKey(apiKey, TranscriptionProvider.Microsoft);
        return BuildTranscriptionRequest(Endpoint(region), apiKey, audio, model, language, vocabulary, boundary);
    }

    /// <summary>Corps multipart à deux parties : <c>audio</c> (le WAV) et <c>definition</c> (JSON).</summary>
    public static HttpRequestMessage BuildTranscriptionRequest(Uri endpoint, string apiKey, ReadOnlySpan<byte> audio,
        string model, string? language, string? vocabulary, string? boundary = null)
    {
        ApiHttp.EnsureApiKey(apiKey, TranscriptionProvider.Microsoft);

        var form = new MultipartFormData(boundary);
        form.AddFile("audio", AudioFileName, "audio/wav", audio);
        form.AddField("definition", BuildDefinition(model, language, vocabulary), "application/json");

        var content = new ByteArrayContent(form.ToArray());
        content.Headers.ContentType = MediaTypeHeaderValue.Parse(form.ContentType);

        var request = new HttpRequestMessage(HttpMethod.Post, endpoint) { Content = content };
        request.Headers.TryAddWithoutValidation(SubscriptionKeyHeader, apiKey.Trim());
        return request;
    }

    /// <summary>
    /// <c>{"locales":["fr-FR"],"enhancedMode":{"enabled":true,"model":"…"},"phraseList":{"phrases":[…]}}</c> ;
    /// <c>locales</c> omis si la langue est vide, <c>phraseList</c> omis s'il n'y a aucun terme.
    /// </summary>
    public static string BuildDefinition(string model, string? language, string? vocabulary)
    {
        var definition = new JsonObject();
        if (AzureLocale.FromLanguage(language) is { } locale) definition["locales"] = new JsonArray(locale);
        definition["enhancedMode"] = new JsonObject { ["enabled"] = true, ["model"] = model };
        var terms = VocabularyTerms.Split(vocabulary);
        if (terms.Count > 0)
        {
            var phrases = new JsonArray();
            foreach (var term in terms) phrases.Add(term);
            definition["phraseList"] = new JsonObject { ["phrases"] = phrases };
        }
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer, DefinitionWriterOptions)) definition.WriteTo(writer);
        return Encoding.UTF8.GetString(buffer.ToArray());
    }

    /// <summary>Texte = <c>combinedPhrases[0].text</c> ; à défaut, les <c>phrases[].text</c> joints par des espaces.</summary>
    public static string ParseTranscription(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.ValueKind == JsonValueKind.Object)
            {
                if (root.TryGetProperty("combinedPhrases", out var combined) && combined.ValueKind == JsonValueKind.Array &&
                    combined.GetArrayLength() > 0 && combined[0].ValueKind == JsonValueKind.Object &&
                    combined[0].TryGetProperty("text", out var combinedText) && combinedText.ValueKind == JsonValueKind.String)
                {
                    return combinedText.GetString() ?? "";
                }

                if (root.TryGetProperty("phrases", out var phrases) && phrases.ValueKind == JsonValueKind.Array)
                {
                    var parts = new List<string>();
                    foreach (var phrase in phrases.EnumerateArray())
                    {
                        if (phrase.ValueKind == JsonValueKind.Object && phrase.TryGetProperty("text", out var text) &&
                            text.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(text.GetString()))
                        {
                            parts.Add(text.GetString()!.Trim());
                        }
                    }
                    return string.Join(" ", parts);
                }

                // Audio sans parole : Azure peut renvoyer « combinedPhrases » vide sans « phrases ».
                if (combined.ValueKind == JsonValueKind.Array) return "";
            }
        }
        catch (JsonException) { }
        throw new DicteeException(DicteeMessages.InvalidResponse(TranscriptionProvider.Microsoft));
    }
}
