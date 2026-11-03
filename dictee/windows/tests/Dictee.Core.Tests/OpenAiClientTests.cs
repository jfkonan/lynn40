using System.Net;
using System.Text;
using System.Text.Json;

namespace Dictee.Core.Tests;

public class MultipartFormDataTests
{
    [Fact]
    public void BodyContainsFieldsFileAndClosingBoundary()
    {
        var form = new MultipartFormData("XYZ");
        form.AddField("model", "gpt-4o-transcribe");
        form.AddFile("file", "a.wav", "audio/wav", "AUDIO"u8);
        var body = Encoding.UTF8.GetString(form.ToArray());

        Assert.Equal("multipart/form-data; boundary=XYZ", form.ContentType);
        Assert.StartsWith("--XYZ\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n", body);
        Assert.Contains("name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\nAUDIO\r\n", body);
        Assert.EndsWith("--XYZ--\r\n", body);
    }
}

public class OpenAiClientRequestTests
{
    private static string BodyOf(HttpRequestMessage request) => request.Content!.ReadAsStringAsync().GetAwaiter().GetResult();

    [Fact]
    public void TranscriptionRequestHasHeadersAndFields()
    {
        using var request = OpenAiClient.BuildTranscriptionRequest(OpenAiClient.DefaultBaseUri, "sk-test", "RIFF"u8,
            "dictee.wav", "gpt-4o-transcribe", "fr", "OHADA, AUSCGIE", boundary: "B");
        var body = BodyOf(request);

        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("https://api.openai.com/v1/audio/transcriptions", request.RequestUri!.ToString());
        Assert.Equal("Bearer sk-test", request.Headers.Authorization!.ToString());
        Assert.Equal("multipart/form-data; boundary=B", request.Content!.Headers.ContentType!.ToString());
        Assert.Contains("--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n", body);
        Assert.Contains("name=\"response_format\"\r\n\r\njson\r\n", body);
        Assert.Contains("name=\"language\"\r\n\r\nfr\r\n", body);
        Assert.Contains("name=\"prompt\"\r\n\r\nOHADA, AUSCGIE\r\n", body);
        Assert.Contains("name=\"file\"; filename=\"dictee.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n", body);
        Assert.EndsWith("--B--\r\n", body);
    }

    [Theory]
    [InlineData("", "")]
    [InlineData("   ", " \n ")]
    [InlineData(null, null)]
    public void EmptyLanguageAndPromptAreOmitted(string? language, string? prompt)
    {
        using var request = OpenAiClient.BuildTranscriptionRequest(OpenAiClient.DefaultBaseUri, "sk-test", "RIFF"u8,
            "a.wav", "whisper-1", language, prompt);
        var body = BodyOf(request);

        Assert.DoesNotContain("name=\"language\"", body);
        Assert.DoesNotContain("name=\"prompt\"", body);
        Assert.Contains("name=\"model\"\r\n\r\nwhisper-1\r\n", body);
    }

