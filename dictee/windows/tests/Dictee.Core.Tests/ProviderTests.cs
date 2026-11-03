using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Dictee.Core.Tests;

public class TranscriptionProviderTests
{
    [Theory]
    [InlineData(TranscriptionProvider.OpenAI, "openai", "OpenAI", "apikey.bin")]
    [InlineData(TranscriptionProvider.Mistral, "mistral", "Mistral", "apikey-mistral.bin")]
    [InlineData(TranscriptionProvider.Microsoft, "microsoft", "Microsoft", "apikey-microsoft.bin")]
    public void IdsNamesAndKeyFiles(TranscriptionProvider provider, string id, string name, string keyFile)
    {
        Assert.Equal(id, TranscriptionProviders.Id(provider));
        Assert.Equal(name, TranscriptionProviders.DisplayName(provider));
        Assert.Equal(keyFile, TranscriptionProviders.ApiKeyFileName(provider));
        Assert.Equal(provider, TranscriptionProviders.Parse(id));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("azure")]
    [InlineData("OpenAI ")]
    public void UnknownProviderIsOpenAi(string? id) => Assert.Equal(TranscriptionProvider.OpenAI, TranscriptionProviders.Parse(id));

    [Fact]
    public void ClientFactoryFollowsProvider()
    {
        using var http = ApiHttp.CreateHttpClient();
        Assert.IsType<OpenAiClient>(TranscriptionClients.Create(TranscriptionProvider.OpenAI, http, "k"));
        Assert.IsType<MistralClient>(TranscriptionClients.Create(TranscriptionProvider.Mistral, http, "k"));
        Assert.IsType<AzureSpeechClient>(TranscriptionClients.Create(TranscriptionProvider.Microsoft, http, "k"));
        foreach (var provider in TranscriptionProviders.All)
            Assert.Equal(provider, TranscriptionClients.Create(provider, http, null).Provider);
    }

    [Theory]
    [InlineData(TranscriptionProvider.OpenAI, "OpenAI")]
    [InlineData(TranscriptionProvider.Mistral, "Mistral")]
    [InlineData(TranscriptionProvider.Microsoft, "Microsoft")]
    public void MessagesNameTheProvider(TranscriptionProvider provider, string name)
    {
        Assert.Equal($"Clé API {name} manquante. Ajoutez-la dans les réglages de Dictée.", DicteeMessages.MissingApiKey(provider));
        Assert.Equal($"Erreur {name} (429) : Quota dépassé", DicteeMessages.Http(provider, 429, "Quota dépassé"));
        Assert.Equal($"Connexion à {name} impossible : Hôte inconnu", DicteeMessages.Network(provider, "Hôte inconnu"));
        Assert.Equal($"{name} ne répond pas (délai dépassé). Réessayez.", DicteeMessages.Timeout(provider));
        Assert.Equal($"Réponse {name} illisible.", DicteeMessages.InvalidResponse(provider));
        Assert.Equal($"Erreur {name} (500) : panne", new ApiHttpException(provider, 500, "panne").Message);
    }
}

public class VocabularyTermsTests
{
    [Fact]
    public void SplitsOnCommasSemicolonsAndNewlines()
    {
        Assert.Equal(["OHADA", "AUSCGIE", "assemblée générale", "CCJA", "SARL", "SA"],
            VocabularyTerms.Split(" OHADA, AUSCGIE ;assemblée générale\nCCJA\r\nSARL\rSA "));
    }

