namespace Dictee.Core.Tests;

public class HotkeyStateMachineTests
{
    private const int KeyC = 0x43;
    private const uint RealLeftCtrlScan = 0x1D;
    private const uint AltGrFakeLeftCtrlScan = 0x21D;

    private static HotkeyStateMachine Machine(string hotkey = HotkeyIds.RightCtrl, string mode = HotkeyModes.Hold)
    {
        var m = new HotkeyStateMachine();
        m.Configure(hotkey, mode);
        return m;
    }

    private static HotkeyDecision Down(HotkeyStateMachine m, int vk, uint scan = 0) => m.OnKey(vk, true, scan, injected: false);
    private static HotkeyDecision Up(HotkeyStateMachine m, int vk, uint scan = 0) => m.OnKey(vk, false, scan, injected: false);

    [Theory]
    [InlineData(HotkeyIds.RightCtrl, VirtualKeys.RightControl, false, false)]
    [InlineData(HotkeyIds.RightAlt, VirtualKeys.RightAlt, false, false)]
    [InlineData(HotkeyIds.F8, VirtualKeys.F8, true, false)]
    [InlineData(HotkeyIds.CtrlShiftSpace, 0, false, true)]
    [InlineData("inconnu", VirtualKeys.RightControl, false, false)]
    public void ConfigureMapsHotkey(string hotkey, int vk, bool swallow, bool toggle)
    {
        var m = Machine(hotkey);
        Assert.Equal(vk, m.HoldVk);
        Assert.Equal(swallow, m.SwallowHoldKey);
        Assert.Equal(toggle, m.IsToggleMode);
    }

    [Fact]
    public void HoldPressAndReleaseStartsThenEnds()
    {
        var m = Machine();
        Assert.Equal(new HotkeyDecision(HotkeyEvent.HoldStarted), Down(m, VirtualKeys.RightControl));
        Assert.Equal(new HotkeyDecision(HotkeyEvent.HoldEnded), Up(m, VirtualKeys.RightControl));
    }

