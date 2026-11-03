# -*- coding: utf-8 -*-
"""Tests du banc d'essai (bibliothèque standard, aucun appel réseau).

Depuis la racine du dépôt :
    python3 -I -m unittest discover -s dictee/bench -v
"""

import json
import os
import struct
import sys
import tempfile
import unittest
from email.parser import BytesParser
from email.policy import default as email_default_policy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bench  # noqa: E402

AUDIO = b"RIFF\x00\x00\x00\x00WAVEfake"


def parse_multipart(body, content_type):
    """Relit un corps multipart avec le module email : liste de (nom, nom de fichier, type, contenu)."""
    message = BytesParser(policy=email_default_policy).parsebytes(
        b"Content-Type: " + content_type.encode("ascii") + b"\r\n\r\n" + body
    )
    parts = []
    for part in message.iter_parts():
        parts.append((
            part.get_param("name", header="content-disposition"),
            part.get_filename(),
            part.get_content_type(),
            part.get_payload(decode=True),
        ))
    return parts


class NormalisationTests(unittest.TestCase):
    def test_minuscules_et_ponctuation(self):
        self.assertEqual(bench.normalize_text("Bonjour, Maître ! Ça va ?"), "bonjour maître ça va")

    def test_apostrophes_unifiees(self):
        self.assertEqual(bench.normalize_text("L\u2019assemblée"), bench.normalize_text("l'assemblée"))
        self.assertEqual(bench.normalize_text("aujourd\u2019hui"), "aujourd'hui")

    def test_tirets_unifies(self):
        self.assertEqual(bench.normalize_text("c\u2019est\u2011à\u2011dire"), "c' est-à-dire")
        self.assertEqual(bench.normalize_text("Article 5 \u2013 alinéa 2"), "article 5 alinéa 2")

    def test_elisions(self):
        self.assertEqual(bench.normalize_text("L'assemblée générale de l'OHADA"), "l' assemblée générale de l' ohada")
        self.assertEqual(bench.normalize_text("l' assemblée"), "l' assemblée")
        self.assertEqual(bench.normalize_text("Lorsqu'il statue, qu'il"), "lorsqu' il statue qu' il")
        self.assertEqual(bench.normalize_text("aujourd'hui"), "aujourd'hui")
        self.assertEqual(bench.normalize_text("'Bonjour' -"), "bonjour")
        # Une élision mal transcrite ne coûte qu'une erreur, pas le mot entier.
        self.assertAlmostEqual(bench.wer("l'assemblée", "la assemblée"), 0.5)

    def test_guillemets_et_espaces(self):
        self.assertEqual(bench.normalize_text("  «\u00a0statuts\u00a0»\n\tsociaux.  "), "statuts sociaux")

    def test_accents_conserves(self):
        self.assertNotEqual(bench.normalize_text("gérant"), bench.normalize_text("gerant"))

    def test_forme_unicode_decomposee(self):
        self.assertEqual(bench.normalize_text("ge\u0301rant"), "gérant")


class WerTests(unittest.TestCase):
    def test_identique(self):
        self.assertEqual(bench.wer("Le gérant est révoqué.", "le gérant est révoqué"), 0.0)

    def test_une_substitution(self):
        self.assertAlmostEqual(bench.wer("le chat dort", "le chien dort"), 1 / 3)

    def test_suppression_et_insertion(self):
        self.assertAlmostEqual(bench.wer("a b c d", "a c d"), 0.25)
        self.assertAlmostEqual(bench.wer("a b c d", "a b x c d"), 0.25)

    def test_cas_connu(self):
        # Exemple classique : 2 substitutions + 1 suppression sur 6 mots de référence.
        ref = "the cat sat on the mat"
        hyp = "the cat sit on mat now"
        errors, total = bench.word_errors(ref, hyp)
        self.assertEqual(total, 6)
        self.assertEqual(errors, 3)  # sat→sit, the supprimé, now inséré
        self.assertAlmostEqual(bench.wer(ref, hyp), 0.5)

    def test_kitten_sitting(self):
        # Distance de Levenshtein connue (kitten → sitting = 3), appliquée ici aux « mots » lettres.
        errors = sum(1 for op, _, _ in bench.align_words(list("kitten"), list("sitting")) if op != "=")
        self.assertEqual(errors, 3)

    def test_hypothese_vide(self):
        self.assertEqual(bench.wer("un deux trois", ""), 1.0)

    def test_reference_vide(self):
        self.assertEqual(bench.wer("", ""), 0.0)
        self.assertEqual(bench.wer("", "bruit"), 1.0)

    def test_peut_depasser_un(self):
        self.assertGreater(bench.wer("oui", "oui oui oui oui"), 1.0)

    def test_alignement_et_diff(self):
        ops = bench.align_words(["a", "b", "c"], ["a", "x", "c", "d"])
        self.assertEqual([op for op, _, _ in ops], ["=", "S", "=", "I"])
        self.assertEqual(bench.diff_markdown("a b c", "a x c d"), "a ~~b~~ **x** c **d**")


