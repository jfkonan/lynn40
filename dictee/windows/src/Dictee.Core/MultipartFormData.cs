using System.Text;

namespace Dictee.Core;

/// <summary>
/// Corps multipart/form-data écrit à la main, comme sur iOS : on maîtrise exactement les en-têtes
/// de chaque partie (noms entre guillemets, pas de Content-Type parasite sur les champs texte).
/// </summary>
public sealed class MultipartFormData
{
    private readonly MemoryStream _body = new();

    public MultipartFormData(string? boundary = null)
    {
        Boundary = boundary ?? "Dictee-" + Guid.NewGuid().ToString("N");
    }

    public string Boundary { get; }

    public string ContentType => $"multipart/form-data; boundary={Boundary}";

    /// <param name="contentType">Type de la partie (ex. <c>application/json</c>) ; omis par défaut, comme pour un champ texte.</param>
    public void AddField(string name, string value, string? contentType = null)
    {
        Append($"--{Boundary}\r\n");
        Append($"Content-Disposition: form-data; name=\"{name}\"\r\n");
        if (contentType is not null) Append($"Content-Type: {contentType}\r\n");
        Append("\r\n");
        Append($"{value}\r\n");
    }

    public void AddFile(string name, string fileName, string mimeType, ReadOnlySpan<byte> data)
    {
        Append($"--{Boundary}\r\n");
        Append($"Content-Disposition: form-data; name=\"{name}\"; filename=\"{fileName}\"\r\n");
        Append($"Content-Type: {mimeType}\r\n\r\n");
        _body.Write(data);
        Append("\r\n");
    }

    /// <summary>Corps complet, frontière de fin comprise.</summary>
    public byte[] ToArray()
    {
        var closing = Encoding.UTF8.GetBytes($"--{Boundary}--\r\n");
        var result = new byte[_body.Length + closing.Length];
        _body.GetBuffer().AsSpan(0, (int)_body.Length).CopyTo(result);
        closing.CopyTo(result, (int)_body.Length);
        return result;
    }

    private void Append(string text) => _body.Write(Encoding.UTF8.GetBytes(text));
}
