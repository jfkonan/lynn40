using System.Net.Http.Headers;

namespace Dictee.Core;

/// <summary>Transcription par Mistral Voxtral, hébergé dans l'UE (SPEC.md §2 bis, fournisseur <c>mistral</c>).</summary>
public sealed class MistralClient : ITranscriptionClient
{
    public static readonly Uri DefaultBaseUri = new("https://api.mistral.ai/v1/");

    private readonly HttpClient _http;
    private readonly string _apiKey;
    private readonly Uri _baseUri;

    /// <param name="http">Client HTTP partagé, sans délai global (<see cref="ApiHttp.CreateHttpClient"/>).</param>
    /// <param name="apiKey">Clé Mistral de l'utilisateur. Ne jamais la journaliser.</param>
    public MistralClient(HttpClient http, string? apiKey, Uri? baseUri = null)
    {
        _http = http;
        _apiKey = apiKey?.Trim() ?? "";
        _baseUri = baseUri ?? DefaultBaseUri;
    }

    public TranscriptionProvider Provider => TranscriptionProvider.Mistral;

    public Task<string> TranscribeAsync(string audioPath, DicteeSettings settings, CancellationToken cancellationToken = default) =>
        TranscribeAsync(audioPath, settings.EffectiveMistralModel, settings.Language, settings.Vocabulary, cancellationToken);

    public async Task<string> TranscribeAsync(string audioPath, string model, string? language, string? vocabulary,
        CancellationToken cancellationToken = default)
    {
        ApiHttp.EnsureApiKey(_apiKey, Provider);
        var audio = await File.ReadAllBytesAsync(audioPath, cancellationToken).ConfigureAwait(false);
        using var request = BuildTranscriptionRequest(_baseUri, _apiKey, audio, Path.GetFileName(audioPath),
            model, language, vocabulary);
        var body = await ApiHttp.SendAsync(_http, request, DicteeConstants.TranscriptionTimeout, Provider, _apiKey,
            cancellationToken).ConfigureAwait(false);
        return OpenAiClient.ParseTranscription(body, Provider);
    }

    /// <summary>
    /// Champs <c>model</c>, <c>language</c> (2 lettres, omis si vide), un <c>context_bias</c> par terme du vocabulaire,
    /// puis <c>file</c>. Ni <c>prompt</c> ni <c>response_format</c>.
    /// </summary>
    public static HttpRequestMessage BuildTranscriptionRequest(Uri baseUri, string apiKey, ReadOnlySpan<byte> audio,
        string fileName, string model, string? language, string? vocabulary, string? boundary = null)
    {
        ApiHttp.EnsureApiKey(apiKey, TranscriptionProvider.Mistral);

        var form = new MultipartFormData(boundary);
        form.AddField("model", model);
        if (LanguageCode(language) is { } code) form.AddField("language", code);
        foreach (var term in VocabularyTerms.Split(vocabulary)) form.AddField("context_bias", term);
        form.AddFile("file", fileName, OpenAiClient.MimeType(fileName), audio);

        var content = new ByteArrayContent(form.ToArray());
        content.Headers.ContentType = MediaTypeHeaderValue.Parse(form.ContentType);

        var request = new HttpRequestMessage(HttpMethod.Post, new Uri(baseUri, "audio/transcriptions")) { Content = content };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey.Trim());
        return request;
    }

    /// <summary>Code de langue à 2 lettres : « fr-FR » → « fr » ; vide → null (champ omis).</summary>
    public static string? LanguageCode(string? language)
    {
        var value = language?.Trim() ?? "";
        var cut = value.IndexOfAny(['-', '_']);
        if (cut >= 0) value = value[..cut];
        value = value.Trim().ToLowerInvariant();
        return value.Length == 0 ? null : value;
    }
}