class VocabularyTests(unittest.TestCase):
    def test_separateurs(self):
        self.assertEqual(bench.vocabulary_terms("OHADA, AUSCGIE;CCJA\nSARL\r\nSA"),
                         ["OHADA", "AUSCGIE", "CCJA", "SARL", "SA"])

    def test_espaces_et_vides(self):
        self.assertEqual(bench.vocabulary_terms("  OHADA ,, ; \n  capital social  ,"),
                         ["OHADA", "capital social"])
        self.assertEqual(bench.vocabulary_terms(""), [])
        self.assertEqual(bench.vocabulary_terms("  ,;\n "), [])

    def test_doublons(self):
        self.assertEqual(bench.vocabulary_terms("SA, SAS, SA, OHADA, SAS"), ["SA", "SAS", "OHADA"])

    def test_limite_100(self):
        terms = bench.vocabulary_terms(",".join("terme{0}".format(i) for i in range(150)))
        self.assertEqual(len(terms), 100)
        self.assertEqual(terms[0], "terme0")
        self.assertEqual(terms[-1], "terme99")

    def test_limite_apres_doublons(self):
        raw = ",".join(["X"] * 50 + ["t{0}".format(i) for i in range(120)])
        terms = bench.vocabulary_terms(raw)
        self.assertEqual(len(terms), 100)
        self.assertEqual(terms[:2], ["X", "t0"])

    def test_vocabulaire_par_defaut(self):
        terms = bench.vocabulary_terms(bench.DEFAULT_VOCABULARY)
        self.assertEqual(len(terms), 18)
        self.assertIn("conseil d'administration", terms)


class AzureLocaleTests(unittest.TestCase):
    def test_table(self):
        attendu = {"fr": "fr-FR", "en": "en-US", "es": "es-ES", "de": "de-DE", "it": "it-IT",
                   "pt": "pt-BR", "nl": "nl-NL", "ar": "ar-SA"}
        for lang, locale in attendu.items():
            self.assertEqual(bench.azure_locale(lang), locale)

    def test_valeur_avec_tiret(self):
        self.assertEqual(bench.azure_locale("fr-CA"), "fr-CA")
        self.assertEqual(bench.azure_locale("en-GB"), "en-GB")

    def test_autre_code(self):
        self.assertEqual(bench.azure_locale("sv"), "sv-SV")
        self.assertEqual(bench.azure_locale("pl"), "pl-PL")

    def test_vide(self):
        self.assertIsNone(bench.azure_locale(""))
        self.assertIsNone(bench.azure_locale("   "))

    def test_mistral_language(self):
        self.assertEqual(bench.mistral_language("fr-FR"), "fr")
        self.assertEqual(bench.mistral_language("fr"), "fr")
        self.assertIsNone(bench.mistral_language(""))


