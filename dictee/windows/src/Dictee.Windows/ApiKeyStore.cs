using System.Security.Cryptography;
using System.Text;

namespace Dictee.Windows;

/// <summary>
/// Clé API chiffrée par DPAPI (portée utilisateur courant) dans %APPDATA%\Dictee\apikey.bin (SPEC.md §4).
/// Seul ce compte Windows, sur cette machine, peut la déchiffrer.
/// </summary>
internal sealed class ApiKeyStore
{
    // Entropie propre à l'app : un autre programme du même utilisateur doit la connaître pour déchiffrer.
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("Dictee.ApiKey.v1");

    private readonly string _path;

    public ApiKeyStore(string? path = null) => _path = path ?? AppPaths.ApiKeyFile;

    public bool HasKey => !string.IsNullOrWhiteSpace(Load());

    /// <summary>Clé déchiffrée, ou null si absente ou illisible (profil copié sur une autre machine, par exemple).</summary>
    public string? Load()
    {
        try
        {
            if (!File.Exists(_path)) return null;
            var clear = ProtectedData.Unprotect(File.ReadAllBytes(_path), Entropy, DataProtectionScope.CurrentUser);
            var key = Encoding.UTF8.GetString(clear).Trim();
            CryptographicOperations.ZeroMemory(clear);
            return key.Length == 0 ? null : key;
        }
        catch (Exception ex) when (ex is CryptographicException or IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public void Save(string apiKey)
    {
        var key = apiKey.Trim();
        if (key.Length == 0)
        {
            Delete();
            return;
        }
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var clear = Encoding.UTF8.GetBytes(key);
        var protectedBytes = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser);
        CryptographicOperations.ZeroMemory(clear);
        var temp = _path + ".tmp";
        File.WriteAllBytes(temp, protectedBytes);
        File.Move(temp, _path, overwrite: true);
    }

    public void Delete()
    {
        try { File.Delete(_path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
