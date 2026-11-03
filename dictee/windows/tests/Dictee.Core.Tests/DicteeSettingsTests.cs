using System.Text.Json;

namespace Dictee.Core.Tests;

public class DicteeSettingsTests
{
    [Fact]
    public void DefaultsMatchSpec()
    {
        var s = new DicteeSettings();
        Assert.Equal("openai", s.Provider);
        Assert.Equal(TranscriptionProvider.OpenAI, s.EffectiveProvider);
        Assert.Equal("gpt-transcribe", s.Model);
        Assert.Equal("voxtral-small-transcribe-3", s.MistralModel);
        Assert.Equal("mai-transcribe-2", s.MicrosoftModel);
        Assert.Equal("eastus", s.AzureRegion);
        Assert.Equal("fr", s.Language);
        Assert.Equal("OHADA, AUSCGIE, AUDCG, AUPCAP, AUPSRVE, CCJA, SARL, SA, SAS, SNC, GIE, RCCM, assemblée générale, conseil d'administration, commissaire aux comptes, gérant, statuts, capital social", s.Vocabulary);
        Assert.False(s.CleanupEnabled);
        Assert.Equal("gpt-4o-mini", s.CleanupModel);
        Assert.Equal("rightCtrl", s.Hotkey);
        Assert.Equal("hold", s.HotkeyMode);
        Assert.True(s.SoundsEnabled);
        Assert.True(s.RestoreClipboard);
        Assert.False(s.LaunchAtLogin);
        Assert.Equal(["gpt-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"], DicteeSettings.ModelChoices);
        Assert.Equal(["voxtral-small-transcribe-3", "voxtral-mini-transcribe-3"], DicteeSettings.MistralModelChoices);
    }

    [Fact]
    public void JsonUsesSpecCamelCaseKeys()
    {
        using var doc = JsonDocument.Parse(new DicteeSettings().ToJson());
        var keys = doc.RootElement.EnumerateObject().Select(p => p.Name).OrderBy(k => k, StringComparer.Ordinal).ToArray();
        Assert.Equal(new[] { "azureRegion", "cleanupEnabled", "cleanupModel", "hotkey", "hotkeyMode", "language", "launchAtLogin",
            "microsoftModel", "mistralModel", "model", "provider", "restoreClipboard", "soundsEnabled", "vocabulary" }, keys);
        Assert.Contains("assemblée générale", new DicteeSettings().ToJson());
    }

    [Fact]
    public void JsonRoundTrip()
    {
        var original = new DicteeSettings
        {
            Provider = "mistral", Model = "whisper-1", MistralModel = "voxtral-mini-transcribe-3", MicrosoftModel = "mai-x",
            AzureRegion = "westeurope", Language = "", Vocabulary = "CCJA", CleanupEnabled = true, CleanupModel = "o4-mini",
            Hotkey = HotkeyIds.F8, HotkeyMode = HotkeyModes.Toggle, SoundsEnabled = false, RestoreClipboard = false, LaunchAtLogin = true,
        };
        var copy = DicteeSettings.FromJson(original.ToJson());

        Assert.Equal(original.ToJson(), copy.ToJson());
        Assert.Equal("", copy.Language);
        Assert.Equal(HotkeyModes.Toggle, copy.EffectiveHotkeyMode);
        Assert.Equal(TranscriptionProvider.Mistral, copy.EffectiveProvider);
        Assert.Equal("voxtral-mini-transcribe-3", copy.MistralModel);
        Assert.Equal("mai-x", copy.MicrosoftModel);
        Assert.Equal("westeurope", copy.AzureRegion);
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
        var s = DicteeSettings.FromJson($"{{\"model\": \"{blank}\", \"cleanupModel\": \"{blank}\", " +
            $"\"mistralModel\": \"{blank}\", \"microsoftModel\": \"{blank}\", \"azureRegion\": \"{blank}\"}}");
        Assert.Equal("gpt-transcribe", s.EffectiveModel);
        Assert.Equal("voxtral-small-transcribe-3", s.EffectiveMistralModel);
        Assert.Equal("mai-transcribe-2", s.EffectiveMicrosoftModel);
        Assert.Equal("eastus", s.EffectiveAzureRegion);
        Assert.Equal("gpt-4o-mini", s.EffectiveCleanupModel);
        Assert.Equal("whisper-1", new DicteeSettings { Model = " whisper-1 " }.EffectiveModel);
    }

    [Theory]
    [InlineData("openai", TranscriptionProvider.OpenAI)]
    [InlineData("mistral", TranscriptionProvider.Mistral)]
    [InlineData("microsoft", TranscriptionProvider.Microsoft)]
    [InlineData("google", TranscriptionProvider.OpenAI)]
    [InlineData("", TranscriptionProvider.OpenAI)]
    [InlineData("  ", TranscriptionProvider.OpenAI)]
    public void ProviderFallsBackToOpenAi(string value, TranscriptionProvider expected)
    {
        Assert.Equal(expected, new DicteeSettings { Provider = value }.EffectiveProvider);
        Assert.Equal(expected, DicteeSettings.FromJson($"{{\"provider\": \"{value}\"}}").EffectiveProvider);
    }

    [Fact]
    public void EffectiveTranscriptionModelFollowsProvider()
    {
        var s = new DicteeSettings { Model = "whisper-1", MistralModel = " voxtral-mini-transcribe-3 ", MicrosoftModel = "" };
        Assert.Equal("whisper-1", s.EffectiveTranscriptionModel);
        s.Provider = "mistral";
        Assert.Equal("voxtral-mini-transcribe-3", s.EffectiveTranscriptionModel);
        s.Provider = "microsoft";
        Assert.Equal("mai-transcribe-2", s.EffectiveTranscriptionModel);
        Assert.Equal("westeurope", new DicteeSettings { AzureRegion = " westeurope " }.EffectiveAzureRegion);
    }

    [Fact]
    public void OldFileWithoutProviderKeysGetsDefaults()
    {
        // Fichier écrit par la version précédente : aucune des nouvelles clés.
        var s = DicteeSettings.FromJson(
            "{\"model\": \"gpt-4o-transcribe\", \"language\": \"fr\", \"cleanupEnabled\": true, \"hotkey\": \"f8\"}");
        Assert.Equal("openai", s.Provider);
        Assert.Equal(TranscriptionProvider.OpenAI, s.EffectiveProvider);
        Assert.Equal("gpt-4o-transcribe", s.Model); // choix explicite conservé
        Assert.Equal("voxtral-small-transcribe-3", s.MistralModel);
        Assert.Equal("mai-transcribe-2", s.MicrosoftModel);
        Assert.Equal("eastus", s.AzureRegion);
        Assert.True(s.CleanupEnabled);
        Assert.Equal(HotkeyIds.F8, s.Hotkey);
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