class OpenAIRequestTests(unittest.TestCase):
    def test_champs(self):
        req = bench.build_openai_request(AUDIO, ".wav", "sk-secret", "gpt-transcribe", "fr", "OHADA, SA, SA")
        self.assertEqual(req.url, "https://api.openai.com/v1/audio/transcriptions")
        self.assertEqual(req.headers, {"Authorization": "Bearer sk-secret"})
        names = [n for n, _ in req.fields]
        self.assertEqual(names, ["model", "response_format", "language", "prompt", "file"])
        self.assertEqual(req.field_values("prompt"), ["OHADA, SA, SA"])  # vocabulaire brut
        self.assertEqual(req.field_values("response_format"), ["json"])
        self.assertEqual(req.field_values("file")[0].content_type, "audio/wav")

    def test_omissions(self):
        req = bench.build_openai_request(AUDIO, ".wav", "k", "whisper-1", "", "  ")
        self.assertEqual([n for n, _ in req.fields], ["model", "response_format", "file"])


class MistralMultipartTests(unittest.TestCase):
    def setUp(self):
        self.req = bench.build_mistral_request(AUDIO, ".wav", "ms-secret", "voxtral-small-transcribe-3",
                                               "fr-FR", "OHADA; AUSCGIE\ncapital social, OHADA")

    def test_url_et_entete(self):
        self.assertEqual(self.req.url, "https://api.mistral.ai/v1/audio/transcriptions")
        self.assertEqual(self.req.headers, {"Authorization": "Bearer ms-secret"})

    def test_context_bias_repete_sans_prompt(self):
        body, content_type = bench.encode_multipart(self.req.fields)
        parts = parse_multipart(body, content_type)
        names = [p[0] for p in parts]
        self.assertEqual(names, ["model", "language", "context_bias", "context_bias", "context_bias", "file"])
        self.assertNotIn("prompt", names)
        self.assertNotIn("response_format", names)
        values = [p[3].decode("utf-8") for p in parts if p[0] == "context_bias"]
        self.assertEqual(values, ["OHADA", "AUSCGIE", "capital social"])
        self.assertEqual(parts[1][3], b"fr")  # fr-FR → fr
        self.assertEqual(parts[-1][1], "audio.wav")
        self.assertEqual(parts[-1][2], "audio/wav")
        self.assertEqual(parts[-1][3], AUDIO)

    def test_sans_vocabulaire_ni_langue(self):
        req = bench.build_mistral_request(AUDIO, ".m4a", "k", "voxtral-mini-transcribe-3", "", "")
        self.assertEqual([n for n, _ in req.fields], ["model", "file"])
        self.assertEqual(req.field_values("file")[0].content_type, "audio/mp4")
        self.assertEqual(req.field_values("file")[0].filename, "audio.m4a")


class AzureMultipartTests(unittest.TestCase):
    def test_definition_json(self):
        req = bench.build_microsoft_request(AUDIO, ".wav", "az-secret", "mai-transcribe-2", "fr",
                                            "OHADA, AUSCGIE, OHADA", "westeurope")
        self.assertEqual(
            req.url,
            "https://westeurope.api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe"
            "?api-version=2025-10-15")
        self.assertEqual(req.headers, {"Ocp-Apim-Subscription-Key": "az-secret"})
        body, content_type = bench.encode_multipart(req.fields)
        parts = parse_multipart(body, content_type)
        self.assertEqual([p[0] for p in parts], ["audio", "definition"])
        audio = parts[0]
        self.assertEqual((audio[1], audio[2], audio[3]), ("audio.wav", "audio/wav", AUDIO))
        definition = parts[1]
        self.assertEqual(definition[2], "application/json")
        self.assertEqual(json.loads(definition[3].decode("utf-8")), {
            "locales": ["fr-FR"],
            "enhancedMode": {"enabled": True, "model": "mai-transcribe-2"},
            "phraseList": {"phrases": ["OHADA", "AUSCGIE"]},
        })

    def test_omissions_et_region_par_defaut(self):
        req = bench.build_microsoft_request(AUDIO, ".wav", "k", "mai-transcribe-2", "", "", "  ")
        self.assertTrue(req.url.startswith("https://eastus.api.cognitive.microsoft.com/"))
        definition = json.loads(req.field_values("definition")[0].data.decode("utf-8"))
        self.assertEqual(definition, {"enhancedMode": {"enabled": True, "model": "mai-transcribe-2"}})

    def test_utf8(self):
        definition = bench.azure_definition("mai-transcribe-2", "fr", "assemblée générale")
        self.assertEqual(definition["phraseList"]["phrases"], ["assemblée générale"])


