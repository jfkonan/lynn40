using Dictee.Core;

namespace Dictee.Windows;

/// <summary>États de SPEC.md §7.</summary>
internal enum DictationState { Idle, Recording, Transcribing, Error }

/// <summary>
/// Machine à états de la dictée (SPEC.md §7) : idle → recording → transcribing → idle, ou error.
/// Tout s'exécute sur le fil d'interface ; les appels réseau sont asynchrones et ne le bloquent jamais.
/// </summary>
internal sealed class DictationController : IDisposable
{
    // Retour visuel et sonore légèrement différé : un Ctrl+C rapide annule avant que la pastille n'apparaisse.
    private static readonly TimeSpan FeedbackDelay = TimeSpan.FromMilliseconds(150);

    private readonly SettingsStore _settings;
    private readonly ApiKeyStore _keys;
    private readonly HotkeyManager _hotkeys;
    private readonly AudioRecorder _recorder;
    private readonly TextInjector _injector;
    private readonly OverlayForm _overlay;
    private readonly SoundEffects _sounds;
    private readonly HttpClient _http;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly System.Windows.Forms.Timer _feedbackTimer = new() { Interval = (int)FeedbackDelay.TotalMilliseconds };
    private readonly System.Windows.Forms.Timer _maxDurationTimer = new() { Interval = (int)DicteeConstants.MaxRecordingDuration.TotalMilliseconds };
    // Mode maintenir : si le crochet manque le relâchement (crochet retiré par Windows, fenêtre administrateur au premier plan),
    // on s'appuie sur l'état réel de la touche pour ne pas enregistrer jusqu'à 12 min.
    private readonly System.Windows.Forms.Timer _holdWatchdog = new() { Interval = 200 };
    private string? _audioPath; // WAV en cours de transcription, supprimé aussi si l'on quitte pendant l'envoi
    private bool _feedbackShown;
    private bool _stopping;

    public DictationController(SettingsStore settings, ApiKeyStore keys, HotkeyManager hotkeys, OverlayForm overlay)
    {
        _settings = settings;
        _keys = keys;
        _hotkeys = hotkeys;
        _overlay = overlay;
        _recorder = new AudioRecorder();
        _injector = new TextInjector();
        _sounds = new SoundEffects();
        _http = ApiHttp.CreateHttpClient();

        _feedbackTimer.Tick += (_, _) => ShowRecordingFeedback();
        _maxDurationTimer.Tick += (_, _) => _ = StopAndTranscribeAsync(); // 12 min : arrêt automatique puis transcription
        _holdWatchdog.Tick += (_, _) => OnHoldWatchdogTick();
        _recorder.Faulted += OnRecorderFaulted;

        _hotkeys.HoldStarted += StartRecording;
        _hotkeys.HoldEnded += () => _ = StopAndTranscribeAsync();
        _hotkeys.HoldInterrupted += () => _ = CancelRecordingAsync();
        _hotkeys.EscapePressed += () => _ = CancelRecordingAsync();
        _hotkeys.TogglePressed += Toggle;
    }

    public DictationState State { get; private set; } = DictationState.Idle;
    public string? LastTranscript { get; private set; }
    public string? LastError { get; private set; }

    public event Action? StateChanged;

    /// <summary>Applique le raccourci des réglages. Renvoie un message d'erreur éventuel.</summary>
    public string? ApplySettings()
    {
        var s = _settings.Current;
        return _hotkeys.Configure(s.EffectiveHotkey, s.EffectiveHotkeyMode);
    }

    private void Toggle()
    {
        switch (State)
        {
            case DictationState.Recording: _ = StopAndTranscribeAsync(); break;
            case DictationState.Transcribing: break; // une nouvelle dictée est ignorée pendant la transcription
            default: StartRecording(); break;
        }
    }

    private void StartRecording()
    {
        if (State is DictationState.Recording or DictationState.Transcribing || _stopping) return;

        try
        {
            _recorder.Start();
        }
        catch (DicteeException ex)
        {
            Fail(ex.Message);
            return;
        }

        _feedbackShown = false;
        _hotkeys.EscapeArmed = true;
        SetState(DictationState.Recording);
        _feedbackTimer.Start();
        _maxDurationTimer.Start();
        if (_settings.Current.EffectiveHotkeyMode == HotkeyModes.Hold) _holdWatchdog.Start();
    }

    private void OnHoldWatchdogTick()
    {
        if (State != DictationState.Recording || _hotkeys.IsHoldKeyPhysicallyDown) return;
        _hotkeys.ForgetHold();
        _ = StopAndTranscribeAsync(); // comme un relâchement normal
    }

    private void ShowRecordingFeedback()
    {
        _feedbackTimer.Stop();
        if (State != DictationState.Recording) return;
        _feedbackShown = true;
        if (_settings.Current.SoundsEnabled) _sounds.PlayStart();
        _overlay.ShowListening(() => _recorder.Level);
    }

