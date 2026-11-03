namespace Dictee.Core;

/// <summary>Locale Azure déduite du réglage <c>language</c> (SPEC.md §2 bis, fournisseur <c>microsoft</c>).</summary>
public static class AzureLocale
{
    private static readonly Dictionary<string, string> Known = new(StringComparer.OrdinalIgnoreCase)
    {
        ["fr"] = "fr-FR",
        ["en"] = "en-US",
        ["es"] = "es-ES",
        ["de"] = "de-DE",
        ["it"] = "it-IT",
        ["pt"] = "pt-BR",
        ["nl"] = "nl-NL",
        ["ar"] = "ar-SA",
    };

    /// <summary>
    /// « fr » → « fr-FR » (table du cahier des charges) ; valeur contenant déjà « - » reprise telle quelle ;
    /// autre code à 2 lettres « xx » → « xx-XX » ; vide → null (clé <c>locales</c> omise).
    /// Une valeur d'une autre forme est transmise telle quelle : Azure signalera l'erreur.
    /// </summary>
    public static string? FromLanguage(string? language)
    {
        var value = language?.Trim() ?? "";
        if (value.Length == 0) return null;
        if (value.Contains('-')) return value;
        if (Known.TryGetValue(value, out var locale)) return locale;
        if (value.Length == 2 && value.All(char.IsAsciiLetter))
            return $"{value.ToLowerInvariant()}-{value.ToUpperInvariant()}";
        return value;
    }
}