class ParserTests(unittest.TestCase):
    def test_openai_et_mistral(self):
        self.assertEqual(bench.parse_openai_response(b'{"text": " Bonjour. "}'), "Bonjour.")
        self.assertEqual(bench.parse_mistral_response('{"text":"Énoncé","model":"x"}'.encode("utf-8")), "Énoncé")
        with self.assertRaises(bench.TranscriptionError):
            bench.parse_openai_response(b"<html>oops</html>")

    def test_azure_combined_phrases(self):
        body = json.dumps({
            "durationMilliseconds": 4200,
            "combinedPhrases": [{"text": "Le gérant de la SARL."}],
            "phrases": [{"text": "Le gérant"}, {"text": "de la SARL."}],
        }).encode("utf-8")
        self.assertEqual(bench.parse_microsoft_response(body), "Le gérant de la SARL.")
        self.assertAlmostEqual(bench.reported_duration_seconds("microsoft", body), 4.2)

    def test_azure_repli_sur_phrases(self):
        body = json.dumps({"phrases": [{"text": "Le gérant"}, {"text": ""}, {"text": "de la SARL."}]}).encode()
        self.assertEqual(bench.parse_microsoft_response(body), "Le gérant de la SARL.")
        body = json.dumps({"combinedPhrases": [], "phrases": [{"text": "OHADA"}]}).encode()
        self.assertEqual(bench.parse_microsoft_response(body), "OHADA")

    def test_azure_sans_parole(self):
        self.assertEqual(bench.parse_microsoft_response(b'{"combinedPhrases": [], "phrases": []}'), "")
        with self.assertRaises(bench.TranscriptionError):
            bench.parse_microsoft_response(b'{"autre": 1}')

    def test_erreurs(self):
        self.assertEqual(bench.extract_error_message(b'{"error": {"message": "Invalid model", "code": "x"}}'),
                         "Invalid model")
        self.assertEqual(bench.extract_error_message(b'{"message": "Unauthorized"}'), "Unauthorized")
        self.assertEqual(bench.extract_error_message(b'{"detail": "Not found"}'), "Not found")
        detail = bench.extract_error_message(b'{"detail": [{"loc": ["body", "model"], "msg": "required"}]}')
        self.assertEqual(json.loads(detail), [{"loc": ["body", "model"], "msg": "required"}])
        self.assertEqual(bench.extract_error_message(b'{"error": {"code": "401", "message": "Access denied"}}'),
                         "Access denied")
        self.assertEqual(bench.extract_error_message(b"x" * 500), "x" * 300)
        self.assertEqual(bench.extract_error_message(b""), "réponse vide")

    def test_priorite_des_champs(self):
        body = b'{"error": {"message": "A"}, "message": "B", "detail": "C"}'
        self.assertEqual(bench.extract_error_message(body), "A")
        self.assertEqual(bench.extract_error_message(b'{"message": "B", "detail": "C"}'), "B")


