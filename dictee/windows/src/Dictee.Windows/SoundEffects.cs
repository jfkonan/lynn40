using System.Media;

namespace Dictee.Windows;

/// <summary>Deux sons discrets générés en mémoire (aucun fichier) : début (montant) et fin (descendant).</summary>
internal sealed class SoundEffects : IDisposable
{
    private readonly SoundPlayer _start = Create(660, 880);
    private readonly SoundPlayer _stop = Create(880, 660);

    public void PlayStart() => Play(_start);
    public void PlayStop() => Play(_stop);

    public void Dispose()
    {
        _start.Dispose();
        _stop.Dispose();
    }

    private static void Play(SoundPlayer player)
    {
        try { player.Play(); } // asynchrone : ne bloque pas le fil d'interface
        catch (Exception ex) when (ex is InvalidOperationException or TimeoutException) { }
    }

    /// <summary>Deux notes brèves de 60 ms, à faible volume, avec fondu pour éviter les clics.</summary>
    private static SoundPlayer Create(double firstHz, double secondHz)
    {
        const int sampleRate = 22_050;
        const double noteSeconds = 0.06;
        const double volume = 0.18;
        var noteSamples = (int)(sampleRate * noteSeconds);
        var samples = new short[noteSamples * 2];
        for (var i = 0; i < samples.Length; i++)
        {
            var hz = i < noteSamples ? firstHz : secondHz;
            var n = i % noteSamples;
            var fade = Math.Min(1.0, Math.Min(n, noteSamples - n) / (sampleRate * 0.008));
            samples[i] = (short)(Math.Sin(2 * Math.PI * hz * i / sampleRate) * volume * fade * short.MaxValue);
        }

        var stream = new MemoryStream();
        using (var writer = new BinaryWriter(stream, System.Text.Encoding.ASCII, leaveOpen: true))
        {
            var dataBytes = samples.Length * 2;
            writer.Write("RIFF"u8); writer.Write(36 + dataBytes); writer.Write("WAVE"u8);
            writer.Write("fmt "u8); writer.Write(16); writer.Write((short)1); writer.Write((short)1);
            writer.Write(sampleRate); writer.Write(sampleRate * 2); writer.Write((short)2); writer.Write((short)16);
            writer.Write("data"u8); writer.Write(dataBytes);
            foreach (var s in samples) writer.Write(s);
        }
        stream.Position = 0;
        var player = new SoundPlayer(stream);
        player.Load();
        return player;
    }
}
