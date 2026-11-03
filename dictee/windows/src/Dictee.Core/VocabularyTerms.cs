namespace Dictee.Core;

/// <summary>Découpage du vocabulaire en termes (SPEC.md §2 bis), pour Mistral et Microsoft.</summary>
public static class VocabularyTerms
{
    public const int MaxTerms = 100;

    private static readonly char[] Separators = [',', ';', '\n', '\r'];

    /// <summary>
    /// Termes séparés par virgules, points-virgules ou retours à la ligne ; espaces de bord retirées, termes vides ignorés,
    /// doublons retirés en gardant le premier ; 100 termes au maximum.
    /// </summary>
    public static IReadOnlyList<string> Split(string? vocabulary)
    {
        if (string.IsNullOrWhiteSpace(vocabulary)) return [];
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var terms = new List<string>();
        foreach (var part in vocabulary.Split(Separators, StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            if (!seen.Add(part)) continue;
            terms.Add(part);
            if (terms.Count == MaxTerms) break;
        }
        return terms;
    }
}
