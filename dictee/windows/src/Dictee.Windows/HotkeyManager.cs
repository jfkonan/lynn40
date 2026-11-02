using System.ComponentModel;
using System.Runtime.InteropServices;
using Dictee.Core;
using static Dictee.Windows.Native.NativeMethods;

namespace Dictee.Windows;

/// <summary>
/// Raccourcis globaux.
/// - Touche seule (Ctrl droit, Alt droit, F8) : crochet clavier bas niveau WH_KEYBOARD_LL, installé sur un fil dédié
///   qui ne fait que pomper ses messages : un fil d'interface occupé (presse-papiers, DPAPI…) ne peut donc ni ralentir
///   le clavier ni faire dépasser LowLevelHooksTimeout, au-delà duquel Windows retire le crochet sans prévenir.
///   Les décisions (maintenir, basculer, annulation, Échap) sont prises par <see cref="HotkeyStateMachine"/>, testée dans Dictee.Core.
/// - Combinaison Ctrl+Maj+Espace : RegisterHotKey, toujours en mode « basculer ».
/// Les rappels restent très courts : ils consultent la machine à états et postent l'action sur le fil d'interface.
/// </summary>
internal sealed class HotkeyManager : IDisposable
{
    private const int ToggleHotkeyId = 0xD1C7;

    // Références conservées : sans elles, le ramasse-miettes libérerait les délégués et Windows appellerait une adresse morte.
    private readonly LowLevelKeyboardProc _hookProc;
    private readonly LowLevelKeyboardProc _mouseProc; // même signature que le rappel clavier
    private readonly SynchronizationContext _ui;
    private readonly HotkeyWindow _window;
    private Thread? _hookThread;
    private uint _hookThreadId;
    private IntPtr _hook;
    private IntPtr _mouseHook;
    private readonly HotkeyStateMachine _state = new();

    public HotkeyManager()
    {
        _ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        _hookProc = HookCallback;
        _mouseProc = MouseCallback;
        _window = new HotkeyWindow(() => Post(TogglePressed));
    }

    public event Action? HoldStarted;
    public event Action? HoldEnded;
    /// <summary>Une autre touche (ou un clic) a été pressée pendant le maintien : annuler sans bruit.</summary>
    public event Action? HoldInterrupted;
    public event Action? TogglePressed;
    public event Action? EscapePressed;

    /// <summary>Vrai pendant l'enregistrement : Échap n'est capturée qu'à ce moment-là.</summary>
    public bool EscapeArmed
    {
        get => _state.EscapeArmed;
        set => _state.EscapeArmed = value;
    }

    /// <summary>
    /// Vrai si la touche maintenue est encore enfoncée (chien de garde du mode « maintenir »).
    /// Renvoie vrai quand on ne peut pas le savoir : combinaison, ou F8 avalée par le crochet (son état asynchrone n'est pas mis à jour).
    /// </summary>
    public bool IsHoldKeyPhysicallyDown
    {
        get
        {
            var vk = _state.HoldVk;
            return vk == 0 || _state.SwallowHoldKey || (GetAsyncKeyState(vk) & 0x8000) != 0;
        }
    }

    /// <summary>Relâchement manqué par le crochet : le prochain appui doit redémarrer normalement.</summary>
    public void ForgetHold() => _state.ForgetHold();

