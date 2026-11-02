namespace Dictee.Core;

/// <summary>Codes de touches virtuelles Windows (VK_*) dont la machine à états a besoin.</summary>
public static class VirtualKeys
{
    public const int Escape = 0x1B;
    public const int F8 = 0x77;
    public const int LeftControl = 0xA2;
    public const int RightControl = 0xA3;
    public const int RightAlt = 0xA5; // VK_RMENU
}

/// <summary>Ce que le crochet doit signaler au contrôleur de dictée.</summary>
public enum HotkeyEvent
{
    None,
    HoldStarted,
    HoldEnded,
    /// <summary>Une autre touche (ou un clic) pendant le maintien : raccourci de l'utilisateur, annuler sans bruit.</summary>
    HoldInterrupted,
    TogglePressed,
    EscapePressed,
}

/// <summary>Décision prise pour un événement clavier ou souris.</summary>
/// <param name="Event">Événement à poster sur le fil d'interface.</param>
/// <param name="Swallow">Vrai : l'événement ne doit pas être transmis aux autres applications.</param>
/// <param name="SendMaskKey">Vrai : simuler la « touche masque » pour qu'Alt seul n'active pas la barre de menus.</param>
public readonly record struct HotkeyDecision(HotkeyEvent Event = HotkeyEvent.None, bool Swallow = false, bool SendMaskKey = false)
{
    public static readonly HotkeyDecision PassThrough = new();
}

/// <summary>
/// Logique des raccourcis à touche seule, sans Win32 (testable sous Linux). Le crochet clavier lui passe chaque
/// événement et applique la décision renvoyée.
/// - Mode « maintenir » : démarre à l'appui, s'arrête au relâchement ; toute autre touche ou tout clic pendant le maintien
///   signifie un raccourci (Ctrl droit+C, Ctrl+clic…) : on annule, et le relâchement ne déclenche plus rien.
/// - Mode « basculer » : un appui-relâché « propre » (sans autre touche) démarre ou arrête.
/// - Échap, quand elle est armée (pendant l'enregistrement), annule et est avalée dans les deux sens.
/// Écrite par le fil du crochet, lue ou réinitialisée par le fil d'interface : champs volatiles.
/// </summary>
public sealed class HotkeyStateMachine
{
    /// <summary>Le faux Ctrl gauche qu'envoie AltGr a un code de balayage 0x21D : ce bit le distingue d'un vrai Ctrl (0x1D).</summary>
    public const uint AltGrCompanionScanFlag = 0x200;

    private volatile int _holdVk;          // 0 si le raccourci est une combinaison (gérée par RegisterHotKey)
    private volatile bool _toggleMode;
    private volatile bool _swallowHoldKey; // F8 : avalée pour que l'application au premier plan ne la reçoive pas
    private volatile bool _holdKeyDown;
    private volatile bool _otherKeyDuringHold;
    private volatile bool _escapeArmed;

    /// <summary>Touche maintenue (VK), ou 0 pour une combinaison.</summary>
    public int HoldVk => _holdVk;

    /// <summary>Vrai si la touche maintenue est avalée (son état asynchrone n'est alors pas mis à jour par Windows).</summary>
    public bool SwallowHoldKey => _swallowHoldKey;

    public bool IsToggleMode => _toggleMode;

    /// <summary>Vrai pendant l'enregistrement : Échap n'est capturée qu'à ce moment-là.</summary>
    public bool EscapeArmed
    {
        get => _escapeArmed;
        set => _escapeArmed = value;
    }

    /// <summary>Applique le raccourci et le mode ; une combinaison force le mode « basculer ».</summary>
    public void Configure(string hotkey, string mode)
    {
        _holdKeyDown = false;
        _otherKeyDuringHold = false;
        _toggleMode = mode == HotkeyModes.Toggle || HotkeyIds.IsCombination(hotkey);
        _swallowHoldKey = hotkey == HotkeyIds.F8;
        _holdVk = hotkey switch
        {
            HotkeyIds.CtrlShiftSpace => 0,
            HotkeyIds.RightAlt => VirtualKeys.RightAlt,
            HotkeyIds.F8 => VirtualKeys.F8,
            _ => VirtualKeys.RightControl,
        };
    }

    /// <summary>Relâchement manqué par le crochet : le prochain appui doit redémarrer normalement.</summary>
    public void ForgetHold() => _holdKeyDown = false;

    /// <summary>Événement clavier bas niveau.</summary>
    /// <param name="injected">Saisie simulée (nos propres Ctrl+V et touche masque, ou un autre logiciel) : ignorée.</param>
    public HotkeyDecision OnKey(int vk, bool down, uint scanCode, bool injected)
    {
        if (injected) return HotkeyDecision.PassThrough;

        if (vk == VirtualKeys.Escape && _escapeArmed)
        {
            if (!down) return new HotkeyDecision(Swallow: true);
            if (_holdKeyDown) _otherKeyDuringHold = true; // pas de HoldEnded au relâchement : l'annulation suffit
            // Avalée, comme sur macOS : sinon Ctrl droit + Échap ouvre le menu Démarrer.
            return new HotkeyDecision(HotkeyEvent.EscapePressed, Swallow: true);
        }

        var holdVk = _holdVk;
        if (holdVk == 0) return HotkeyDecision.PassThrough;

        if (vk == holdVk)
        {
            var evt = HotkeyEvent.None;
            var mask = false;
            if (down && !_holdKeyDown) // la répétition automatique renvoie des « down » : on ne garde que le premier
            {
                _holdKeyDown = true;
                _otherKeyDuringHold = false;
                mask = vk == VirtualKeys.RightAlt;
                if (!_toggleMode) evt = HotkeyEvent.HoldStarted;
            }
            else if (!down && _holdKeyDown)
            {
                _holdKeyDown = false;
                if (!_otherKeyDuringHold) evt = _toggleMode ? HotkeyEvent.TogglePressed : HotkeyEvent.HoldEnded;
            }
            return new HotkeyDecision(evt, _swallowHoldKey, mask);
        }

        if (down && !IsAltGrCompanion(holdVk, vk, scanCode)) return Interrupt();
        return HotkeyDecision.PassThrough;
    }

    /// <summary>Clic ou molette (jamais avalé).</summary>
    public HotkeyDecision OnMouseButton(bool injected) => injected ? HotkeyDecision.PassThrough : Interrupt();

    /// <summary>Première autre touche ou premier clic pendant le maintien : la dictée est annulée (mode maintenir).</summary>
    private HotkeyDecision Interrupt()
    {
        if (!_holdKeyDown || _otherKeyDuringHold) return HotkeyDecision.PassThrough;
        _otherKeyDuringHold = true;
        return _toggleMode ? HotkeyDecision.PassThrough : new HotkeyDecision(HotkeyEvent.HoldInterrupted);
    }

    /// <summary>AltGr (Alt droit sur AZERTY) envoie aussi un faux Ctrl gauche, répété tant qu'on maintient : ce n'est pas « une autre touche ».</summary>
    private static bool IsAltGrCompanion(int holdVk, int vk, uint scanCode) =>
        holdVk == VirtualKeys.RightAlt && vk == VirtualKeys.LeftControl && (scanCode & AltGrCompanionScanFlag) != 0;
}
