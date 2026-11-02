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
        Assert.Contains("name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n", handler.Requests[0].Body);
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
        Assert.Contains("name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n", handler.Requests[0].Body);
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

        var ex = await Assert.ThrowsAsync<OpenAiHttpException>(() => pipeline.RunAsync(path, new DicteeSettings()));

        Assert.Equal("Erreur OpenAI (429) : Quota dépassé", ex.Message);
        Assert.False(File.Exists(path));
    }

    [Fact]
    public async Task MissingKeyDeletesFileWithoutNetwork()
    {
        var (pipeline, handler) = Make(key: null);
        var path = TempWav.Create();

        var ex = await Assert.ThrowsAsync<DicteeException>(() => pipeline.RunAsync(path, new DicteeSettings()));

        Assert.Equal(DicteeMessages.MissingApiKey, ex.Message);
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

    [Fact]
    public void TryDeleteNeverThrows()
    {
        TranscriptionPipeline.TryDelete(null);
        TranscriptionPipeline.TryDelete(Path.Combine(Path.GetTempPath(), "inexistant-" + Guid.NewGuid()));
    }
}
