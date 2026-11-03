namespace Dictee.Core;

/// <summary>Messages affichés à l'utilisateur (textes imposés par SPEC.md). « Fournisseur » = OpenAI, Mistral ou Microsoft.</summary>
public static class DicteeMessages
{
    public const string NoSpeech = "Aucune parole détectée.";
    public const string TextCopied = "Texte copié : collez-le avec Ctrl+V";
    public const string InvalidAzureRegion =
        "Région Azure invalide. Indiquez dans les réglages le nom de la région de votre ressource (ex. westeurope, swedencentral).";

    public static string MissingApiKey(TranscriptionProvider provider) =>
        $"Clé API {Name(provider)} manquante. Ajoutez-la dans les réglages de Dictée.";

    public static string InvalidResponse(TranscriptionProvider provider) => $"Réponse {Name(provider)} illisible.";

    public static string Timeout(TranscriptionProvider provider) => $"{Name(provider)} ne répond pas (délai dépassé). Réessayez.";

    public static string Http(TranscriptionProvider provider, int statusCode, string message) =>
        $"Erreur {Name(provider)} ({statusCode}) : {message}";

    public static string Network(TranscriptionProvider provider, string detail) => $"Connexion à {Name(provider)} impossible : {detail}";

    private static string Name(TranscriptionProvider provider) => TranscriptionProviders.DisplayName(provider);
}

/// <summary>Erreur dont le message peut être montré tel quel à l'utilisateur.</summary>
public class DicteeException : Exception
{
    public DicteeException(string message, Exception? inner = null) : base(message, inner) { }
}

/// <summary>Réponse HTTP non 2xx d'un fournisseur (OpenAI, Mistral ou Microsoft).</summary>
public sealed class ApiHttpException : DicteeException
{
    public ApiHttpException(TranscriptionProvider provider, int statusCode, string apiMessage)
        : base(DicteeMessages.Http(provider, statusCode, apiMessage))
    {
        Provider = provider;
        StatusCode = statusCode;
    }

    public TranscriptionProvider Provider { get; }

    public int StatusCode { get; }
}
