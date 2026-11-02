namespace Dictee.Core;

/// <summary>Aperçu non sensible de la clé API (SPEC.md §4).</summary>
public static class ApiKeyHint
{
    /// <summary>« sk-…abcd » : 3 premiers et 4 derniers caractères ; « •••• » si la clé est trop courte ; null si absente.</summary>
    public static string? Preview(string? apiKey)
    {
        if (apiKey is null) return null;
        var key = apiKey.Trim();
        if (key.Length == 0) return null;
        if (key.Length <= 8) return "••••";
        return $"{key[..3]}…{key[^4..]}";
    }
}
