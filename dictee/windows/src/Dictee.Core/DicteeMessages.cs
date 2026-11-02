namespace Dictee.Core;

/// <summary>Messages affichés à l'utilisateur (textes imposés par SPEC.md).</summary>
public static class DicteeMessages
{
    public const string MissingApiKey = "Clé API OpenAI manquante. Ajoutez-la dans les réglages de Dictée.";
    public const string NoSpeech = "Aucune parole détectée.";
    public const string InvalidResponse = "Réponse OpenAI illisible.";
    public const string Timeout = "OpenAI ne répond pas (délai dépassé). Réessayez.";
    public const string TextCopied = "Texte copié : collez-le avec Ctrl+V";

    public static string Http(int statusCode, string message) => $"Erreur OpenAI ({statusCode}) : {message}";

    public static string Network(string detail) => $"Connexion à OpenAI impossible : {detail}";
}

/// <summary>Erreur dont le message peut être montré tel quel à l'utilisateur.</summary>
public class DicteeException : Exception
{
    public DicteeException(string message, Exception? inner = null) : base(message, inner) { }
}

/// <summary>Réponse HTTP non 2xx d'OpenAI.</summary>
public sealed class OpenAiHttpException : DicteeException
{
    public OpenAiHttpException(int statusCode, string apiMessage)
        : base(DicteeMessages.Http(statusCode, apiMessage))
    {
        StatusCode = statusCode;
    }

    public int StatusCode { get; }
}