    private async Task StopAndTranscribeAsync()
    {
        if (State != DictationState.Recording || _stopping) return;
        _stopping = true;
        RecordingResult recording;
        try
        {
            StopRecordingUi();
            recording = await _recorder.StopAsync();
        }
        catch (Exception ex)
        {
            Fail("Impossible d'arrêter l'enregistrement : " + ex.Message);
            return;
        }
        finally
        {
            _stopping = false;
        }

        try
        {
            // Trop court : abandon silencieux, sans appel réseau (SPEC §2.1).
            if (recording.Duration < DicteeConstants.MinRecordingDuration)
            {
                TranscriptionPipeline.TryDelete(recording.Path);
                _overlay.HideOverlay();
                SetState(DictationState.Idle);
                return;
            }

            if (_feedbackShown && _settings.Current.SoundsEnabled) _sounds.PlayStop();

            if (recording.BytesWritten == 0 || recording.AllSilent)
            {
                TranscriptionPipeline.TryDelete(recording.Path);
                Fail("Le micro n'a capté aucun son. Vérifiez qu'il est branché, non coupé, et autorisé dans " +
                     "Paramètres Windows > Confidentialité et sécurité > Microphone.");
                return;
            }

            // Clé du fournisseur choisi, vérifiée au moment de transcrire (comme sur macOS) :
            // un Ctrl+C sans clé enregistrée reste silencieux.
            var settings = _settings.Current.Clone();
            var provider = settings.EffectiveProvider;
            var apiKey = _keys.Load(provider);
            if (apiKey is null)
            {
                TranscriptionPipeline.TryDelete(recording.Path);
                Fail(DicteeMessages.MissingApiKey(provider));
                return;
            }

            SetState(DictationState.Transcribing);
            _overlay.ShowTranscribing();

            // Le nettoyage reste chez OpenAI ; sans clé OpenAI, il est sauté sans erreur (SPEC §2.3).
            var openAiKey = provider == TranscriptionProvider.OpenAI ? apiKey
                : settings.CleanupEnabled ? _keys.Load(TranscriptionProvider.OpenAI)
                : null;
            var cleaner = openAiKey is null ? null : new OpenAiClient(_http, openAiKey);
            var pipeline = new TranscriptionPipeline(TranscriptionClients.Create(provider, _http, apiKey), cleaner);
            _audioPath = recording.Path;
            var text = await pipeline.RunAsync(recording.Path, settings, _shutdown.Token);
            _audioPath = null;
            LastTranscript = text;

            var outcome = await _injector.InsertAsync(text, settings.RestoreClipboard);
            SetState(DictationState.Idle);
            if (outcome == InsertOutcome.Pasted) _overlay.HideOverlay();
            else _overlay.ShowMessage(DicteeMessages.TextCopied, isError: false);
        }
        catch (OperationCanceledException) when (_shutdown.IsCancellationRequested)
        {
            // Fermeture de l'application pendant la transcription.
        }
        catch (DicteeException ex)
        {
            Fail(ex.Message);
        }
        catch (System.Runtime.InteropServices.ExternalException)
        {
            Fail("Presse-papiers occupé par une autre application : le texte est disponible dans le menu « Dernière transcription ».");
        }
        catch (Exception ex)
        {
            Fail("Erreur inattendue : " + ex.Message);
        }
        finally
        {
            _audioPath = null; // le pipeline l'a supprimé dans son propre finally
            // Garde-fou : ne jamais rester bloqué en « transcription », sinon toutes les dictées suivantes seraient ignorées.
            if (State == DictationState.Transcribing && !_shutdown.IsCancellationRequested) SetState(DictationState.Idle);
        }
    }

    private async Task CancelRecordingAsync()
    {
        if (State != DictationState.Recording || _stopping) return;
        _stopping = true;
        try
        {
            StopRecordingUi();
            await _recorder.CancelAsync(); // supprime le fichier
        }
        catch (Exception)
        {
            // Annulation : rien à signaler à l'utilisateur.
        }
        finally
        {
            _stopping = false;
        }
        _overlay.HideOverlay();
        SetState(DictationState.Idle);
    }

    private void OnRecorderFaulted(Exception? error)
    {
        if (State != DictationState.Recording) return;
        StopRecordingUi();
        _ = _recorder.CancelAsync();
        Fail("Le micro s'est arrêté pendant l'enregistrement" + (error is null ? "." : " : " + error.Message));
    }

    private void StopRecordingUi()
    {
        _feedbackTimer.Stop();
        _maxDurationTimer.Stop();
        _holdWatchdog.Stop();
        _hotkeys.EscapeArmed = false;
    }

    private void Fail(string message)
    {
        LastError = message;
        SetState(DictationState.Error);
        _overlay.ShowMessage(message, isError: true);
    }

    private void SetState(DictationState state)
    {
        if (state != DictationState.Error) LastError = null;
        State = state;
        StateChanged?.Invoke();
    }

    public void Dispose()
    {
        _shutdown.Cancel();
        // La suppression du pipeline tourne sur le pool de fils et pourrait ne pas précéder la fin du processus.
        TranscriptionPipeline.TryDelete(_audioPath);
        _feedbackTimer.Dispose();
        _holdWatchdog.Dispose();
        _maxDurationTimer.Dispose();
        _recorder.Dispose(); // supprime un éventuel enregistrement en cours
        _sounds.Dispose();
        _http.Dispose();
        _shutdown.Dispose();
    }
}
