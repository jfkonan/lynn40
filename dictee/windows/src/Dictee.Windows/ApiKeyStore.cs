using System.Security.Cryptography;
using System.Text;
using Dictee.Core;

namespace Dictee.Windows;

/// <summary>
/// Une clé API par fournisseur, chiffrée par DPAPI (portée utilisateur courant) dans %APPDATA%\Dictee (SPEC.md §4) :
/// apikey.bin pour OpenAI (inchangé), apikey-mistral.bin, apikey-microsoft.bin.
/// Seul ce compte Windows, sur cette machine, peut les déchiffrer.
/// </summary>
internal sealed class ApiKeyStore
{
    // Entropie propre à l'app : un autre programme du même utilisateur doit la connaître pour déchiffrer.
    // Inchangée pour que la clé OpenAI déjà enregistrée reste lisible.
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("Dictee.ApiKey.v1");

    private readonly string _directory;

    public ApiKeyStore(string? directory = null) => _directory = directory ?? AppPaths.DataDirectory;

    public bool HasKey(TranscriptionProvider provider) => !string.IsNullOrWhiteSpace(Load(provider));

    /// <summary>Clé déchiffrée, ou null si absente ou illisible (profil copié sur une autre machine, par exemple).</summary>
    public string? Load(TranscriptionProvider provider)
    {
        var path = PathOf(provider);
        try
        {
            if (!File.Exists(path)) return null;
            var clear = ProtectedData.Unprotect(File.ReadAllBytes(path), Entropy, DataProtectionScope.CurrentUser);
            var key = Encoding.UTF8.GetString(clear).Trim();
            CryptographicOperations.ZeroMemory(clear);
            return key.Length == 0 ? null : key;
        }
        catch (Exception ex) when (ex is CryptographicException or IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public void Save(TranscriptionProvider provider, string apiKey)
    {
        var key = apiKey.Trim();
        if (key.Length == 0)
        {
            Delete(provider);
            return;
        }
        var path = PathOf(provider);
        Directory.CreateDirectory(_directory);
        var clear = Encoding.UTF8.GetBytes(key);
        var protectedBytes = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser);
        CryptographicOperations.ZeroMemory(clear);
        var temp = path + ".tmp";
        File.WriteAllBytes(temp, protectedBytes);
        File.Move(temp, path, overwrite: true);
    }

    public void Delete(TranscriptionProvider provider)
    {
        try { File.Delete(PathOf(provider)); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    private string PathOf(TranscriptionProvider provider) =>
        Path.Combine(_directory, TranscriptionProviders.ApiKeyFileName(provider));
}