    [Fact]
    public void IgnoresEmptyTermsAndKeepsFirstDuplicate()
    {
        Assert.Equal(["SARL", "SA", "sa"], VocabularyTerms.Split(",, SARL ;; SA,\n\n SARL , sa, SA ,"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    [InlineData(" , ; \n ")]
    public void EmptyVocabularyGivesNoTerms(string? vocabulary) => Assert.Empty(VocabularyTerms.Split(vocabulary));

    [Fact]
    public void KeepsAtMost100Terms()
    {
        var vocabulary = string.Join(", ", Enumerable.Range(1, 150).Select(i => $"terme{i}"));
        var terms = VocabularyTerms.Split(vocabulary);
        Assert.Equal(100, terms.Count);
        Assert.Equal("terme1", terms[0]);
        Assert.Equal("terme100", terms[^1]);
    }

    [Fact]
    public void DuplicatesDoNotCountTowardTheLimit()
    {
        var vocabulary = "doublon, doublon, " + string.Join(", ", Enumerable.Range(1, 120).Select(i => $"t{i}"));
        var terms = VocabularyTerms.Split(vocabulary);
        Assert.Equal(100, terms.Count);
        Assert.Equal("t99", terms[^1]);
    }

    [Fact]
    public void DefaultVocabularyHas18Terms() =>
        Assert.Equal(18, VocabularyTerms.Split(DicteeSettings.DefaultVocabulary).Count);
}

public class AzureLocaleTests
{
    [Theory]
    [InlineData("fr", "fr-FR")]
    [InlineData("en", "en-US")]
    [InlineData("es", "es-ES")]
    [InlineData("de", "de-DE")]
    [InlineData("it", "it-IT")]
    [InlineData("pt", "pt-BR")]
    [InlineData("nl", "nl-NL")]
    [InlineData("ar", "ar-SA")]
    [InlineData(" FR ", "fr-FR")]
    [InlineData("fr-CA", "fr-CA")]
    [InlineData("en-GB", "en-GB")]
    [InlineData("xx", "xx-XX")]
    [InlineData("Pl", "pl-PL")]
    public void MapsLanguageToLocale(string language, string expected) => Assert.Equal(expected, AzureLocale.FromLanguage(language));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void EmptyLanguageGivesNull(string? language) => Assert.Null(AzureLocale.FromLanguage(language));
}

public class MistralClientTests
{
    private static string BodyOf(HttpRequestMessage request) => request.Content!.ReadAsStringAsync().GetAwaiter().GetResult();

    [Fact]
    public void RequestHasUrlBearerAndContextBiasPerTerm()
    {
        using var request = MistralClient.BuildTranscriptionRequest(MistralClient.DefaultBaseUri, "mistral-key-0123456789",
            "RIFF"u8, "dictee.wav", "voxtral-small-transcribe-3", "fr-FR", "OHADA, AUSCGIE; assemblée générale\nOHADA", boundary: "B");
        var body = BodyOf(request);

        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("https://api.mistral.ai/v1/audio/transcriptions", request.RequestUri!.ToString());
        Assert.Equal("Bearer mistral-key-0123456789", request.Headers.Authorization!.ToString());
        Assert.Equal("multipart/form-data; boundary=B", request.Content!.Headers.ContentType!.ToString());
        Assert.Contains("--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nvoxtral-small-transcribe-3\r\n", body);
        Assert.Contains("name=\"language\"\r\n\r\nfr\r\n", body);
        Assert.Equal(3, Regex.Matches(body, "name=\"context_bias\"").Count);
        Assert.Contains("name=\"context_bias\"\r\n\r\nOHADA\r\n", body);
        Assert.Contains("name=\"context_bias\"\r\n\r\nAUSCGIE\r\n", body);
        Assert.Contains("name=\"context_bias\"\r\n\r\nassemblée générale\r\n", body);
        Assert.DoesNotContain("name=\"prompt\"", body);
        Assert.DoesNotContain("name=\"response_format\"", body);
        Assert.Contains("name=\"file\"; filename=\"dictee.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n", body);
        Assert.EndsWith("--B--\r\n", body);
        // Ordre : champs texte d'abord, fichier en dernier.
        Assert.True(body.IndexOf("context_bias", StringComparison.Ordinal) < body.IndexOf("name=\"file\"", StringComparison.Ordinal));
    }

    [Theory]
    [InlineData("", null)]
    [InlineData(null, null)]
    [InlineData("fr", "fr")]
    [InlineData("fr-FR", "fr")]
    [InlineData(" EN_us ", "en")]
    public void LanguageIsReducedToTwoLetters(string? language, string? expected)
    {
        Assert.Equal(expected, MistralClient.LanguageCode(language));
        using var request = MistralClient.BuildTranscriptionRequest(MistralClient.DefaultBaseUri, "k", "x"u8, "a.wav", "m", language, "");
        var body = BodyOf(request);
        if (expected is null) Assert.DoesNotContain("name=\"language\"", body);
        else Assert.Contains($"name=\"language\"\r\n\r\n{expected}\r\n", body);
        Assert.DoesNotContain("context_bias", body); // vocabulaire vide : aucun terme
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    public void MissingKeyNamesMistral(string? key)
    {
        var ex = Assert.Throws<DicteeException>(() =>
            MistralClient.BuildTranscriptionRequest(MistralClient.DefaultBaseUri, key!, "x"u8, "a.wav", "m", null, null));
        Assert.Equal("Clé API Mistral manquante. Ajoutez-la dans les réglages de Dictée.", ex.Message);
    }

    [Fact]
    public async Task UsesMistralModelFromSettingsAndParsesText()
    {
        var handler = new FakeHttpHandler().Respond(HttpStatusCode.OK, "{\"model\":\"voxtral\",\"text\":\"Bonjour\",\"language\":\"fr\"}");
        var client = new MistralClient(ApiHttp.CreateHttpClient(handler), "mistral-key-0123456789");
        var path = TempWav.Create();

        var text = await client.TranscribeAsync(path, new DicteeSettings { MistralModel = " " });

        Assert.Equal("Bonjour", text);
        Assert.Contains("name=\"model\"\r\n\r\nvoxtral-small-transcribe-3\r\n", handler.Requests.Single().Body);
        File.Delete(path);
    }

    [Fact]
    public async Task HttpErrorNamesMistral()
    {
        var handler = new FakeHttpHandler().Respond(HttpStatusCode.Unauthorized,
            "{\"object\":\"error\",\"message\":\"Unauthorized\",\"type\":\"invalid_request_error\"}");
        var client = new MistralClient(ApiHttp.CreateHttpClient(handler), "mistral-key-0123456789");
        var path = TempWav.Create();

        var ex = await Assert.ThrowsAsync<ApiHttpException>(() => client.TranscribeAsync(path, new DicteeSettings()));

        Assert.Equal("Erreur Mistral (401) : Unauthorized", ex.Message);
        Assert.Equal(TranscriptionProvider.Mistral, ex.Provider);
        File.Delete(path);
    }

    [Fact]
    public async Task NetworkAndTimeoutNameMistral()
    {
        var handler = new FakeHttpHandler().Throw(new HttpRequestException("Hôte inconnu")).Throw(new TaskCanceledException("délai"));
        var client = new MistralClient(ApiHttp.CreateHttpClient(handler), "k");
        var path = TempWav.Create();

        var network = await Assert.ThrowsAsync<DicteeException>(() => client.TranscribeAsync(path, new DicteeSettings()));
        var timeout = await Assert.ThrowsAsync<DicteeException>(() => client.TranscribeAsync(path, new DicteeSettings()));

        Assert.Equal("Connexion à Mistral impossible : Hôte inconnu", network.Message);
        Assert.Equal("Mistral ne répond pas (délai dépassé). Réessayez.", timeout.Message);
        File.Delete(path);
    }
}

public class AzureSpeechClientTests
{
    private static string BodyOf(HttpRequestMessage request) => request.Content!.ReadAsStringAsync().GetAwaiter().GetResult();

    /// <summary>Contenu JSON de la partie « definition ».</summary>
    private static JsonDocument DefinitionOf(string body)
    {
        var match = Regex.Match(body, "name=\"definition\"\r\nContent-Type: application/json\r\n\r\n(.*?)\r\n--", RegexOptions.Singleline);
        Assert.True(match.Success, "partie definition absente ou sans Content-Type application/json");
        return JsonDocument.Parse(match.Groups[1].Value);
    }

    [Fact]
    public void RequestHasRegionUrlKeyHeaderAndTwoParts()
    {
        using var request = AzureSpeechClient.BuildTranscriptionRequest("westeurope", "azure-key-0123456789abcdef",
            "RIFF"u8, "mai-transcribe-2", "fr", "OHADA, AUSCGIE\nassemblée générale", boundary: "B");
        var body = BodyOf(request);

        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("https://westeurope.api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15",
            request.RequestUri!.AbsoluteUri);
        Assert.Equal("azure-key-0123456789abcdef", request.Headers.GetValues("Ocp-Apim-Subscription-Key").Single());
        Assert.Null(request.Headers.Authorization);
        Assert.Equal("multipart/form-data; boundary=B", request.Content!.Headers.ContentType!.ToString());
        Assert.Contains("--B\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n", body);
        Assert.Equal(2, Regex.Matches(body, "Content-Disposition").Count);
        Assert.EndsWith("--B--\r\n", body);

        using var definition = DefinitionOf(body);
        var root = definition.RootElement;
        Assert.Equal(["fr-FR"], root.GetProperty("locales").EnumerateArray().Select(e => e.GetString()));
        Assert.True(root.GetProperty("enhancedMode").GetProperty("enabled").GetBoolean());
        Assert.Equal("mai-transcribe-2", root.GetProperty("enhancedMode").GetProperty("model").GetString());
        Assert.Equal(["OHADA", "AUSCGIE", "assemblée générale"],
            root.GetProperty("phraseList").GetProperty("phrases").EnumerateArray().Select(e => e.GetString()));
    }

    [Fact]
    public void LocalesAndPhraseListOmittedWhenEmpty()
    {
        using var definition = JsonDocument.Parse(AzureSpeechClient.BuildDefinition("mai-transcribe-2", " ", " ; "));
        var root = definition.RootElement;
        Assert.False(root.TryGetProperty("locales", out _));
        Assert.False(root.TryGetProperty("phraseList", out _));
        Assert.Equal("mai-transcribe-2", root.GetProperty("enhancedMode").GetProperty("model").GetString());
    }

    [Fact]
    public void ComposedLocaleIsKept()
    {
        using var definition = JsonDocument.Parse(AzureSpeechClient.BuildDefinition("m", "fr-CA", null));
        Assert.Equal("fr-CA", definition.RootElement.GetProperty("locales")[0].GetString());
    }

    [Theory]
    [InlineData("eastus")]
    [InlineData(" SwedenCentral ")]
    public void ValidRegions(string region) =>
        Assert.StartsWith($"https://{region.Trim().ToLowerInvariant()}.api.cognitive.microsoft.com/", AzureSpeechClient.Endpoint(region).AbsoluteUri);

    [Theory]
    [InlineData("")]
    [InlineData("evil.com/x?")]
    [InlineData("west europe")]
    [InlineData("-eastus")]
    [InlineData("a.b")]
    public void InvalidRegionIsRejectedWithoutSendingTheKey(string region)
    {
        var ex = Assert.Throws<DicteeException>(() =>
            AzureSpeechClient.BuildTranscriptionRequest(region, "azure-key", "x"u8, "m", "fr", ""));
        Assert.Equal(DicteeMessages.InvalidAzureRegion, ex.Message);
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    public void MissingKeyNamesMicrosoft(string? key)
    {
        var ex = Assert.Throws<DicteeException>(() =>
            AzureSpeechClient.BuildTranscriptionRequest("eastus", key!, "x"u8, "m", null, null));
        Assert.Equal("Clé API Microsoft manquante. Ajoutez-la dans les réglages de Dictée.", ex.Message);
    }

    [Fact]
    public void ParsesCombinedPhrases()
    {
        Assert.Equal("Bonjour le monde.", AzureSpeechClient.ParseTranscription(
            "{\"durationMilliseconds\":1200,\"combinedPhrases\":[{\"text\":\"Bonjour le monde.\"}],\"phrases\":[{\"text\":\"autre\"}]}"));
    }

    [Fact]
    public void FallsBackToPhrases()
    {
        Assert.Equal("Bonjour. Le monde.", AzureSpeechClient.ParseTranscription(
            "{\"phrases\":[{\"offsetMilliseconds\":0,\"text\":\"Bonjour.\"},{\"text\":\" Le monde. \"},{\"locale\":\"fr-FR\"}]}"));
        Assert.Equal("Seul.", AzureSpeechClient.ParseTranscription("{\"combinedPhrases\":[],\"phrases\":[{\"text\":\"Seul.\"}]}"));
        Assert.Equal("", AzureSpeechClient.ParseTranscription("{\"combinedPhrases\":[],\"phrases\":[]}"));
        Assert.Equal("", AzureSpeechClient.ParseTranscription("{\"combinedPhrases\":[]}"));
    }

    [Theory]
    [InlineData("pas du json")]
    [InlineData("{}")]
    [InlineData("{\"text\":\"Bonjour\"}")]
    [InlineData("[]")]
    public void InvalidResponseNamesMicrosoft(string json)
    {
        var ex = Assert.Throws<DicteeException>(() => AzureSpeechClient.ParseTranscription(json));
        Assert.Equal("Réponse Microsoft illisible.", ex.Message);
    }

    [Fact]
    public async Task UsesSettingsRegionModelAndLanguage()
    {
        var handler = new FakeHttpHandler().Respond(HttpStatusCode.OK, "{\"combinedPhrases\":[{\"text\":\"Bonjour\"}]}");
        var client = new AzureSpeechClient(ApiHttp.CreateHttpClient(handler), "azure-key-0123456789abcdef");
        var path = TempWav.Create();

        var text = await client.TranscribeAsync(path, new DicteeSettings { AzureRegion = "swedencentral", Language = "en", Vocabulary = "" });

        Assert.Equal("Bonjour", text);
        var request = handler.Requests.Single();
        Assert.Equal("swedencentral.api.cognitive.microsoft.com", request.Uri.Host);
        Assert.Equal("?api-version=2025-10-15", request.Uri.Query);
        Assert.Equal("azure-key-0123456789abcdef", request.Headers["Ocp-Apim-Subscription-Key"]);
        using var definition = DefinitionOf(request.Body);
        Assert.Equal("en-US", definition.RootElement.GetProperty("locales")[0].GetString());
        Assert.Equal("mai-transcribe-2", definition.RootElement.GetProperty("enhancedMode").GetProperty("model").GetString());
        Assert.False(definition.RootElement.TryGetProperty("phraseList", out _));
        File.Delete(path);
    }

    [Fact]
    public async Task HttpErrorNamesMicrosoftAndNeverLeaksKey()
    {
        const string key = "0123456789abcdef0123456789abcdef";
        var handler = new FakeHttpHandler().Respond(HttpStatusCode.Unauthorized,
            $"{{\"error\":{{\"code\":\"401\",\"message\":\"Access denied for key {key}.\"}}}}");
        var client = new AzureSpeechClient(ApiHttp.CreateHttpClient(handler), key);
        var path = TempWav.Create();

        var ex = await Assert.ThrowsAsync<ApiHttpException>(() => client.TranscribeAsync(path, new DicteeSettings()));

        Assert.Equal(401, ex.StatusCode);
        Assert.Equal("Erreur Microsoft (401) : Access denied for key 012…cdef.", ex.Message);
        Assert.DoesNotContain(key, ex.Message);
        File.Delete(path);
    }
}

public class ErrorMessageTests
{
    [Fact]
    public void ReadsErrorMessageFirst() =>
        Assert.Equal("Clé invalide", ApiHttp.ExtractErrorMessage("{\"error\":{\"message\":\"Clé invalide\"},\"message\":\"autre\",\"detail\":\"x\"}"));

    [Fact]
    public void ThenRootMessage() =>
        Assert.Equal("Unauthorized", ApiHttp.ExtractErrorMessage("{\"object\":\"error\",\"message\":\"Unauthorized\",\"detail\":\"x\"}"));

    [Fact]
    public void ThenDetailText() =>
        Assert.Equal("Invalid model", ApiHttp.ExtractErrorMessage("{\"detail\":\"Invalid model\"}"));

    [Fact]
    public void DetailJsonIsCopiedAsIs() =>
        Assert.Equal("[{\"loc\":[\"body\",\"model\"],\"msg\":\"field required\"}]",
            ApiHttp.ExtractErrorMessage("{\"detail\":[{\"loc\":[\"body\",\"model\"],\"msg\":\"field required\"}]}"));

    [Fact]
    public void ErrorWithoutMessageFallsThrough() =>
        Assert.Equal("Quota", ApiHttp.ExtractErrorMessage("{\"error\":{\"code\":\"429\"},\"message\":\"Quota\"}"));

    [Fact]
    public void OtherwiseFirst300Characters()
    {
        Assert.Equal(new string('x', 300), ApiHttp.ExtractErrorMessage(new string('x', 500)));
        var unknownJson = "{\"code\":\"oops\"}";
        Assert.Equal(unknownJson, ApiHttp.ExtractErrorMessage(unknownJson));
        Assert.Equal("erreur inconnue", ApiHttp.ExtractErrorMessage("  "));
    }

    [Fact]
    public void RedactKeyReplacesKeyByPreview()
    {
        Assert.Equal("clé abc…wxyz refusée", ApiHttp.RedactKey("clé abcdefghijklmnopqrstuvwxyz refusée", "abcdefghijklmnopqrstuvwxyz"));
        Assert.Equal("rien à masquer", ApiHttp.RedactKey("rien à masquer", "abcdefghijklmnop"));
        Assert.Equal("texte", ApiHttp.RedactKey("texte", null));
    }
}