    [Fact]
    public void LanguageAndPromptAreTrimmed()
    {
        using var request = OpenAiClient.BuildTranscriptionRequest(OpenAiClient.DefaultBaseUri, "sk-test", "x"u8,
            "a.wav", "m", "  en ", " SARL \n");
        var body = BodyOf(request);
        Assert.Contains("name=\"language\"\r\n\r\nen\r\n", body);
        Assert.Contains("name=\"prompt\"\r\n\r\nSARL\r\n", body);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    public void MissingKeyThrowsSpecMessage(string? key)
    {
        var ex = Assert.Throws<DicteeException>(() =>
            OpenAiClient.BuildTranscriptionRequest(OpenAiClient.DefaultBaseUri, key!, "x"u8, "a.wav", "m", null, null));
        Assert.Equal("Clé API OpenAI manquante. Ajoutez-la dans les réglages de Dictée.", ex.Message);
        Assert.Throws<DicteeException>(() =>
            OpenAiClient.BuildCleanupRequest(OpenAiClient.DefaultBaseUri, key!, "texte", "gpt-4o-mini", ""));
    }

    [Fact]
    public void CleanupRequestHasMessagesAndHeaders()
    {
        using var request = OpenAiClient.BuildCleanupRequest(OpenAiClient.DefaultBaseUri, "sk-test", "bonjour euh", "gpt-4o-mini", "OHADA");
        using var json = JsonDocument.Parse(BodyOf(request));
        var root = json.RootElement;

        Assert.Equal("https://api.openai.com/v1/chat/completions", request.RequestUri!.ToString());
        Assert.Equal("Bearer sk-test", request.Headers.Authorization!.ToString());
        Assert.Equal("application/json", request.Content!.Headers.ContentType!.MediaType);
        Assert.Equal("gpt-4o-mini", root.GetProperty("model").GetString());
        var messages = root.GetProperty("messages");
        Assert.Equal(2, messages.GetArrayLength());
        Assert.Equal("system", messages[0].GetProperty("role").GetString());
        Assert.Equal(OpenAiClient.CleanupInstructions("OHADA"), messages[0].GetProperty("content").GetString());
        Assert.Equal("user", messages[1].GetProperty("role").GetString());
        Assert.Equal("bonjour euh", messages[1].GetProperty("content").GetString());
    }

    [Theory]
    [InlineData("gpt-4o-mini", true)]
    [InlineData("gpt-4.1-mini", true)]
    [InlineData("gpt-4o", true)]
    [InlineData("o4-mini", false)]
    [InlineData("o3", false)]
    [InlineData("gpt-5-mini", false)]
    public void TemperatureOnlyForGpt4Models(string model, bool expected)
    {
        Assert.Equal(expected, OpenAiClient.ShouldSendTemperature(model));
        using var request = OpenAiClient.BuildCleanupRequest(OpenAiClient.DefaultBaseUri, "sk-test", "x", model, "");
        using var json = JsonDocument.Parse(BodyOf(request));
        Assert.Equal(expected, json.RootElement.TryGetProperty("temperature", out var temperature));
        if (expected) Assert.Equal(0, temperature.GetInt32());
    }
}

public class OpenAiClientParsingTests
{
    [Fact]
    public void ParsesTranscription()
    {
        Assert.Equal("Bonjour", OpenAiClient.ParseTranscription("{\"text\":\"Bonjour\"}"));
        Assert.Equal("", OpenAiClient.ParseTranscription("{\"text\":\"\"}"));
    }

    [Theory]
    [InlineData("oops")]
    [InlineData("{}")]
    [InlineData("{\"text\":3}")]
    [InlineData("[]")]
    public void InvalidTranscriptionThrows(string json)
    {
        var ex = Assert.Throws<DicteeException>(() => OpenAiClient.ParseTranscription(json));
        Assert.Equal("Réponse OpenAI illisible.", ex.Message);
    }

    [Fact]
    public void ParsesChatAndTrims()
    {
        Assert.Equal("Bonjour.", OpenAiClient.ParseChat("{\"choices\":[{\"message\":{\"content\":\"  Bonjour.\\n\"}}]}"));
    }

    [Theory]
    [InlineData("{\"choices\":[]}")]
    [InlineData("{\"choices\":[{\"message\":{\"content\":null}}]}")]
    [InlineData("pas du json")]
    public void InvalidChatThrows(string json)
    {
        Assert.Throws<DicteeException>(() => OpenAiClient.ParseChat(json));
    }

    [Fact]
    public void ExtractsErrorMessage()
    {
        Assert.Equal("Incorrect API key provided.",
            OpenAiClient.ExtractErrorMessage("{\"error\":{\"message\":\"Incorrect API key provided.\",\"type\":\"invalid_request_error\"}}"));
    }

    [Fact]
    public void ErrorMessageRedactsPartialApiKey()
    {
        var message = OpenAiClient.ExtractErrorMessage(
            "{\"error\":{\"message\":\"Incorrect API key provided: sk-proj-ab12****wxyz. You can find your API key at https://platform.openai.com/account/api-keys.\"}}");
        Assert.DoesNotContain("ab12", message);
        Assert.StartsWith("Incorrect API key provided: sk-…wxyz.", message);
    }