    /// <summary>Installe les crochets sur leur fil dédié. Lève Win32Exception si le crochet clavier est refusé.</summary>
    public void Install()
    {
        if (_hookThread is not null) return;
        using var ready = new ManualResetEventSlim();
        var error = 0;
        var thread = new Thread(() =>
        {
            PeekMessage(out _, IntPtr.Zero, WM_USER, WM_USER, PM_NOREMOVE); // crée la file de messages du fil
            _hookThreadId = GetCurrentThreadId();
            var module = GetModuleHandle(null);
            _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _hookProc, module, 0);
            if (_hook == IntPtr.Zero) error = Marshal.GetLastWin32Error();
            else _mouseHook = SetWindowsHookEx(WH_MOUSE_LL, _mouseProc, module, 0); // facultatif : sans lui, Ctrl+clic n'annule pas
            ready.Set();
            if (_hook == IntPtr.Zero) return;

            // Les rappels bas niveau sont appelés pendant GetMessage ; WM_QUIT (Dispose) termine la boucle.
            while (GetMessage(out _, IntPtr.Zero, 0, 0) > 0) { }

            if (_mouseHook != IntPtr.Zero) UnhookWindowsHookEx(_mouseHook);
            UnhookWindowsHookEx(_hook);
            _mouseHook = IntPtr.Zero;
            _hook = IntPtr.Zero;
        }) { IsBackground = true, Name = "Dictee.KeyboardHook" };
        thread.Start();
        ready.Wait();
        if (_hook == IntPtr.Zero) throw new Win32Exception(error);
        _hookThread = thread;
    }

    /// <summary>Applique le raccourci et le mode. Renvoie un message d'erreur à afficher, ou null.</summary>
    public string? Configure(string hotkey, string mode)
    {
        _window.Unregister(ToggleHotkeyId);
        _state.Configure(hotkey, mode);
        if (!HotkeyIds.IsCombination(hotkey)) return null;
        return _window.Register(ToggleHotkeyId, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, VK_SPACE)
            ? null
            : "Le raccourci Ctrl+Maj+Espace est déjà utilisé par une autre application. Choisissez-en un autre dans les réglages.";
    }

    /// <summary>Libellé lisible du raccourci courant, pour l'interface.</summary>
    public static string Describe(string hotkey, string mode) => hotkey switch
    {
        HotkeyIds.CtrlShiftSpace => "Ctrl+Maj+Espace (appuyer pour démarrer, puis pour arrêter)",
        _ => (mode == HotkeyModes.Toggle ? "Appuyer sur " : "Maintenir ") + KeyName(hotkey),
    };

    public static string KeyName(string hotkey) => hotkey switch
    {
        HotkeyIds.RightAlt => "Alt droit",
        HotkeyIds.F8 => "F8",
        HotkeyIds.CtrlShiftSpace => "Ctrl+Maj+Espace",
        _ => "Ctrl droit",
    };

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0) return CallNextHookEx(_hook, nCode, wParam, lParam);

        var data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
        var down = (int)wParam is WM_KEYDOWN or WM_SYSKEYDOWN; // sinon WM_KEYUP / WM_SYSKEYUP
        var decision = _state.OnKey((int)data.vkCode, down, data.scanCode, (data.flags & LLKHF_INJECTED) != 0);
        return Apply(decision) ? 1 : CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private IntPtr MouseCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        // Ctrl droit + clic (ou molette) : raccourci de l'utilisateur, pas une dictée.
        if (nCode >= 0 &&
            (int)wParam is WM_LBUTTONDOWN or WM_RBUTTONDOWN or WM_MBUTTONDOWN or WM_XBUTTONDOWN or WM_MOUSEWHEEL or WM_MOUSEHWHEEL)
        {
            var injected = ((uint)Marshal.ReadInt32(lParam, MSLLHOOKSTRUCT_FLAGS_OFFSET) & LLMHF_INJECTED) != 0;
            Apply(_state.OnMouseButton(injected));
        }
        return CallNextHookEx(_mouseHook, nCode, wParam, lParam);
    }

    /// <summary>Poste l'événement décidé sur le fil d'interface ; renvoie vrai si la touche doit être avalée.</summary>
    private bool Apply(HotkeyDecision decision)
    {
        if (decision.SendMaskKey) _ui.Post(_ => SendMaskKey(), null);
        Post(decision.Event switch
        {
            HotkeyEvent.HoldStarted => HoldStarted,
            HotkeyEvent.HoldEnded => HoldEnded,
            HotkeyEvent.HoldInterrupted => HoldInterrupted,
            HotkeyEvent.TogglePressed => TogglePressed,
            HotkeyEvent.EscapePressed => EscapePressed,
            _ => null,
        });
        return decision.Swallow;
    }

    /// <summary>
    /// Alt pressé puis relâché seul active la barre de menus de l'application au premier plan, ce qui gênerait le collage.
    /// Une touche neutre simulée pendant le maintien l'en empêche (technique dite de la « touche masque »).
    /// </summary>
    private static void SendMaskKey() => SendKeys((VK_MASK, false), (VK_MASK, true));

    private void Post(Action? handler)
    {
        if (handler is not null) _ui.Post(_ => handler(), null);
    }

    public void Dispose()
    {
        if (_hookThread is not null)
        {
            // Le fil retire lui-même ses crochets en sortant de sa boucle.
            PostThreadMessage(_hookThreadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
            _hookThread.Join(TimeSpan.FromSeconds(1));
            _hookThread = null;
        }
        _window.Unregister(ToggleHotkeyId);
        _window.DestroyHandle();
    }

    /// <summary>Fenêtre « message seulement » qui reçoit WM_HOTKEY.</summary>
    private sealed class HotkeyWindow : NativeWindow
    {
        private static readonly IntPtr HWND_MESSAGE = new(-3);
        private readonly Action _onHotkey;
        private readonly HashSet<int> _registered = [];

        public HotkeyWindow(Action onHotkey)
        {
            _onHotkey = onHotkey;
            CreateHandle(new CreateParams { Caption = "Dictee.Hotkeys", Parent = HWND_MESSAGE });
        }

        public bool Register(int id, uint modifiers, int vk)
        {
            if (!RegisterHotKey(Handle, id, modifiers, (uint)vk)) return false;
            _registered.Add(id);
            return true;
        }

        public void Unregister(int id)
        {
            if (_registered.Remove(id) && Handle != IntPtr.Zero) UnregisterHotKey(Handle, id);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY && _registered.Contains((int)m.WParam)) _onHotkey();
            base.WndProc(ref m);
        }
    }
}
