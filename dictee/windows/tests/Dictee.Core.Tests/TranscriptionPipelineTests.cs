using System.Net;

namespace Dictee.Core.Tests;

public class TranscriptionPipelineTests
{
    private static (TranscriptionPipeline Pipeline, FakeHttpHandler Handler) Make(string? key = "sk-test")
    {
        var handler = new FakeHttpHandler();
        return (new TranscriptionPipeline(new OpenAiClient(OpenAiClient.CreateHttpClient(handler), key)), handler);
    }

    private const string Chat = "{{\"choices\":[{{\"message\":{{\"content\":\"{0}\"}}}}]}}";

    [Fact]
    public async Task TranscribesWithoutCleanupByDefault()
    {
        var (pipeline, handler) = Make();
        handler.Respond(HttpStatusCode.OK, "{\"text\":\"  bonjour le monde \"}");
        var path = TempWav.Create();

        var text = await pipeline.RunAsync(path, new DicteeSettings());

        Assert.Equal("bonjour le monde", text);
        Assert.Single(handler.Requests);
        Assert.EndsWith("/audio/transcriptions", handler.Requests[0].Uri.AbsolutePath);
        Assert.Contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n", handler.Requests[0].Body);
        Assert.Contains("name=\"language\"\r\n\r\nfr\r\n", handler.Requests[0].Body);
        Assert.Contains("name=\"prompt\"\r\n\r\nOHADA, AUSCGIE", handler.Requests[0].Body);
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task BlankModelUsesDefault()
    {
        var (pipeline, handler) = Make();
        handler.Respond(HttpStatusCode.OK, "{\"text\":\"ok\"}");
        await pipeline.RunAsync(TempWav.Create(), new DicteeSettings { Model = "  " });
        Assert.Contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n", handler.Requests[0].Body);
    }

    [Fact]
    public async Task UsesCleanedTextWhenEnabled()
    {
        var (pipeline, handler) = Make();
        handler.Respond(HttpStatusCode.OK, "{\"text\":\"euh bonjour\"}")
               .Respond(HttpStatusCode.OK, string.Format(Chat, "Bonjour."));
        var path = TempWav.Create();

        var text = await pipeline.RunAsync(path, new DicteeSettings { CleanupEnabled = true });

        Assert.Equal("Bonjour.", text);
        Assert.Equal(2, handler.Requests.Count);
        Assert.EndsWith("/chat/completions", handler.Requests[1].Uri.AbsolutePath);
        Assert.Contains("\"model\":\"gpt-4o-mini\"", handler.Requests[1].Body);
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task FallsBackToRawTextWhenCleanupFails()
    {
        var (pipeline, handler) = Make();
        handler.Respond(HttpStatusCode.OK, "{\"text\":\"euh bonjour\"}")
               .Respond(HttpStatusCode.InternalServerError, "{\"error\":{\"message\":\"panne\"}}");
        var path = TempWav.Create();

        Assert.Equal("euh bonjour", await pipeline.RunAsync(path, new DicteeSettings { CleanupEnabled = true }));
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task FallsBackToRawTextWhenCleanupIsEmpty()
    {
        var (pipeline, handler) = Make();
        handler.Respond(HttpStatusCode.OK, "{\"text\":\"euh bonjour\"}")
               .Respond(HttpStatusCode.OK, string.Format(Chat, "   "));

        Assert.Equal("euh bonjour", await pipeline.RunAsync(TempWav.Create(), new DicteeSettings { CleanupEnabled = true }));
    }

    [Fact]
    public async Task FallsBackToRawTextWhenCleanupResponseIsUnreadable()
    {
        var (pipeline, handler) = Make();
        handler.Respond(HttpStatusCode.OK, "{\"text\":\"brut\"}").Respond(HttpStatusCode.OK, "n'importe quoi");
        Assert.Equal("brut", await pipeline.RunAsync(TempWav.Create(), new DicteeSettings { CleanupEnabled = true }));
    }

    [Theory]
    [InlineData("{\"text\":\"\"}")]
    [InlineData("{\"text\":\"  \\n \"}")]
    public async Task EmptyTranscriptionIsNoSpeechError(string body)
    {
        var (pipeline, handler) = Make();
        handler.Respond(HttpStatusCode.OK, body);
        var path = TempWav.Create();

        var ex = await Assert.ThrowsAsync<DicteeException>(() => pipeline.RunAsync(path, new DicteeSettings { CleanupEnabled = true }));

        Assert.Equal("Aucune parole détectée.", ex.Message);
        Assert.Single(handler.Requests); // pas de nettoyage d'un texte vide
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task HttpErrorDeletesFile()
    {
        var (pipeline, handler) = Make();
        handler.Respond(HttpStatusCode.TooManyRequests, "{\"error\":{\"message\":\"Quota dépassé\"}}");
        var path = TempWav.Create();

        var ex = await Assert.ThrowsAsync<ApiHttpException>(() => pipeline.RunAsync(path, new DicteeSettings()));

        Assert.Equal("Erreur OpenAI (429) : Quota dépassé", ex.Message);
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task MissingKeyDeletesFileWithoutNetwork()
    {
        var (pipeline, handler) = Make(key: null);
        var path = TempWav.Create();

        var ex = await Assert.ThrowsAsync<DicteeException>(() => pipeline.RunAsync(path, new DicteeSettings()));

        Assert.Equal("Clé API OpenAI manquante. Ajoutez-la dans les réglages de Dictée.", ex.Message);
        Assert.Empty(handler.Requests);
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task CancellationDeletesFile()
    {
        var (pipeline, handler) = Make();
        handler.Respond(HttpStatusCode.OK, "{\"text\":\"x\"}");
        var path = TempWav.Create();
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pipeline.RunAsync(path, new DicteeSettings(), cts.Token));
        Assert.False(File.Exists(path));
    }

    // ---- Autres fournisseurs : le nettoyage reste chez OpenAI ----

    private static (TranscriptionPipeline Pipeline, FakeHttpHandler Handler) MakeFor(TranscriptionProvider provider,
        string? providerKey, string? openAiKey)
    {
        var handler = new FakeHttpHandler();
        var http = OpenAiClient.CreateHttpClient(handler);
        var cleaner = openAiKey is null ? null : new OpenAiClient(http, openAiKey);
        return (new TranscriptionPipeline(TranscriptionClients.Create(provider, http, providerKey), cleaner), handler);
    }

    [Fact]
    public async Task MistralTranscriptionWithCleanupSkippedWithoutOpenAiKey()
    {
        var (pipeline, handler) = MakeFor(TranscriptionProvider.Mistral, "mistral-key-0123456789", openAiKey: null);
        handler.Respond(HttpStatusCode.OK, "{\"text\":\" euh bonjour \"}");
        var path = TempWav.Create();

        var text = await pipeline.RunAsync(path, new DicteeSettings { Provider = "mistral", CleanupEnabled = true });

        Assert.Equal("euh bonjour", text);
        Assert.Single(handler.Requests); // aucun appel de nettoyage, aucune erreur
        Assert.Equal("https://api.mistral.ai/v1/audio/transcriptions", handler.Requests[0].Uri.ToString());
        Assert.Equal("Bearer mistral-key-0123456789", handler.Requests[0].Authorization);
        Assert.Contains("name=\"model\"\r\n\r\nvoxtral-small-transcribe-3\r\n", handler.Requests[0].Body);
        Assert.Contains("name=\"context_bias\"\r\n\r\nOHADA\r\n", handler.Requests[0].Body);
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task EmptyOpenAiKeySkipsCleanup()
    {
        var (pipeline, handler) = MakeFor(TranscriptionProvider.Microsoft, "azure-key-0123456789", openAiKey: "  ");
        handler.Respond(HttpStatusCode.OK, "{\"combinedPhrases\":[{\"text\":\"euh bonjour\"}]}");

        var text = await pipeline.RunAsync(TempWav.Create(), new DicteeSettings { Provider = "microsoft", CleanupEnabled = true });

        Assert.Equal("euh bonjour", text);
        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task AzureTranscriptionThenCleanupAtOpenAiWithOpenAiKey()
    {
        var (pipeline, handler) = MakeFor(TranscriptionProvider.Microsoft, "azure-key-0123456789", openAiKey: "sk-openai");
        handler.Respond(HttpStatusCode.OK, "{\"combinedPhrases\":[{\"text\":\"euh bonjour\"}]}")
               .Respond(HttpStatusCode.OK, string.Format(Chat, "Bonjour."));
        var path = TempWav.Create();

        var text = await pipeline.RunAsync(path, new DicteeSettings { Provider = "microsoft", AzureRegion = "westeurope", CleanupEnabled = true });

        Assert.Equal("Bonjour.", text);
        Assert.Equal(2, handler.Requests.Count);
        Assert.Equal("westeurope.api.cognitive.microsoft.com", handler.Requests[0].Uri.Host);
        Assert.Equal("azure-key-0123456789", handler.Requests[0].Headers["Ocp-Apim-Subscription-Key"]);
        Assert.Equal("https://api.openai.com/v1/chat/completions", handler.Requests[1].Uri.ToString());
        Assert.Equal("Bearer sk-openai", handler.Requests[1].Authorization);
        Assert.False(File.Exists(path));
    }

    [Theory]
    [InlineData(TranscriptionProvider.Mistral, "Mistral")]
    [InlineData(TranscriptionProvider.Microsoft, "Microsoft")]
    public async Task MissingProviderKeyNamesProviderWithoutNetwork(TranscriptionProvider provider, string name)
    {
        var (pipeline, handler) = MakeFor(provider, providerKey: null, openAiKey: "sk-openai");
        var path = TempWav.Create();

        var ex = await Assert.ThrowsAsync<DicteeException>(() =>
            pipeline.RunAsync(path, new DicteeSettings { Provider = TranscriptionProviders.Id(provider), CleanupEnabled = true }));

        Assert.Equal($"Clé API {name} manquante. Ajoutez-la dans les réglages de Dictée.", ex.Message);
        Assert.Empty(handler.Requests);
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task MistralHttpErrorNamesProviderAndDeletesFile()
    {
        var (pipeline, handler) = MakeFor(TranscriptionProvider.Mistral, "mistral-key-0123456789", openAiKey: null);
        handler.Respond(HttpStatusCode.UnprocessableEntity, "{\"detail\":\"Invalid model: voxtral-x\"}");
        var path = TempWav.Create();

        var ex = await Assert.ThrowsAsync<ApiHttpException>(() => pipeline.RunAsync(path, new DicteeSettings { Provider = "mistral" }));

        Assert.Equal("Erreur Mistral (422) : Invalid model: voxtral-x", ex.Message);
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task EmptyAzureTranscriptionIsNoSpeech()
    {
        var (pipeline, handler) = MakeFor(TranscriptionProvider.Microsoft, "azure-key-0123456789", openAiKey: "sk-openai");
        handler.Respond(HttpStatusCode.OK, "{\"combinedPhrases\":[],\"phrases\":[]}");

        var ex = await Assert.ThrowsAsync<DicteeException>(() =>
            pipeline.RunAsync(TempWav.Create(), new DicteeSettings { Provider = "microsoft", CleanupEnabled = true }));

        Assert.Equal("Aucune parole détectée.", ex.Message);
        Assert.Single(handler.Requests);
    }

    [Fact]
    public void TryDeleteNeverThrows()
    {
        TranscriptionPipeline.TryDelete(null);
        TranscriptionPipeline.TryDelete(Path.Combine(Path.GetTempPath(), "inexistant-" + Guid.NewGuid()));
    }
}