    [Fact]
    public void ErrorMessageFallsBackToFirst300Characters()
    {
        var body = new string('x', 500);
        Assert.Equal(new string('x', 300), OpenAiClient.ExtractErrorMessage(body));
        Assert.Equal("<html>Bad gateway</html>", OpenAiClient.ExtractErrorMessage("<html>Bad gateway</html>"));
        Assert.Equal("erreur inconnue", OpenAiClient.ExtractErrorMessage(""));
    }

    [Fact]
    public void HttpErrorMessageFormat()
    {
        Assert.Equal("Erreur OpenAI (401) : Clé invalide", DicteeMessages.Http(TranscriptionProvider.OpenAI, 401, "Clé invalide"));
    }

    [Theory]
    [InlineData("a.wav", "audio/wav")]
    [InlineData("A.WAV", "audio/wav")]
    [InlineData("a.mp3", "audio/mpeg")]
    [InlineData("a.bin", "application/octet-stream")]
    public void MimeTypes(string fileName, string expected) => Assert.Equal(expected, OpenAiClient.MimeType(fileName));
}

public class OpenAiClientHttpTests
{
    [Fact]
    public async Task HttpErrorUsesOpenAiMessageAndNeverLeaksKey()
    {
        var handler = new FakeHttpHandler().Respond(HttpStatusCode.Unauthorized,
            "{\"error\":{\"message\":\"Incorrect API key provided.\"}}");
        var client = new OpenAiClient(OpenAiClient.CreateHttpClient(handler), "sk-secret-1234");
        var path = TempWav.Create();

        var ex = await Assert.ThrowsAsync<ApiHttpException>(() => client.TranscribeAsync(path, "gpt-4o-transcribe", "fr", ""));

        Assert.Equal(401, ex.StatusCode);
        Assert.Equal("Erreur OpenAI (401) : Incorrect API key provided.", ex.Message);
        Assert.DoesNotContain("sk-secret", ex.Message);
        Assert.Equal("Bearer sk-secret-1234", handler.Requests.Single().Authorization);
        File.Delete(path);
    }

    [Fact]
    public async Task NetworkFailureBecomesReadableError()
    {
        var handler = new FakeHttpHandler().Throw(new HttpRequestException("Hôte inconnu"));
        var client = new OpenAiClient(OpenAiClient.CreateHttpClient(handler), "sk-test");

        var ex = await Assert.ThrowsAsync<DicteeException>(() => client.CleanUpAsync("x", "gpt-4o-mini", ""));
        Assert.Equal("Connexion à OpenAI impossible : Hôte inconnu", ex.Message);
    }

    [Fact]
    public async Task TimeoutBecomesReadableError()
    {
        var handler = new FakeHttpHandler().Throw(new TaskCanceledException("délai"));
        var client = new OpenAiClient(OpenAiClient.CreateHttpClient(handler), "sk-test");

        var ex = await Assert.ThrowsAsync<DicteeException>(() => client.CleanUpAsync("x", "gpt-4o-mini", ""));
        Assert.Equal("OpenAI ne répond pas (délai dépassé). Réessayez.", ex.Message);
    }

    [Fact]
    public void HttpClientHasNoGlobalTimeout()
    {
        using var http = OpenAiClient.CreateHttpClient();
        Assert.Equal(Timeout.InfiniteTimeSpan, http.Timeout);
    }

    [Fact]
    public void TimeoutsMatchSpec()
    {
        Assert.Equal(TimeSpan.FromSeconds(120), DicteeConstants.TranscriptionTimeout);
        Assert.Equal(TimeSpan.FromSeconds(60), DicteeConstants.CleanupTimeout);
        Assert.Equal(16_000, DicteeConstants.SampleRate);
        Assert.Equal(TimeSpan.FromMinutes(12), DicteeConstants.MaxRecordingDuration);
        Assert.Equal(TimeSpan.FromMilliseconds(300), DicteeConstants.MinRecordingDuration);
    }
}

internal static class TempWav
{
    public static string Create()
    {
        var path = Path.Combine(Path.GetTempPath(), $"dictee-test-{Guid.NewGuid():N}.wav");
        File.WriteAllBytes(path, "RIFF....WAVE"u8.ToArray());
        return path;
    }
}
