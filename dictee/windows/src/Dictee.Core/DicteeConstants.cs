namespace Dictee.Core;

/// <summary>Valeurs fixées par le cahier des charges (SPEC.md §2, §5, §6).</summary>
public static class DicteeConstants
{
    /// <summary>Format d'enregistrement : WAV PCM 16 bits, 16 kHz, mono.</summary>
    public const int SampleRate = 16_000;
    public const int BitsPerSample = 16;
    public const int Channels = 1;

    /// <summary>Au-delà, arrêt automatique et transcription (limite OpenAI : 25 Mo).</summary>
    public static readonly TimeSpan MaxRecordingDuration = TimeSpan.FromMinutes(12);

    /// <summary>En dessous, abandon silencieux, sans appel réseau.</summary>
    public static readonly TimeSpan MinRecordingDuration = TimeSpan.FromSeconds(0.3);

    public static readonly TimeSpan TranscriptionTimeout = TimeSpan.FromSeconds(120);
    public static readonly TimeSpan CleanupTimeout = TimeSpan.FromSeconds(60);

    /// <summary>Délai avant restauration du presse-papiers d'origine.</summary>
    public static readonly TimeSpan ClipboardRestoreDelay = TimeSpan.FromSeconds(1);

    /// <summary>Durée d'affichage d'une erreur dans la pastille.</summary>
    public static readonly TimeSpan ErrorDisplayDuration = TimeSpan.FromSeconds(4);
}
