using System.Runtime.InteropServices;
using Dictee.Core;
using static Dictee.Windows.Native.NativeMethods;

namespace Dictee.Windows;

internal enum InsertOutcome
{
    /// <summary>Ctrl+V envoyé à l'application au premier plan.</summary>
    Pasted,
    /// <summary>Collage impossible : le texte reste dans le presse-papiers, l'utilisateur colle lui-même.</summary>
    LeftInClipboard,
}

/// <summary>
/// Insertion au curseur (SPEC.md §5) : sauvegarde du presse-papiers (tous formats), texte, Ctrl+V simulé,
/// puis restauration après ~1 s si le presse-papiers contient toujours notre texte.
/// Doit être appelé sur le fil d'interface (STA). Aucune attente bloquante : tout passe par Task.Delay.
/// </summary>
internal sealed class TextInjector
{
    private const int ClipboardAttempts = 10;
    private static readonly TimeSpan ClipboardRetryDelay = TimeSpan.FromMilliseconds(50);

    // Restauration différée de l'insertion précédente : hors du chemin critique, pour que la pastille disparaisse dès le collage.
    private Task _pendingRestore = Task.CompletedTask;

    public async Task<InsertOutcome> InsertAsync(string text, bool restoreClipboard)
    {
        // La sauvegarde suivante ne doit pas capturer le texte dicté précédent.
        await _pendingRestore;

        var backup = restoreClipboard ? await WithClipboardRetryAsync(SnapshotClipboard) : null;

        await WithClipboardRetryAsync(() =>
        {
            Clipboard.SetDataObject(BuildTextData(text, transient: restoreClipboard), copy: true, retryTimes: 1, retryDelay: 0);
            return true;
        });
        var ourSequence = GetClipboardSequenceNumber();

        // Une application lancée en administrateur ignore les saisies simulées d'une application normale (UIPI).
        if (ForegroundIsElevated()) return InsertOutcome.LeftInClipboard;

        // Ctrl+Maj+V ou Alt+V n'ont pas le même effet : on attend que l'utilisateur ait lâché ses touches.
        await WaitForModifiersReleasedAsync(TimeSpan.FromMilliseconds(600));
        await Task.Delay(20);

        var sent = SendKeys((VK_CONTROL, false), (VK_V, false), (VK_V, true), (VK_CONTROL, true));
        if (!sent) return InsertOutcome.LeftInClipboard;

        if (backup is not null) _pendingRestore = RestoreLaterAsync(backup, ourSequence);
        return InsertOutcome.Pasted;
    }

    /// <summary>Après ~1 s, remet le contenu d'origine, seulement si le presse-papiers contient toujours notre texte (SPEC §5).</summary>
    private static async Task RestoreLaterAsync(DataObject backup, uint ourSequence)
    {
        try
        {
            await Task.Delay(DicteeConstants.ClipboardRestoreDelay);
            var empty = backup.GetFormats(false).Length == 0;
            if (!empty)
            {
                // Le contenu d'origine est déjà dans l'historique Win+V (et le cloud) : pas de doublon à la restauration.
                var hadCloudFormat = backup.GetDataPresent("CanUploadToCloudClipboard", false);
                backup.SetData("CanIncludeInClipboardHistory", false, new MemoryStream(BitConverter.GetBytes(0)));
                if (!hadCloudFormat) backup.SetData("CanUploadToCloudClipboard", false, new MemoryStream(BitConverter.GetBytes(0)));
            }
            await WithClipboardRetryAsync(() =>
            {
                // Revérifié à chaque tentative : un échec signifie souvent qu'une autre application est en train d'écrire.
                if (GetClipboardSequenceNumber() != ourSequence) return false;
                if (empty) Clipboard.Clear();
                else Clipboard.SetDataObject(backup, copy: true, retryTimes: 1, retryDelay: 0);
                return true;
            });
        }
        catch (Exception)
        {
            // Presse-papiers verrouillé trop longtemps ou format non restaurable : on laisse le texte dicté, sans gravité.
        }
    }

    /// <summary>Copie simple (menu « Dernière transcription »).</summary>
    public static async Task CopyAsync(string text) =>
        await WithClipboardRetryAsync(() =>
        {
            Clipboard.SetDataObject(BuildTextData(text, transient: false), copy: true, retryTimes: 1, retryDelay: 0);
            return true;
        });

    private static DataObject BuildTextData(string text, bool transient)
    {
        var data = new DataObject();
        data.SetData(DataFormats.UnicodeText, false, text);
        // Confidentialité : jamais dans le presse-papiers cloud ; pas dans l'historique Win+V si on restaure juste après.
        data.SetData("CanUploadToCloudClipboard", false, new MemoryStream(BitConverter.GetBytes(0)));
        if (transient) data.SetData("CanIncludeInClipboardHistory", false, new MemoryStream(BitConverter.GetBytes(0)));
        return data;
    }

    /// <summary>Copie de tous les formats lisibles dans un nouveau DataObject (un format illisible est ignoré).</summary>
    private static DataObject SnapshotClipboard()
    {
        var copy = new DataObject();
        var current = Clipboard.GetDataObject();
        if (current is null) return copy;
        foreach (var format in current.GetFormats(false))
        {
            try
            {
                var value = current.GetData(format, false);
                if (value is not null) copy.SetData(format, false, value);
            }
            catch (Exception)
            {
                // Format à rendu différé ou non pris en charge par WinForms : tant pis pour celui-là.
            }
        }
        return copy;
    }

    /// <summary>Le presse-papiers peut être ouvert par une autre application (ExternalException) : on réessaie.</summary>
    private static async Task<T> WithClipboardRetryAsync<T>(Func<T> action)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return action();
            }
            catch (ExternalException) when (attempt < ClipboardAttempts)
            {
                await Task.Delay(ClipboardRetryDelay);
            }
        }
    }

    private static async Task WaitForModifiersReleasedAsync(TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline && AnyModifierDown())
            await Task.Delay(20);
    }

    private static bool AnyModifierDown()
    {
        foreach (var vk in new[] { VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN })
            if ((GetAsyncKeyState(vk) & 0x8000) != 0) return true;
        return false;
    }

    /// <summary>Vrai si la fenêtre au premier plan appartient à un processus élevé alors que Dictée ne l'est pas.</summary>
    private static bool ForegroundIsElevated()
    {
        if (IsElevated(Environment.ProcessId) == true) return false;
        var hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return false;
        GetWindowThreadProcessId(hwnd, out var pid);
        return pid != 0 && IsElevated((int)pid) == true;
    }

    /// <summary>true/false si connu ; null si le processus est inaccessible. Un jeton illisible (accès refusé) compte comme élevé.</summary>
    private static bool? IsElevated(int processId)
    {
        var process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, (uint)processId);
        if (process == IntPtr.Zero) return null;
        try
        {
            if (!OpenProcessToken(process, TOKEN_QUERY, out var token))
                return Marshal.GetLastWin32Error() == ERROR_ACCESS_DENIED ? true : null;
            try
            {
                return GetTokenInformation(token, TokenElevation, out var elevation, sizeof(int), out _) ? elevation != 0 : null;
            }
            finally
            {
                CloseHandle(token);
            }
        }
        finally
        {
            CloseHandle(process);
        }
    }
}
