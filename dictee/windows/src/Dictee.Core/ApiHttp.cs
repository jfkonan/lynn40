using System.Text.Json;
using System.Text.RegularExpressions;

namespace Dictee.Core;

/// <summary>Envoi HTTP et lecture des erreurs, communs aux trois fournisseurs (SPEC.md §2.6).</summary>
public static class ApiHttp
{
    private const int MaxErrorLength = 300;

    /// <summary>Client HTTP sans délai global : chaque appel applique son propre délai (120 s ou 60 s).</summary>
    public static HttpClient CreateHttpClient(HttpMessageHandler? handler = null)
    {
        var client = handler is null ? new HttpClient() : new HttpClient(handler);
        client.Timeout = Timeout.InfiniteTimeSpan;
        return client;
    }

    /// <summary>Envoie la requête avec son délai propre ; renvoie le corps, ou lève un message prêt à afficher.</summary>
    /// <param name="apiKey">Clé utilisée, pour la masquer si le fournisseur la recopie dans son message d'erreur.</param>
    public static async Task<string> SendAsync(HttpClient http, HttpRequestMessage request, TimeSpan timeout,
        TranscriptionProvider provider, string apiKey, CancellationToken cancellationToken)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(timeout);
        try
        {
            using var response = await http.SendAsync(request, cts.Token).ConfigureAwait(false);
            var body = await response.Content.ReadAsStringAsync(cts.Token).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
                throw new ApiHttpException(provider, (int)response.StatusCode, RedactKey(ExtractErrorMessage(body), apiKey));
            return body;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // Délai propre à l'appel (ou délai global du HttpClient) dépassé.
            throw new DicteeException(DicteeMessages.Timeout(provider));
        }
        catch (HttpRequestException ex)
        {
            throw new DicteeException(DicteeMessages.Network(provider, RedactKey(ex.Message, apiKey)), ex);
        }
    }

    /// <summary>
    /// Message d'erreur du fournisseur : <c>error.message</c>, sinon <c>message</c> à la racine, sinon <c>detail</c>
    /// (texte, ou JSON recopié tel quel) ; à défaut, les 300 premiers caractères du corps.
    /// </summary>
    public static string ExtractErrorMessage(string? body)
    {
        if (string.IsNullOrWhiteSpace(body)) return "erreur inconnue";
        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            if (root.ValueKind == JsonValueKind.Object)
            {
                if (root.TryGetProperty("error", out var error) && error.ValueKind == JsonValueKind.Object &&
                    error.TryGetProperty("message", out var nested) && TextOf(nested) is { } nestedText)
                    return RedactKeys(nestedText);
                if (root.TryGetProperty("message", out var message) && TextOf(message) is { } messageText)
                    return RedactKeys(messageText);
                if (root.TryGetProperty("detail", out var detail) && TextOf(detail) is { } detailText)
                    return RedactKeys(detailText);
            }
        }
        catch (JsonException) { }
        return RedactKeys(Truncate(body));
    }

    /// <summary>Texte d'une chaîne non vide ; JSON brut (tronqué) d'un objet ou d'un tableau ; null sinon.</summary>
    private static string? TextOf(JsonElement element) => element.ValueKind switch
    {
        JsonValueKind.String when !string.IsNullOrWhiteSpace(element.GetString()) => element.GetString()!,
        JsonValueKind.Object or JsonValueKind.Array => Truncate(element.GetRawText()),
        _ => null,
    };

    private static string Truncate(string text) => text.Length <= MaxErrorLength ? text : text[..MaxErrorLength];

    /// <summary>
    /// Une erreur 401 d'OpenAI cite la clé partiellement masquée (« sk-proj-ab12****wxyz ») : on n'en garde que l'aperçu
    /// autorisé par SPEC §4, sans les premiers caractères.
    /// </summary>
    private static string RedactKeys(string text) =>
        Regex.Replace(text, @"sk-[A-Za-z0-9_*\-]{8,}", m => "sk-…" + m.Value[^4..]);

    /// <summary>La clé ne doit jamais apparaître dans un message d'erreur (SPEC §4) : remplacée par son aperçu.</summary>
    public static string RedactKey(string text, string? apiKey)
    {
        var key = apiKey?.Trim() ?? "";
        if (key.Length < 8 || !text.Contains(key, StringComparison.Ordinal)) return text;
        return text.Replace(key, ApiKeyHint.Preview(key), StringComparison.Ordinal);
    }

    /// <summary>Clé absente ou vide : message « Clé API &lt;Fournisseur&gt; manquante… ».</summary>
    public static void EnsureApiKey(string? apiKey, TranscriptionProvider provider)
    {
        if (string.IsNullOrWhiteSpace(apiKey)) throw new DicteeException(DicteeMessages.MissingApiKey(provider));
    }
}
