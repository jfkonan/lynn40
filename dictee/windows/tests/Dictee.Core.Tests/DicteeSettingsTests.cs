using System.Text.Json;

namespace Dictee.Core.Tests;

public class DicteeSettingsTests
{
    [Fact]
    public void DefaultsMatchSpec()
    {
        var s = new DicteeSettings();
        Assert.Equal("gpt-4o-transcribe", s.Model);
        Assert.Equal("fr", s.Language);
        Assert.Equal("OHADA, AUSCGIE, AUDCG, AUPCAP, AUPSRVE, CCJA, SARL, SA, SAS, SNC, GIE, RCCM, assemblée générale, conseil d'administration, commissaire aux comptes, gérant, statuts, capital social", s.Vocabulary);
        Assert.False(s.CleanupEnabled);
        Assert.Equal("gpt-4o-mini", s.CleanupModel);
        Assert.Equal("rightCtrl", s.Hotkey);
        Assert.Equal("hold", s.HotkeyMode);
        Assert.True(s.SoundsEnabled);
        Assert.True(s.RestoreClipboard);
        Assert.False(s.LaunchAtLogin);
        Assert.Equal(["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"], DicteeSettings.ModelChoices);
    }

    [Fact]
    public void JsonUsesSpecCamelCaseKeys()
    {
        using var doc = JsonDocument.Parse(new DicteeSettings().ToJson());
        var keys = doc.RootElement.EnumerateObject().Select(p => p.Name).OrderBy(k => k, StringComparer.Ordinal).ToArray();
        Assert.Equal(new[] { "cleanupEnabled", "cleanupModel", "hotkey", "hotkeyMode", "language", "launchAtLogin",
            "model", "restoreClipboard", "soundsEnabled", "vocabulary" }, keys);
        Assert.Contains("assemblée générale", new DicteeSettings().ToJson());
    }

    [Fact]
    public void JsonRoundTrip()
    {
        var original = new DicteeSettings
        {
            Model = "whisper-1", Language = "", Vocabulary = "CCJA", CleanupEnabled = true, CleanupModel = "o4-mini",
            Hotkey = HotkeyIds.F8, HotkeyMode = HotkeyModes.Toggle, SoundsEnabled = false, RestoreClipboard = false, LaunchAtLogin = true,
        };
        var copy = DicteeSettings.FromJson(original.ToJson());

        Assert.Equal(original.ToJson(), copy.ToJson());
        Assert.Equal("", copy.Language);
        Assert.Equal(HotkeyModes.Toggle, copy.EffectiveHotkeyMode);
    }

    [Theory]
    [InlineData("{ pas du json")]
    [InlineData("[1,2,3]")]
    [InlineData("{\"cleanupEnabled\": \"peut-être\"}")]
    [InlineData("")]
    public void CorruptJsonGivesDefaults(string json)
    {
        Assert.Equal(new DicteeSettings().ToJson(), DicteeSettings.FromJson(json).ToJson());
    }

    [Fact]
    public void MissingKeysKeepDefaultsAndNullsAreReplaced()
    {
        var s = DicteeSettings.FromJson("{\"cleanupEnabled\": true, \"model\": null, \"vocabulary\": null}");
        Assert.True(s.CleanupEnabled);
        Assert.Equal(DicteeSettings.DefaultModel, s.Model);
        Assert.Equal(DicteeSettings.DefaultVocabulary, s.Vocabulary);
        Assert.Equal("fr", s.Language);
    }

    [Fact]
    public void BadlyTypedKeyDoesNotResetOthers()
    {
        var s = DicteeSettings.FromJson(
            "{\"soundsEnabled\": \"oui\", \"hotkey\": \"f8\", \"language\": 42, \"launchAtLogin\": true, \"model\": \"whisper-1\"}");
        Assert.True(s.SoundsEnabled);              // mal typé : défaut
        Assert.Equal("fr", s.Language);            // mal typé : défaut
        Assert.Equal(HotkeyIds.F8, s.Hotkey);      // les autres réglages sont conservés
        Assert.True(s.LaunchAtLogin);
        Assert.Equal("whisper-1", s.Model);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void BlankModelsFallBackToDefaults(string blank)
    {
        var s = DicteeSettings.FromJson($"{{\"model\": \"{blank}\", \"cleanupModel\": \"{blank}\"}}");
        Assert.Equal("gpt-4o-transcribe", s.EffectiveModel);
        Assert.Equal("gpt-4o-mini", s.EffectiveCleanupModel);
        Assert.Equal("whisper-1", new DicteeSettings { Model = " whisper-1 " }.EffectiveModel);
    }

    [Fact]
    public void UnknownHotkeyAndCombinationMode()
    {
        Assert.Equal(HotkeyIds.RightCtrl, new DicteeSettings { Hotkey = "inconnu" }.EffectiveHotkey);
        Assert.Equal(HotkeyModes.Hold, new DicteeSettings { HotkeyMode = "autre" }.EffectiveHotkeyMode);
        Assert.Equal(HotkeyModes.Toggle, new DicteeSettings { Hotkey = HotkeyIds.CtrlShiftSpace, HotkeyMode = "hold" }.EffectiveHotkeyMode);
    }

    [Fact]
    public void SaveAndLoadFile()
    {
        var dir = Path.Combine(Path.GetTempPath(), "dictee-tests-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(dir, "settings.json");
        try
        {
            Assert.Equal(new DicteeSettings().ToJson(), DicteeSettings.Load(path).ToJson()); // absent → défauts

            new DicteeSettings { Language = "en", SoundsEnabled = false }.Save(path);
            var loaded = DicteeSettings.Load(path);
            Assert.Equal("en", loaded.Language);
            Assert.False(loaded.SoundsEnabled);
            Assert.False(File.Exists(path + ".tmp"));

            File.WriteAllText(path, "\u0000\u0001 corrompu");
            Assert.Equal(new DicteeSettings().ToJson(), DicteeSettings.Load(path).ToJson());
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Theory]
    [InlineData("sk-proj-abcdefgh1234", "sk-…1234")]
    [InlineData("  sk-0123456789abcd  ", "sk-…abcd")]
    [InlineData("short", "••••")]
    [InlineData("", null)]
    [InlineData(null, null)]
    public void ApiKeyPreview(string? key, string? expected) => Assert.Equal(expected, ApiKeyHint.Preview(key));
}