class VocabularyRecallTests(unittest.TestCase):
    TERMS = bench.vocabulary_terms(bench.DEFAULT_VOCABULARY)

    def test_tous_trouves(self):
        ref = "L'assemblée générale de la SARL a révoqué le gérant."
        hyp = "l\u2019Assemblée Générale de la sarl a révoqué le gérant"
        found, expected, missed = bench.vocabulary_recall(ref, hyp, self.TERMS)
        self.assertEqual((found, expected, missed), (3, 3, []))

    def test_terme_manque(self):
        ref = "Le recours est porté devant la CCJA conformément à l'AUSCGIE."
        hyp = "Le recours est porté devant la CCGA conformément à l'AUSCGIE."
        found, expected, missed = bench.vocabulary_recall(ref, hyp, self.TERMS)
        self.assertEqual((found, expected), (1, 2))
        self.assertEqual(missed, ["CCJA"])

    def test_mots_entiers(self):
        # « SA » ne doit pas être trouvé à l'intérieur de « SAS » ou de « SARL ».
        found, expected, _ = bench.vocabulary_recall("Une SAS au capital social de 1 000 euros.",
                                                     "Une SARL au capital social de 1 000 euros.",
                                                     ["SA", "SAS", "capital social"])
        self.assertEqual((found, expected), (1, 2))

    def test_sigle_et_possessif(self):
        # « sa » (possessif) dans la référence n'est pas le sigle « SA ».
        self.assertEqual(bench.vocabulary_recall("Le gérant et sa famille.", "le gérant et sa famille", ["SA"]),
                         (0, 0, []))
        # Le sigle en majuscules est attendu ; la transcription est comparée sans tenir compte de la casse.
        self.assertEqual(bench.vocabulary_recall("Une SA de droit OHADA.", "une sa de droit ohada", ["SA", "OHADA"]),
                         (2, 2, []))
        self.assertEqual(bench.vocabulary_recall("L'OHADA.", "Lohada", ["OHADA"]), (0, 1, ["OHADA"]))

    def test_aucun_terme_attendu(self):
        self.assertEqual(bench.vocabulary_recall("Bonjour.", "Bonjour.", self.TERMS), (0, 0, []))


class DurationAndStatsTests(unittest.TestCase):
    def test_duree_wav(self):
        import wave
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.wav")
            with wave.open(path, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(16000)
                w.writeframes(b"\x00\x00" * 24000)
            with open(path, "rb") as f:
                self.assertAlmostEqual(bench.audio_duration_seconds(f.read(), ".wav"), 1.5)

    def test_duree_m4a(self):
        mvhd_body = struct.pack(">B3xIIII", 0, 0, 0, 600, 1500) + b"\x00" * 80
        mvhd = struct.pack(">I4s", 8 + len(mvhd_body), b"mvhd") + mvhd_body
        moov = struct.pack(">I4s", 8 + len(mvhd), b"moov") + mvhd
        ftyp = struct.pack(">I4s", 16, b"ftyp") + b"M4A \x00\x00\x00\x00"
        self.assertAlmostEqual(bench.audio_duration_seconds(ftyp + moov, ".m4a"), 2.5)

    def test_duree_inconnue(self):
        self.assertIsNone(bench.audio_duration_seconds(b"ID3....", ".mp3"))
        self.assertIsNone(bench.audio_duration_seconds(b"garbage", ".wav"))

    def test_percentile(self):
        values = list(range(1, 11))
        self.assertEqual(bench.percentile(values, 0.9), 9)
        self.assertEqual(bench.percentile([5.0], 0.9), 5.0)
        self.assertIsNone(bench.percentile([], 0.9))


class SafetyTests(unittest.TestCase):
    def test_cles_masquees(self):
        masked = bench.mask_headers({"Authorization": "Bearer sk-abc", "Ocp-Apim-Subscription-Key": "zzz"})
        self.assertNotIn("sk-abc", json.dumps(masked))
        self.assertNotIn("zzz", json.dumps(masked))

    def test_describe_sans_cle(self):
        for provider in bench.PROVIDERS:
            req = bench.build_request(provider, AUDIO, ".wav", "SECRET-KEY-123", "m", "fr", "OHADA", "eastus")
            self.assertNotIn("SECRET-KEY-123", bench.describe_request(req))

    def test_redaction(self):
        self.assertEqual(bench.redact("clé sk-1234567 invalide", "sk-1234567"), "clé *** invalide")


class SamplesTests(unittest.TestCase):
    def test_reference_optionnelle(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ("a.wav", "b.m4a", "notes.docx"):
                open(os.path.join(tmp, name), "wb").close()
            with open(os.path.join(tmp, "a.txt"), "w", encoding="utf-8") as f:
                f.write("\ufeffLe gérant.\n")
            samples = bench.find_samples(tmp)
            self.assertEqual([s.name for s in samples], ["a.wav", "b.m4a"])
            self.assertEqual(samples[0].reference, "Le gérant.")
            self.assertIsNone(samples[1].reference)


if __name__ == "__main__":
    unittest.main()