    [Fact]
    public void AutoRepeatDoesNotRestart()
    {
        var m = Machine();
        Assert.Equal(HotkeyEvent.HoldStarted, Down(m, VirtualKeys.RightControl).Event);
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, VirtualKeys.RightControl));
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, VirtualKeys.RightControl));
        Assert.Equal(HotkeyEvent.HoldEnded, Up(m, VirtualKeys.RightControl).Event);
    }

    [Fact]
    public void RightCtrlPlusCNeverDictates()
    {
        var m = Machine();
        Down(m, VirtualKeys.RightControl);
        Assert.Equal(new HotkeyDecision(HotkeyEvent.HoldInterrupted), Down(m, KeyC));
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, KeyC)); // une seule annulation
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, KeyC));
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, VirtualKeys.RightControl)); // pas de HoldEnded
    }

    [Fact]
    public void NextPressAfterInterruptionStartsNormally()
    {
        var m = Machine();
        Down(m, VirtualKeys.RightControl);
        Down(m, KeyC);
        Up(m, VirtualKeys.RightControl);
        Assert.Equal(HotkeyEvent.HoldStarted, Down(m, VirtualKeys.RightControl).Event);
        Assert.Equal(HotkeyEvent.HoldEnded, Up(m, VirtualKeys.RightControl).Event);
    }

    [Fact]
    public void ClickDuringHoldInterruptsOnce()
    {
        var m = Machine();
        Down(m, VirtualKeys.RightControl);
        Assert.Equal(new HotkeyDecision(HotkeyEvent.HoldInterrupted), m.OnMouseButton(injected: false));
        Assert.Equal(HotkeyDecision.PassThrough, m.OnMouseButton(injected: false));
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, VirtualKeys.RightControl));
    }

    [Fact]
    public void ClickWithoutHoldOrInjectedIsIgnored()
    {
        var m = Machine();
        Assert.Equal(HotkeyDecision.PassThrough, m.OnMouseButton(injected: false));
        Down(m, VirtualKeys.RightControl);
        Assert.Equal(HotkeyDecision.PassThrough, m.OnMouseButton(injected: true));
        Assert.Equal(HotkeyEvent.HoldEnded, Up(m, VirtualKeys.RightControl).Event);
    }

    [Fact]
    public void KeysWithoutHoldAreIgnored()
    {
        var m = Machine();
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, KeyC));
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, KeyC));
        Assert.Equal(HotkeyEvent.HoldStarted, Down(m, VirtualKeys.RightControl).Event);
    }

    [Fact]
    public void InjectedKeysAreIgnored()
    {
        var m = Machine();
        Assert.Equal(HotkeyDecision.PassThrough, m.OnKey(VirtualKeys.RightControl, true, 0, injected: true));
        Down(m, VirtualKeys.RightControl);
        Assert.Equal(HotkeyDecision.PassThrough, m.OnKey(0x56, true, 0, injected: true)); // notre Ctrl+V simulé
        Assert.Equal(HotkeyEvent.HoldEnded, Up(m, VirtualKeys.RightControl).Event);
    }

    [Fact]
    public void ToggleModeFiresOnCleanRelease()
    {
        var m = Machine(mode: HotkeyModes.Toggle);
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, VirtualKeys.RightControl));
        Assert.Equal(new HotkeyDecision(HotkeyEvent.TogglePressed), Up(m, VirtualKeys.RightControl));
        Down(m, VirtualKeys.RightControl);
        Assert.Equal(HotkeyEvent.TogglePressed, Up(m, VirtualKeys.RightControl).Event);
    }

    [Fact]
    public void ToggleModeIgnoresShortcutWithoutInterrupting()
    {
        var m = Machine(mode: HotkeyModes.Toggle);
        Down(m, VirtualKeys.RightControl);
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, KeyC)); // pas de HoldInterrupted en mode basculer
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, VirtualKeys.RightControl));
        Down(m, VirtualKeys.RightControl);
        Assert.Equal(HotkeyDecision.PassThrough, m.OnMouseButton(injected: false));
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, VirtualKeys.RightControl));
    }

    [Fact]
    public void AltGrCompanionLeftCtrlIsNotAnotherKey()
    {
        var m = Machine(HotkeyIds.RightAlt);
        Assert.Equal(new HotkeyDecision(HotkeyEvent.HoldStarted, SendMaskKey: true), Down(m, VirtualKeys.RightAlt));
        // Windows répète le faux Ctrl gauche tant qu'AltGr est maintenue.
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, VirtualKeys.LeftControl, AltGrFakeLeftCtrlScan));
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, VirtualKeys.LeftControl, AltGrFakeLeftCtrlScan));
        Assert.Equal(HotkeyEvent.HoldEnded, Up(m, VirtualKeys.RightAlt).Event);
    }

    [Fact]
    public void RealLeftCtrlDuringAltGrInterrupts()
    {
        var m = Machine(HotkeyIds.RightAlt);
        Down(m, VirtualKeys.RightAlt);
        Assert.Equal(HotkeyEvent.HoldInterrupted, Down(m, VirtualKeys.LeftControl, RealLeftCtrlScan).Event);
    }

    [Fact]
    public void AltGrScanFlagOnlyExcusedForRightAltHotkey()
    {
        var m = Machine();
        Down(m, VirtualKeys.RightControl);
        Assert.Equal(HotkeyEvent.HoldInterrupted, Down(m, VirtualKeys.LeftControl, AltGrFakeLeftCtrlScan).Event);
    }

    [Fact]
    public void AltGrCharacterDuringHoldInterrupts()
    {
        var m = Machine(HotkeyIds.RightAlt);
        Down(m, VirtualKeys.RightAlt);
        Assert.Equal(HotkeyEvent.HoldInterrupted, Down(m, 0x30).Event); // AltGr+à = @
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, VirtualKeys.RightAlt));
    }

    [Fact]
    public void MaskKeyOnlyOnFirstRightAltPress()
    {
        var m = Machine(HotkeyIds.RightAlt);
        Assert.True(Down(m, VirtualKeys.RightAlt).SendMaskKey);
        Assert.False(Down(m, VirtualKeys.RightAlt).SendMaskKey); // répétition
        Assert.False(Machine().OnKey(VirtualKeys.RightControl, true, 0, false).SendMaskKey);
    }

    [Fact]
    public void F8IsSwallowedInBothDirectionsAndOnRepeat()
    {
        var m = Machine(HotkeyIds.F8);
        Assert.Equal(new HotkeyDecision(HotkeyEvent.HoldStarted, Swallow: true), Down(m, VirtualKeys.F8));
        Assert.Equal(new HotkeyDecision(Swallow: true), Down(m, VirtualKeys.F8));
        Assert.Equal(new HotkeyDecision(HotkeyEvent.HoldEnded, Swallow: true), Up(m, VirtualKeys.F8));
    }

    [Fact]
    public void RightCtrlIsNeverSwallowed()
    {
        var m = Machine();
        Assert.False(Down(m, VirtualKeys.RightControl).Swallow);
        Assert.False(Up(m, VirtualKeys.RightControl).Swallow);
    }

    [Fact]
    public void EscapePassesThroughWhenNotArmed()
    {
        var m = Machine();
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, VirtualKeys.Escape));
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, VirtualKeys.Escape));
    }

    [Fact]
    public void ArmedEscapeCancelsAndIsSwallowed()
    {
        var m = Machine(mode: HotkeyModes.Toggle);
        m.EscapeArmed = true;
        Assert.Equal(new HotkeyDecision(HotkeyEvent.EscapePressed, Swallow: true), Down(m, VirtualKeys.Escape));
        Assert.Equal(new HotkeyDecision(Swallow: true), Up(m, VirtualKeys.Escape));
    }

    [Fact]
    public void NoHoldEndedAfterEscapeDuringHold()
    {
        var m = Machine();
        Down(m, VirtualKeys.RightControl);
        m.EscapeArmed = true; // le contrôleur arme Échap au début de l'enregistrement
        Assert.Equal(new HotkeyDecision(HotkeyEvent.EscapePressed, Swallow: true), Down(m, VirtualKeys.Escape));
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, KeyC)); // déjà annulée : pas de HoldInterrupted en plus
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, VirtualKeys.RightControl));
    }

    [Fact]
    public void CombinationIgnoresKeyboardHookExceptEscape()
    {
        var m = Machine(HotkeyIds.CtrlShiftSpace, HotkeyModes.Hold);
        Assert.Equal(HotkeyDecision.PassThrough, Down(m, VirtualKeys.RightControl));
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, VirtualKeys.RightControl));
        m.EscapeArmed = true;
        Assert.Equal(HotkeyEvent.EscapePressed, Down(m, VirtualKeys.Escape).Event);
    }

    [Fact]
    public void ForgetHoldLetsNextPressRestart()
    {
        var m = Machine();
        Down(m, VirtualKeys.RightControl);
        m.ForgetHold(); // relâchement manqué (chien de garde)
        Assert.Equal(HotkeyEvent.HoldStarted, Down(m, VirtualKeys.RightControl).Event);
    }

    [Fact]
    public void ReconfigureResetsHoldState()
    {
        var m = Machine();
        Down(m, VirtualKeys.RightControl);
        m.Configure(HotkeyIds.F8, HotkeyModes.Hold);
        Assert.Equal(HotkeyDecision.PassThrough, Up(m, VirtualKeys.RightControl));
        Assert.Equal(HotkeyEvent.HoldStarted, Down(m, VirtualKeys.F8).Event);
    }
}
