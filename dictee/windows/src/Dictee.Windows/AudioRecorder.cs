using System.Diagnostics;
using Dictee.Core;
using NAudio.Wave;

namespace Dictee.Windows;

/// <summary>Résultat d'un enregistrement terminé.</summary>
internal sealed record RecordingResult(string Path, TimeSpan Duration, long BytesWritten, bool AllSilent);

/// <summary>
/// Enregistrement micro en WAV PCM 16 bits, 16 kHz, mono (SPEC.md §2.1) dans %TEMP%, avec NAudio (WinMM).
/// Les tampons arrivent sur un fil de NAudio ; <see cref="Level"/> est lisible depuis n'importe quel fil.
/// </summary>
internal sealed class AudioRecorder : IDisposable
{
    private const int WaveMapper = -1; // périphérique d'entrée par défaut de Windows, qui suit ses changements

    private readonly object _lock = new();
    private readonly Stopwatch _stopwatch = new();
    private WaveInEvent? _waveIn;
    private WaveFileWriter? _writer;
    private string? _path;
    private TaskCompletionSource<Exception?>? _stopped;
    private bool _stopRequested;
    private long _bytesWritten;
    private int _peak;
    private volatile float _level;

    /// <summary>Le micro s'est arrêté de lui-même (débranché, par exemple).</summary>
    public event Action<Exception?>? Faulted;

    public bool IsRecording => _waveIn is not null;

    /// <summary>Niveau sonore lissé entre 0 et 1 (échelle en décibels, -50 dB → 0).</summary>
    public float Level => _level;

    /// <exception cref="DicteeException">Aucun micro, ou micro inaccessible.</exception>
    public void Start()
    {
        if (IsRecording) return;
        if (WaveInEvent.DeviceCount == 0)
            throw new DicteeException("Aucun micro détecté. Branchez un micro, puis vérifiez Paramètres Windows > Système > Son.");

        var format = new WaveFormat(DicteeConstants.SampleRate, DicteeConstants.BitsPerSample, DicteeConstants.Channels);
        _path = Path.Combine(Path.GetTempPath(), $"dictee-{Guid.NewGuid():N}.wav");
        _bytesWritten = 0;
        _peak = 0;
        _level = 0;
        _stopRequested = false;
        _stopped = new TaskCompletionSource<Exception?>(TaskCreationOptions.RunContinuationsAsynchronously);

        try
        {
            _writer = new WaveFileWriter(_path, format);
            _waveIn = new WaveInEvent { DeviceNumber = WaveMapper, WaveFormat = format, BufferMilliseconds = 50, NumberOfBuffers = 4 };
            _waveIn.DataAvailable += OnDataAvailable;
            _waveIn.RecordingStopped += OnRecordingStopped;
            _waveIn.StartRecording();
            _stopwatch.Restart();
        }
        catch (Exception ex)
        {
            var path = _path;
            Cleanup();
            TranscriptionPipeline.TryDelete(path);
            throw new DicteeException(
                "Micro inaccessible. Vérifiez qu'il est branché et que les applications de bureau peuvent l'utiliser " +
                "(Paramètres Windows > Confidentialité et sécurité > Microphone). Détail : " + ex.Message, ex);
        }
    }

    /// <summary>Arrête l'enregistrement et ferme le fichier WAV (en-tête finalisé).</summary>
    public async Task<RecordingResult> StopAsync()
    {
        var waveIn = _waveIn ?? throw new InvalidOperationException("Aucun enregistrement en cours.");
        var stopped = _stopped!;
        _stopRequested = true;
        _stopwatch.Stop();
        try { waveIn.StopRecording(); }
        catch (Exception) { /* périphérique déjà parti : on garde ce qui a été écrit */ }

        // RecordingStopped arrive dès que NAudio a rendu ses tampons ; garde-fou si le pilote ne répond pas.
        await Task.WhenAny(stopped.Task, Task.Delay(2000));

        var result = new RecordingResult(_path!, _stopwatch.Elapsed, Interlocked.Read(ref _bytesWritten), Volatile.Read(ref _peak) == 0);
        try
        {
            Cleanup();
        }
        catch
        {
            TranscriptionPipeline.TryDelete(result.Path); // sinon l'appelant perd le chemin et le WAV reste dans %TEMP%
            throw;
        }
        return result;
    }

    /// <summary>Arrête et supprime le fichier, sans transcription.</summary>
    public async Task CancelAsync()
    {
        if (!IsRecording) return;
        var result = await StopAsync();
        TranscriptionPipeline.TryDelete(result.Path);
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        lock (_lock)
        {
            if (_writer is null) return;
            _writer.Write(e.Buffer, 0, e.BytesRecorded);
        }
        Interlocked.Add(ref _bytesWritten, e.BytesRecorded);

        // Niveau RMS du tampon (échantillons 16 bits petit-boutistes).
        double sum = 0;
        var peak = 0;
        var count = e.BytesRecorded / 2;
        for (var i = 0; i < count; i++)
        {
            var sample = (short)(e.Buffer[2 * i] | (e.Buffer[2 * i + 1] << 8));
            sum += (double)sample * sample;
            var abs = Math.Abs((int)sample);
            if (abs > peak) peak = abs;
        }
        if (peak > Volatile.Read(ref _peak)) Volatile.Write(ref _peak, peak);
        if (count == 0) return;

        var rms = Math.Sqrt(sum / count) / 32768.0;
        var db = rms > 0 ? 20 * Math.Log10(rms) : -100;
        var target = (float)Math.Clamp((db + 50) / 50, 0, 1);
        // Montée rapide, descente douce : plus agréable à l'œil.
        _level = target > _level ? target : _level * 0.7f + target * 0.3f;
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        _stopped?.TrySetResult(e.Exception);
        if (!_stopRequested) Faulted?.Invoke(e.Exception);
    }

    private void Cleanup()
    {
        try
        {
            lock (_lock)
            {
                try { _writer?.Dispose(); } // écrit les tailles définitives dans l'en-tête WAV
                finally { _writer = null; }
            }
        }
        finally
        {
            // Même si l'écriture finale échoue (disque plein…), le micro est libéré.
            if (_waveIn is not null)
            {
                _waveIn.DataAvailable -= OnDataAvailable;
                _waveIn.RecordingStopped -= OnRecordingStopped;
                _waveIn.Dispose();
                _waveIn = null;
            }
            _level = 0;
        }
    }

    public void Dispose()
    {
        if (!IsRecording) return;
        var path = _path;
        _stopRequested = true;
        try { _waveIn?.StopRecording(); } catch (Exception) { }
        try { Cleanup(); }
        catch (Exception) { /* fermeture de l'app : on supprime quand même le fichier */ }
        TranscriptionPipeline.TryDelete(path);
    }
}
