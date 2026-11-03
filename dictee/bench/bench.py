#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Banc d'essai des moteurs de transcription de Dictée.

Compare OpenAI, Mistral Voxtral et Microsoft MAI-Transcribe-2 sur vos propres dictées :
précision (WER, rappel du vocabulaire), rapidité (latence de bout en bout) et coût estimé.

Les requêtes reproduisent exactement celles des applications (dictee/SPEC.md, §2, §2 bis et §3).
L'outil sert aussi à confirmer les noms de modèles et le format Azure.

Python 3.9 ou plus récent, bibliothèque standard uniquement. Fonctionne sur Mac, Windows et Linux.

Utilisation rapide :
    python3 bench.py echantillons
    python3 bench.py echantillons --providers openai,mistral --repeat 3
    python3 bench.py echantillons --dry-run

Les clés sont lues dans OPENAI_API_KEY, MISTRAL_API_KEY et AZURE_SPEECH_KEY (+ AZURE_SPEECH_REGION).
Elles ne sont jamais affichées ni écrites dans un fichier.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import json
import math
import os
import re
import socket
import ssl
import statistics
import struct
import sys
import time
import unicodedata
import urllib.error
import urllib.request
import uuid
from typing import Dict, List, Optional, Sequence, Tuple, Union

# ---------------------------------------------------------------------------
# Constantes (SPEC §2 bis et §3)
# ---------------------------------------------------------------------------

PROVIDERS = ("openai", "mistral", "microsoft")

PROVIDER_LABELS = {"openai": "OpenAI", "mistral": "Mistral", "microsoft": "Microsoft"}

KEY_ENV = {
    "openai": "OPENAI_API_KEY",
    "mistral": "MISTRAL_API_KEY",
    "microsoft": "AZURE_SPEECH_KEY",
}

DEFAULT_MODELS = {
    "openai": "gpt-transcribe",
    "mistral": "voxtral-small-transcribe-3",
    "microsoft": "mai-transcribe-2",
}

DEFAULT_AZURE_REGION = "eastus"
DEFAULT_LANGUAGE = "fr"
TIMEOUT_SECONDS = 120
MAX_VOCABULARY_TERMS = 100
AZURE_API_VERSION = "2025-10-15"

OPENAI_URL = "https://api.openai.com/v1/audio/transcriptions"
MISTRAL_URL = "https://api.mistral.ai/v1/audio/transcriptions"
AZURE_URL_TEMPLATE = (
    "https://{region}.api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe"
    "?api-version=" + AZURE_API_VERSION
)

DEFAULT_VOCABULARY = (
    "OHADA, AUSCGIE, AUDCG, AUPCAP, AUPSRVE, CCJA, SARL, SA, SAS, SNC, GIE, RCCM, "
    "assemblée générale, conseil d'administration, commissaire aux comptes, gérant, "
    "statuts, capital social"
)

# Prix en dollars US par minute d'audio.
# À VÉRIFIER : valeurs relevées dans le cahier des charges (novembre 2026), non confirmées
# sur les pages tarifaires des fournisseurs. Corrigez-les ici si besoin.
PRICE_PER_MINUTE_USD = {
    ("openai", "gpt-transcribe"): 0.0045,       # à vérifier
    ("openai", "gpt-4o-transcribe"): 0.006,     # à vérifier
    ("openai", "gpt-4o-mini-transcribe"): 0.003,  # à vérifier
    ("openai", "whisper-1"): 0.006,             # à vérifier
    ("mistral", "voxtral-small-transcribe-3"): 0.004,   # à vérifier
    ("mistral", "voxtral-mini-transcribe-3"): 0.0035,   # à vérifier
    ("microsoft", "mai-transcribe-2"): 0.0017,  # à vérifier (tarif promotionnel)
}

AUDIO_EXTENSIONS = {
    ".wav": "audio/wav",
    ".m4a": "audio/mp4",
    ".mp3": "audio/mpeg",
    ".ogg": "audio/ogg",
    ".flac": "audio/flac",
    ".webm": "audio/webm",
}

# Locales Azure explicites (SPEC §2 bis, `microsoft`).
AZURE_LOCALES = {
    "fr": "fr-FR",
    "en": "en-US",
    "es": "es-ES",
    "de": "de-DE",
    "it": "it-IT",
    "pt": "pt-BR",
    "nl": "nl-NL",
    "ar": "ar-SA",
}


# ---------------------------------------------------------------------------
# Configuration : vocabulaire, langue, modèles
# ---------------------------------------------------------------------------


def vocabulary_terms(vocabulary: str) -> List[str]:
    """Découpe le vocabulaire en termes (SPEC §2 bis).

    Séparateurs : virgules, points-virgules, retours à la ligne. Espaces retirées aux extrémités,
    termes vides ignorés, doublons retirés en gardant le premier, 100 termes au maximum.
    """
    terms: List[str] = []
    seen = set()
    for raw in re.split(r"[,;\r\n]", vocabulary or ""):
        term = raw.strip()
        if not term or term in seen:
            continue
        seen.add(term)
        terms.append(term)
        if len(terms) >= MAX_VOCABULARY_TERMS:
            break
    return terms


def azure_locale(language: str) -> Optional[str]:
    """Locale Azure déduite de `language` (SPEC §2 bis). None si la langue est vide."""
    lang = (language or "").strip()
    if not lang:
        return None
    if "-" in lang:
        return lang
    lower = lang.lower()
    if lower in AZURE_LOCALES:
        return AZURE_LOCALES[lower]
    if len(lower) == 2 and lower.isalpha():
        return lower + "-" + lower.upper()
    return lang


def mistral_language(language: str) -> Optional[str]:
    """Code à 2 lettres pour Mistral : `fr-FR` → `fr`. None si la langue est vide."""
    lang = (language or "").strip()
    if not lang:
        return None
    return re.split(r"[-_]", lang, maxsplit=1)[0].lower()


def or_default(value: Optional[str], default: str) -> str:
    """Une valeur vide ou faite d'espaces revient à la valeur par défaut (SPEC §3)."""
    value = (value or "").strip()
    return value or default


# ---------------------------------------------------------------------------
# Construction des requêtes
# ---------------------------------------------------------------------------

# Un champ multipart : (nom, valeur texte) ou (nom, FilePart).


class FilePart:
    """Partie fichier d'un corps multipart."""

    def __init__(self, filename: Optional[str], content_type: str, data: bytes):
        self.filename = filename
        self.content_type = content_type
        self.data = data

    def __repr__(self) -> str:  # utile dans les tests et le --dry-run
        return "<fichier {0}, {1}, {2} octets>".format(
            self.filename or "(sans nom)", self.content_type, format_int(len(self.data))
        )


Field = Tuple[str, Union[str, FilePart]]


class PreparedRequest:
    """Requête prête à être encodée et envoyée. Ne contient jamais la clé en clair hors de `headers`."""

    def __init__(self, provider: str, model: str, url: str, headers: Dict[str, str],
                 fields: List[Field], secret: str):
        self.provider = provider
        self.model = model
        self.url = url
        self.headers = headers
        self.fields = fields
        self.secret = secret

    def field_values(self, name: str) -> List[Union[str, FilePart]]:
        return [value for (key, value) in self.fields if key == name]


def encode_multipart(fields: Sequence[Field], boundary: Optional[str] = None) -> Tuple[bytes, str]:
    """Encode les champs en multipart/form-data. Renvoie (corps, valeur de Content-Type)."""
    boundary = boundary or ("----dictee-bench-" + uuid.uuid4().hex)
    lines: List[bytes] = []
    for name, value in fields:
        lines.append(("--" + boundary + "\r\n").encode("ascii"))
        if isinstance(value, FilePart):
            disposition = 'Content-Disposition: form-data; name="{0}"'.format(name)
            if value.filename:
                disposition += '; filename="{0}"'.format(value.filename)
            lines.append((disposition + "\r\n").encode("utf-8"))
            lines.append("Content-Type: {0}\r\n\r\n".format(value.content_type).encode("utf-8"))
            lines.append(value.data)
            lines.append(b"\r\n")
        else:
            lines.append('Content-Disposition: form-data; name="{0}"\r\n\r\n'.format(name).encode("utf-8"))
            lines.append(value.encode("utf-8"))
            lines.append(b"\r\n")
    lines.append(("--" + boundary + "--\r\n").encode("ascii"))
    return b"".join(lines), "multipart/form-data; boundary=" + boundary


def audio_part(audio: bytes, extension: str) -> FilePart:
    """Le fichier est toujours nommé `audio.<ext>` : le nom de vos fichiers n'est jamais envoyé."""
    ext = extension.lower()
    content_type = AUDIO_EXTENSIONS.get(ext, "application/octet-stream")
    return FilePart("audio" + ext, content_type, audio)


def build_openai_request(audio: bytes, extension: str, key: str, model: str,
                         language: str, vocabulary: str) -> PreparedRequest:
    """OpenAI : model, response_format=json, language, prompt = vocabulaire brut, file."""
    fields: List[Field] = [("model", model), ("response_format", "json")]
    if (language or "").strip():
        fields.append(("language", language.strip()))
    if (vocabulary or "").strip():
        fields.append(("prompt", vocabulary.strip()))
    fields.append(("file", audio_part(audio, extension)))
    headers = {"Authorization": "Bearer " + key}
    return PreparedRequest("openai", model, OPENAI_URL, headers, fields, key)


def build_mistral_request(audio: bytes, extension: str, key: str, model: str,
                          language: str, vocabulary: str) -> PreparedRequest:
    """Mistral : model, language (2 lettres), context_bias répété par terme, file. Ni prompt ni response_format."""
    fields: List[Field] = [("model", model)]
    lang = mistral_language(language)
    if lang:
        fields.append(("language", lang))
    for term in vocabulary_terms(vocabulary):
        fields.append(("context_bias", term))
    fields.append(("file", audio_part(audio, extension)))
    headers = {"Authorization": "Bearer " + key}
    return PreparedRequest("mistral", model, MISTRAL_URL, headers, fields, key)


def azure_definition(model: str, language: str, vocabulary: str) -> Dict:
    """Objet JSON de la partie `definition` d'Azure fast transcription."""
    definition: Dict = {}
    locale = azure_locale(language)
    if locale:
        definition["locales"] = [locale]
    definition["enhancedMode"] = {"enabled": True, "model": model}
    terms = vocabulary_terms(vocabulary)
    if terms:
        definition["phraseList"] = {"phrases": terms}
    return definition


def build_microsoft_request(audio: bytes, extension: str, key: str, model: str,
                            language: str, vocabulary: str, region: str) -> PreparedRequest:
    """Azure AI Speech : parties `audio` et `definition` (JSON)."""
    region = or_default(region, DEFAULT_AZURE_REGION)
    definition = azure_definition(model, language, vocabulary)
    fields: List[Field] = [
        ("audio", audio_part(audio, extension)),
        ("definition", FilePart(None, "application/json",
                                json.dumps(definition, ensure_ascii=False).encode("utf-8"))),
    ]
    headers = {"Ocp-Apim-Subscription-Key": key}
    url = AZURE_URL_TEMPLATE.format(region=region)
    return PreparedRequest("microsoft", model, url, headers, fields, key)


def build_request(provider: str, audio: bytes, extension: str, key: str, model: str,
                  language: str, vocabulary: str, region: str) -> PreparedRequest:
    if provider == "openai":
        return build_openai_request(audio, extension, key, model, language, vocabulary)
    if provider == "mistral":
        return build_mistral_request(audio, extension, key, model, language, vocabulary)
    if provider == "microsoft":
        return build_microsoft_request(audio, extension, key, model, language, vocabulary, region)
    raise ValueError("Fournisseur inconnu : " + provider)


# ---------------------------------------------------------------------------
# Parsing des réponses
# ---------------------------------------------------------------------------


class TranscriptionError(Exception):
    """Erreur lisible, au format de l'app : « Erreur <Fournisseur> (<code>) : <message> »."""

    def __init__(self, message: str, status: Optional[int] = None):
        super().__init__(message)
        self.status = status


def _load_json(body: bytes):
    try:
        return json.loads(body.decode("utf-8-sig"))
    except (ValueError, UnicodeDecodeError):
        return None


def extract_error_message(body: bytes) -> str:
    """Message d'erreur : error.message, sinon message, sinon detail (texte ou JSON), sinon 300 caractères."""
    data = _load_json(body)
    if isinstance(data, dict):
        error = data.get("error")
        if isinstance(error, dict) and isinstance(error.get("message"), str) and error["message"].strip():
            return error["message"].strip()
        if isinstance(error, str) and error.strip():
            return error.strip()
        message = data.get("message")
        if isinstance(message, str) and message.strip():
            return message.strip()
        detail = data.get("detail")
        if isinstance(detail, str) and detail.strip():
            return detail.strip()
        if detail is not None and not isinstance(detail, str):
            return json.dumps(detail, ensure_ascii=False)
    text = body.decode("utf-8", errors="replace").strip()
    return text[:300] if text else "réponse vide"


def parse_openai_response(body: bytes) -> str:
    data = _load_json(body)
    if not isinstance(data, dict) or not isinstance(data.get("text"), str):
        raise TranscriptionError("Réponse OpenAI inattendue : " + body[:300].decode("utf-8", "replace"))
    return data["text"].strip()


def parse_mistral_response(body: bytes) -> str:
    data = _load_json(body)
    if not isinstance(data, dict) or not isinstance(data.get("text"), str):
        raise TranscriptionError("Réponse Mistral inattendue : " + body[:300].decode("utf-8", "replace"))
    return data["text"].strip()


def parse_microsoft_response(body: bytes) -> str:
    """combinedPhrases[0].text ; si absent, phrases[].text joints par des espaces."""
    data = _load_json(body)
    if not isinstance(data, dict):
        raise TranscriptionError("Réponse Microsoft inattendue : " + body[:300].decode("utf-8", "replace"))
    combined = data.get("combinedPhrases")
    if isinstance(combined, list) and combined and isinstance(combined[0], dict):
        text = combined[0].get("text")
        if isinstance(text, str) and text.strip():
            return text.strip()
    phrases = data.get("phrases")
    if isinstance(phrases, list):
        parts = [p.get("text", "").strip() for p in phrases
                 if isinstance(p, dict) and isinstance(p.get("text"), str) and p.get("text", "").strip()]
        if parts:
            return " ".join(parts)
    if "combinedPhrases" in data or "phrases" in data:
        return ""  # réponse valide, mais aucune parole reconnue
    raise TranscriptionError("Réponse Microsoft inattendue : " + body[:300].decode("utf-8", "replace"))


PARSERS = {
    "openai": parse_openai_response,
    "mistral": parse_mistral_response,
    "microsoft": parse_microsoft_response,
}


def reported_duration_seconds(provider: str, body: bytes) -> Optional[float]:
    """Durée audio éventuellement renvoyée par le fournisseur (sert au calcul du coût hors WAV)."""
    data = _load_json(body)
    if not isinstance(data, dict):
        return None
    candidates = []
    if provider == "microsoft":
        candidates.append(_num(data.get("durationMilliseconds"), 1 / 1000.0))
    usage = data.get("usage") if isinstance(data.get("usage"), dict) else {}
    candidates.append(_num(usage.get("prompt_audio_seconds"), 1.0))
    candidates.append(_num(usage.get("seconds"), 1.0))
    candidates.append(_num(data.get("duration"), 1.0))
    for value in candidates:
        if value:
            return value
    return None


def _num(value, factor: float) -> Optional[float]:
    if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0:
        return float(value) * factor
    return None


# ---------------------------------------------------------------------------
# Envoi
# ---------------------------------------------------------------------------


def send_request(request: PreparedRequest, timeout: float = TIMEOUT_SECONDS) -> Tuple[bytes, float]:
    """Envoie la requête. Renvoie (corps de la réponse, latence en ms).

    La latence couvre l'envoi complet de la requête jusqu'à la lecture complète de la réponse.
    Lève TranscriptionError en cas d'échec (message sans la clé).
    """
    label = PROVIDER_LABELS[request.provider]
    body, content_type = encode_multipart(request.fields)
    headers = dict(request.headers)
    headers["Content-Type"] = content_type
    headers["Accept"] = "application/json"
    headers["User-Agent"] = "dictee-bench/1.0"
    http_request = urllib.request.Request(request.url, data=body, headers=headers, method="POST")
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(http_request, timeout=timeout) as response:
            payload = response.read()
        latency_ms = (time.perf_counter() - start) * 1000.0
        return payload, latency_ms
    except urllib.error.HTTPError as exc:
        payload = exc.read() if hasattr(exc, "read") else b""
        message = "Erreur {0} ({1}) : {2}".format(label, exc.code, extract_error_message(payload or b""))
        raise TranscriptionError(redact(message, request.secret), exc.code)
    except (socket.timeout, TimeoutError):
        raise TranscriptionError("Erreur {0} : délai dépassé ({1} s)".format(label, int(timeout)))
    except urllib.error.URLError as exc:
        reason = exc.reason
        if isinstance(reason, (socket.timeout, TimeoutError)):
            raise TranscriptionError("Erreur {0} : délai dépassé ({1} s)".format(label, int(timeout)))
        hint = ""
        if isinstance(reason, ssl.SSLError) or "CERTIFICATE" in str(reason).upper():
            hint = (" (certificats SSL : sur Mac, lancez « Install Certificates.command » "
                    "dans le dossier Python des Applications)")
        raise TranscriptionError(redact("Erreur {0} : connexion impossible : {1}{2}".format(label, reason, hint),
                                        request.secret))
    except OSError as exc:
        raise TranscriptionError(redact("Erreur {0} : {1}".format(label, exc), request.secret))


def redact(text: str, secret: str) -> str:
    """Retire la clé d'un message, au cas où un serveur la renverrait."""
    if secret and len(secret) >= 6:
        text = text.replace(secret, "***")
    return text


def mask_headers(headers: Dict[str, str]) -> Dict[str, str]:
    masked = {}
    for name, value in headers.items():
        if name.lower() == "authorization":
            masked[name] = "Bearer <clé masquée>"
        elif name.lower() == "ocp-apim-subscription-key":
            masked[name] = "<clé masquée>"
        else:
            masked[name] = value
    return masked


# ---------------------------------------------------------------------------
# Normalisation française et WER
# ---------------------------------------------------------------------------

_APOSTROPHES = "\u2019\u2018\u02bc\u02b9`\u00b4\u2032\uff07"
_HYPHENS = "\u2010\u2011\u2012\u2013\u2014\u2015\u2212\ufe63\uff0d"
_KEEP_INSIDE = "'-"
_ELISIONS = ("l'", "d'", "j'", "m'", "n'", "s'", "t'", "c'", "ç'", "qu'",
             "jusqu'", "lorsqu'", "puisqu'", "quoiqu'", "presqu'", "quelqu'")
_ELISION_RE = re.compile(r"^(" + "|".join(sorted(_ELISIONS, key=len, reverse=True)) + r")(.+)$", re.IGNORECASE)


def normalize_text(text: str, lowercase: bool = True) -> str:
    """Normalisation française pour le WER.

    Minuscules, apostrophes et tirets unifiés (’ → ', – → -), ponctuation supprimée
    (l'apostrophe et le trait d'union restent à l'intérieur des mots : « aujourd'hui »,
    « peut-être »), élisions séparées (« l'assemblée » → « l' assemblée »), espaces multiples
    réduites. Les accents sont conservés. `lowercase=False` garde la casse (repérage des sigles).
    """
    text = unicodedata.normalize("NFC", text or "")
    if lowercase:
        text = text.lower()
    for char in _APOSTROPHES:
        text = text.replace(char, "'")
    for char in _HYPHENS:
        text = text.replace(char, "-")
    out = []
    for char in text:
        if char in _KEEP_INSIDE:
            out.append(char)
            continue
        category = unicodedata.category(char)
        if category[0] in ("P", "S") or category[0] == "Z" or char.isspace() or category == "Cc":
            out.append(" ")
        else:
            out.append(char)
    tokens: List[str] = []
    for token in "".join(out).split():
        # Apostrophe ou tiret en bordure de mot : retirés, sauf l'apostrophe d'une élision isolée (« l' »).
        token = token.lstrip(_KEEP_INSIDE).rstrip("-")
        if token.endswith("'") and token.lower().rstrip("'") + "'" not in _ELISIONS:
            token = token.rstrip("'-")
        # Élision séparée du mot : « l'assemblée » → « l' assemblée », « qu'il » → « qu' il ».
        while token:
            match = _ELISION_RE.match(token)
            if not match:
                break
            tokens.append(match.group(1))
            token = match.group(2).lstrip(_KEEP_INSIDE)
        if token:
            tokens.append(token)
    return " ".join(tokens)


def tokenize(text: str, lowercase: bool = True) -> List[str]:
    return normalize_text(text, lowercase).split()


def align_words(reference: Sequence[str], hypothesis: Sequence[str]) -> List[Tuple[str, Optional[str], Optional[str]]]:
    """Alignement de Levenshtein sur les mots, implémenté à la main.

    Renvoie une liste d'opérations (op, mot_ref, mot_hyp) avec op ∈ {"=", "S", "D", "I"} :
    égal, substitution, suppression (mot de la référence absent), insertion (mot en trop).
    """
    n, m = len(reference), len(hypothesis)
    # dist[i][j] = coût minimal pour transformer reference[:i] en hypothesis[:j]
    dist = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        dist[i][0] = i
    for j in range(1, m + 1):
        dist[0][j] = j
    for i in range(1, n + 1):
        ref_word = reference[i - 1]
        row, prev = dist[i], dist[i - 1]
        for j in range(1, m + 1):
            cost = 0 if ref_word == hypothesis[j - 1] else 1
            row[j] = min(prev[j - 1] + cost, prev[j] + 1, row[j - 1] + 1)
    ops: List[Tuple[str, Optional[str], Optional[str]]] = []
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and dist[i][j] == dist[i - 1][j - 1] + (0 if reference[i - 1] == hypothesis[j - 1] else 1):
            op = "=" if reference[i - 1] == hypothesis[j - 1] else "S"
            ops.append((op, reference[i - 1], hypothesis[j - 1]))
            i, j = i - 1, j - 1
        elif i > 0 and dist[i][j] == dist[i - 1][j] + 1:
            ops.append(("D", reference[i - 1], None))
            i -= 1
        else:
            ops.append(("I", None, hypothesis[j - 1]))
            j -= 1
    ops.reverse()
    return ops


def word_errors(reference: str, hypothesis: str) -> Tuple[int, int]:
    """(nombre d'erreurs, nombre de mots de la référence) après normalisation."""
    ref = tokenize(reference)
    hyp = tokenize(hypothesis)
    errors = sum(1 for op, _, _ in align_words(ref, hyp) if op != "=")
    return errors, len(ref)


def wer(reference: str, hypothesis: str) -> float:
    """Taux d'erreur sur les mots (0.0 = parfait ; peut dépasser 1.0 si beaucoup d'insertions)."""
    errors, total = word_errors(reference, hypothesis)
    if total == 0:
        return 0.0 if not tokenize(hypothesis) else 1.0
    return errors / total


def diff_markdown(reference: str, hypothesis: str) -> str:
    """Différences simples : ~~mot de la référence~~ manquant ou remplacé, **mot transcrit** fautif ou en trop."""
    parts = []
    for op, ref_word, hyp_word in align_words(tokenize(reference), tokenize(hypothesis)):
        if op == "=":
            parts.append(md_escape(ref_word or ""))
        elif op == "S":
            parts.append("~~{0}~~ **{1}**".format(md_escape(ref_word or ""), md_escape(hyp_word or "")))
        elif op == "D":
            parts.append("~~{0}~~".format(md_escape(ref_word or "")))
        else:
            parts.append("**{0}**".format(md_escape(hyp_word or "")))
    return " ".join(parts)


# ---------------------------------------------------------------------------
# Rappel du vocabulaire
# ---------------------------------------------------------------------------


def _contains_sequence(tokens: Sequence[str], needle: Sequence[str]) -> bool:
    if not needle or len(needle) > len(tokens):
        return False
    first = needle[0]
    size = len(needle)
    for start in range(len(tokens) - size + 1):
        if tokens[start] == first and list(tokens[start:start + size]) == list(needle):
            return True
    return False


def vocabulary_recall(reference: str, hypothesis: str, terms: Sequence[str]) -> Tuple[int, int, List[str]]:
    """Rappel du vocabulaire.

    Parmi les termes présents dans la référence (mots entiers, après normalisation, casse ignorée),
    compte ceux qui figurent aussi dans la transcription (casse ignorée). Renvoie (trouvés, attendus,
    termes manqués).

    Exception : un sigle écrit tout en majuscules dans le vocabulaire (« SA ») n'est attendu que s'il
    figure en majuscules dans la référence, pour ne pas confondre la société anonyme et le possessif « sa ».
    """
    ref_tokens = tokenize(reference)
    ref_cased = tokenize(reference, lowercase=False)
    hyp_tokens = tokenize(hypothesis)
    found, expected, missed = 0, 0, []
    seen = set()
    for term in terms:
        needle = tokenize(term)
        key = " ".join(needle)
        if not needle or key in seen:
            continue
        seen.add(key)
        is_acronym = term.isupper()
        in_reference = (_contains_sequence(ref_cased, tokenize(term, lowercase=False)) if is_acronym
                        else _contains_sequence(ref_tokens, needle))
        if in_reference:
            expected += 1
            if _contains_sequence(hyp_tokens, needle):
                found += 1
            else:
                missed.append(term)
    return found, expected, missed


# ---------------------------------------------------------------------------
# Échantillons et durée audio
# ---------------------------------------------------------------------------


class Sample:
    def __init__(self, path: str, reference: Optional[str]):
        self.path = path
        self.name = os.path.basename(path)
        self.extension = os.path.splitext(path)[1].lower()
        self.reference = reference
        self._audio: Optional[bytes] = None
        self.duration_s: Optional[float] = None

    @property
    def audio(self) -> bytes:
        if self._audio is None:
            with open(self.path, "rb") as handle:
                self._audio = handle.read()
            self.duration_s = audio_duration_seconds(self._audio, self.extension)
        return self._audio


def read_text_file(path: str) -> str:
    with open(path, "rb") as handle:
        raw = handle.read()
    for encoding in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            return raw.decode(encoding).strip()
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace").strip()


def find_samples(path: str) -> List[Sample]:
    """Enregistrements d'un dossier (ou un fichier seul), avec leur .txt de référence s'il existe."""
    if os.path.isfile(path):
        files = [path]
    elif os.path.isdir(path):
        files = [os.path.join(path, name) for name in sorted(os.listdir(path), key=str.lower)]
    else:
        raise SystemExit("Dossier introuvable : " + path)
    samples = []
    for file_path in files:
        base, ext = os.path.splitext(file_path)
        if ext.lower() not in AUDIO_EXTENSIONS or os.path.basename(file_path).startswith("."):
            continue
        reference = None
        for candidate in (base + ".txt", base + ".TXT"):
            if os.path.isfile(candidate):
                reference = read_text_file(candidate)
                break
        samples.append(Sample(file_path, reference))
    return samples


def audio_duration_seconds(data: bytes, extension: str) -> Optional[float]:
    """Durée lue dans l'en-tête (WAV, M4A/MP4, FLAC). None si inconnue (MP3, OGG, WebM)."""
    try:
        if extension == ".wav":
            return _wav_duration(data)
        if extension == ".m4a":
            return _mp4_duration(data)
        if extension == ".flac":
            return _flac_duration(data)
    except (struct.error, ValueError, IndexError, ZeroDivisionError):
        return None
    return None


def _wav_duration(data: bytes) -> Optional[float]:
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return None
    pos, byte_rate, data_size = 12, None, None
    while pos + 8 <= len(data):
        chunk_id = data[pos:pos + 4]
        size = struct.unpack("<I", data[pos + 4:pos + 8])[0]
        if chunk_id == b"fmt ":
            byte_rate = struct.unpack("<I", data[pos + 16:pos + 20])[0]
        elif chunk_id == b"data":
            data_size = min(size, len(data) - pos - 8)
            break
        pos += 8 + size + (size & 1)
    if byte_rate and data_size is not None:
        return data_size / float(byte_rate)
    return None


def _mp4_duration(data: bytes) -> Optional[float]:
    def boxes(start: int, end: int):
        pos = start
        while pos + 8 <= end:
            size, kind = struct.unpack(">I4s", data[pos:pos + 8])
            header = 8
            if size == 1:
                size = struct.unpack(">Q", data[pos + 8:pos + 16])[0]
                header = 16
            elif size == 0:
                size = end - pos
            if size < header:
                return
            yield kind, pos + header, pos + size
            pos += size

    for kind, body_start, body_end in boxes(0, len(data)):
        if kind != b"moov":
            continue
        for sub, sub_start, _ in boxes(body_start, body_end):
            if sub != b"mvhd":
                continue
            version = data[sub_start]
            if version == 1:
                timescale, duration = struct.unpack(">IQ", data[sub_start + 20:sub_start + 32])
            else:
                timescale, duration = struct.unpack(">II", data[sub_start + 12:sub_start + 20])
            return duration / float(timescale) if timescale else None
    return None


def _flac_duration(data: bytes) -> Optional[float]:
    if data[:4] != b"fLaC":
        return None
    info = data[8:8 + 34]  # bloc STREAMINFO
    packed = int.from_bytes(info[10:18], "big")
    sample_rate = packed >> 44
    total_samples = packed & ((1 << 36) - 1)
    return total_samples / float(sample_rate) if sample_rate and total_samples else None


# ---------------------------------------------------------------------------
# Banc d'essai
# ---------------------------------------------------------------------------


class Config:
    """Un couple fournisseur + modèle à tester."""

    def __init__(self, provider: str, model: str):
        self.provider = provider
        self.model = model

    @property
    def label(self) -> str:
        return "{0}:{1}".format(self.provider, self.model)

    @property
    def price_per_minute(self) -> Optional[float]:
        return PRICE_PER_MINUTE_USD.get((self.provider, self.model))


class RunResult:
    def __init__(self, config: Config, sample: Sample, attempt: int):
        self.config = config
        self.sample = sample
        self.attempt = attempt
        self.text: Optional[str] = None
        self.latency_ms: Optional[float] = None
        self.error: Optional[str] = None
        self.status: Optional[int] = None
        self.wer: Optional[float] = None
        self.errors: Optional[int] = None
        self.ref_words: Optional[int] = None
        self.vocab_found = 0
        self.vocab_expected = 0
        self.vocab_missed: List[str] = []
        self.duration_s: Optional[float] = None


def score_result(result: RunResult, terms: Sequence[str]) -> None:
    reference = result.sample.reference
    if result.text is None or reference is None:
        return
    result.errors, result.ref_words = word_errors(reference, result.text)
    result.wer = wer(reference, result.text)
    result.vocab_found, result.vocab_expected, result.vocab_missed = vocabulary_recall(reference, result.text, terms)


def percentile(values: Sequence[float], fraction: float) -> Optional[float]:
    """Percentile par rang le plus proche (p90 : 90 % des valeurs sont inférieures ou égales)."""
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, int(math.ceil(fraction * len(ordered))))
    return ordered[rank - 1]


class Summary:
    def __init__(self, config: Config, results: List[RunResult]):
        self.config = config
        ok = [r for r in results if r.error is None]
        self.calls = len(results)
        self.errors = len(results) - len(ok)
        latencies = [r.latency_ms for r in ok if r.latency_ms is not None]
        self.latency_median = statistics.median(latencies) if latencies else None
        self.latency_p90 = percentile(latencies, 0.9)
        # WER moyen : moyenne par fichier (moyenne des répétitions d'un même fichier d'abord).
        per_file: Dict[str, List[float]] = {}
        for r in ok:
            if r.wer is not None:
                per_file.setdefault(r.sample.path, []).append(r.wer)
        file_wers = [sum(v) / len(v) for v in per_file.values()]
        self.scored_files = len(file_wers)
        self.wer_mean = sum(file_wers) / len(file_wers) if file_wers else None
        total_errors = sum(r.errors for r in ok if r.errors is not None)
        total_words = sum(r.ref_words for r in ok if r.ref_words is not None)
        self.wer_global = (total_errors / total_words) if total_words else None
        found = sum(r.vocab_found for r in ok)
        expected = sum(r.vocab_expected for r in ok)
        self.vocab_recall = (found / expected) if expected else None
        self.vocab_found, self.vocab_expected = found, expected
        # Coût : durée de chaque appel réussi × prix/min (les appels en erreur ne sont pas facturés).
        price = config.price_per_minute
        durations = [r.duration_s for r in ok]
        self.unknown_durations = sum(1 for d in durations if not d)
        self.audio_minutes = sum(d for d in durations if d) / 60.0
        self.cost = (self.audio_minutes * price) if price is not None else None
        self.cost_per_hour = (price * 60.0) if price is not None else None
        self.error_messages = sorted({r.error for r in results if r.error})


def build_configs(args: argparse.Namespace, providers: Sequence[str]) -> List[Config]:
    compare = {
        "openai": args.compare_openai_models,
        "mistral": args.compare_mistral_models,
        "microsoft": args.compare_microsoft_models,
    }
    single = {
        "openai": or_default(args.openai_model, DEFAULT_MODELS["openai"]),
        "mistral": or_default(args.mistral_model, DEFAULT_MODELS["mistral"]),
        "microsoft": or_default(args.microsoft_model, DEFAULT_MODELS["microsoft"]),
    }
    configs = []
    for provider in providers:
        models = [m.strip() for m in (compare[provider] or "").split(",") if m.strip()]
        if not models:
            models = [single[provider]]
        for model in dict.fromkeys(models):
            configs.append(Config(provider, model))
    return configs


def resolve_providers(requested: Optional[str], keys: Dict[str, str], dry_run: bool) -> List[str]:
    if requested:
        providers = []
        for name in requested.split(","):
            name = name.strip().lower()
            if not name:
                continue
            if name not in PROVIDERS:
                raise SystemExit("Fournisseur inconnu : « {0} ». Valeurs possibles : {1}.".format(
                    name, ", ".join(PROVIDERS)))
            if name not in providers:
                providers.append(name)
    else:
        providers = [p for p in PROVIDERS if keys.get(p)]
        if not providers and dry_run:
            providers = list(PROVIDERS)
    if not dry_run:
        missing = [p for p in providers if not keys.get(p)]
        for p in missing:
            print("Clé API {0} manquante. Définissez la variable d'environnement {1}. Fournisseur ignoré.".format(
                PROVIDER_LABELS[p], KEY_ENV[p]), file=sys.stderr)
        providers = [p for p in providers if keys.get(p)]
    if not providers:
        raise SystemExit(
            "Aucun fournisseur utilisable : définissez au moins une clé "
            "(OPENAI_API_KEY, MISTRAL_API_KEY ou AZURE_SPEECH_KEY). Voir le README."
        )
    return providers


def run_benchmark(samples: Sequence[Sample], configs: Sequence[Config], keys: Dict[str, str],
                  language: str, vocabulary: str, region: str, repeat: int,
                  timeout: float) -> List[RunResult]:
    terms = vocabulary_terms(vocabulary)
    results: List[RunResult] = []
    total = len(samples) * len(configs) * repeat
    done = 0
    # Ordre entrelacé (fichier → répétition → fournisseur) pour ne favoriser personne
    # si le réseau ralentit en cours de route.
    for sample in samples:
        for attempt in range(1, repeat + 1):
            for config in configs:
                done += 1
                result = RunResult(config, sample, attempt)
                try:
                    request = build_request(config.provider, sample.audio, sample.extension,
                                            keys[config.provider], config.model, language, vocabulary, region)
                    body, result.latency_ms = send_request(request, timeout)
                    result.text = PARSERS[config.provider](body)
                    result.duration_s = sample.duration_s or reported_duration_seconds(config.provider, body)
                    score_result(result, terms)
                except TranscriptionError as exc:
                    result.error = str(exc)
                    result.status = exc.status
                except OSError as exc:  # fichier illisible, etc.
                    result.error = "Erreur : {0}".format(exc)
                results.append(result)
                print(progress_line(done, total, result), flush=True)
    return results


def progress_line(done: int, total: int, result: RunResult) -> str:
    head = "[{0}/{1}] {2} · {3}".format(done, total, result.sample.name, result.config.label)
    if result.error:
        return head + " · " + result.error
    parts = [head, "{0} ms".format(format_int(round(result.latency_ms or 0)))]
    if result.wer is not None:
        parts.append("WER " + format_pct(result.wer))
    else:
        parts.append("sans référence")
    return " · ".join(parts)


# ---------------------------------------------------------------------------
# Mise en forme
# ---------------------------------------------------------------------------


def format_int(value: float) -> str:
    return "{0:,}".format(int(value)).replace(",", " ")


def format_pct(value: Optional[float]) -> str:
    return "n.d." if value is None else "{0:.1f} %".format(value * 100).replace(".", ",")


def format_ms(value: Optional[float]) -> str:
    return "n.d." if value is None else "{0} ms".format(format_int(round(value)))


def format_usd(value: Optional[float], digits: int = 4) -> str:
    return "n.d." if value is None else ("{0:." + str(digits) + "f} $").format(value).replace(".", ",")


def md_escape(text: str) -> str:
    return re.sub(r"([\\`*_~|\[\]<>#])", r"\\\1", text)


def md_cell(text: str) -> str:
    return md_escape(" ".join((text or "").split()))


def summary_rows(summaries: Sequence[Summary]) -> List[List[str]]:
    rows = []
    for s in summaries:
        rows.append([
            s.config.label,
            format_pct(s.wer_mean),
            format_ms(s.latency_median),
            format_ms(s.latency_p90),
            format_pct(s.vocab_recall),
            "{0}/{1}".format(s.errors, s.calls),
            format_usd(s.cost_per_hour, 2),
            format_usd(s.cost),
        ])
    return rows


SUMMARY_HEADERS = ["Configuration", "WER moyen", "Latence méd.", "Latence p90", "Rappel vocab.",
                   "Erreurs", "Coût/heure*", "Coût du banc*"]


def text_table(headers: Sequence[str], rows: Sequence[Sequence[str]]) -> str:
    widths = [max(len(str(c)) for c in col) for col in zip(headers, *rows)]

    def line(cells):
        return "  ".join(str(c).ljust(w) for c, w in zip(cells, widths)).rstrip()

    sep = "  ".join("-" * w for w in widths)
    return "\n".join([line(headers), sep] + [line(r) for r in rows])


def verdict_lines(summaries: Sequence[Summary]) -> List[str]:
    lines = []
    scored = [s for s in summaries if s.wer_mean is not None]
    if scored:
        best = min(scored, key=lambda s: s.wer_mean)
        lines.append("Le plus précis : {0} (WER moyen {1}).".format(best.config.label, format_pct(best.wer_mean)))
    timed = [s for s in summaries if s.latency_median is not None]
    if timed:
        fast = min(timed, key=lambda s: s.latency_median)
        lines.append("Le plus rapide : {0} (latence médiane {1}).".format(fast.config.label,
                                                                          format_ms(fast.latency_median)))
    return lines


def print_summary(summaries: Sequence[Summary]) -> None:
    print()
    print("Récapitulatif")
    print("=============")
    print(text_table(SUMMARY_HEADERS, summary_rows(summaries)))
    print("* Coût estimé à partir des prix/min en tête de bench.py (à vérifier). n.d. = prix inconnu.")
    for line in verdict_lines(summaries):
        print(line)
    for s in summaries:
        if s.error_messages:
            print()
            print("Erreurs pour {0} :".format(s.config.label))
            for message in s.error_messages:
                print("  - " + message)


def write_markdown_report(path: str, samples: Sequence[Sample], configs: Sequence[Config],
                          summaries: Sequence[Summary], results: Sequence[RunResult],
                          args: argparse.Namespace, terms: Sequence[str]) -> None:
    now = _dt.datetime.now()
    out: List[str] = []
    out.append("# Banc d'essai de transcription · {0}".format(now.strftime("%d/%m/%Y %H:%M")))
    out.append("")
    out.append("- Échantillons : {0} ({1} avec référence)".format(
        len(samples), sum(1 for s in samples if s.reference is not None)))
    out.append("- Langue : `{0}` · Répétitions : {1} · Région Azure : `{2}`".format(
        args.language or "(vide)", args.repeat, args.azure_region))
    out.append("- Vocabulaire ({0} termes) : {1}".format(len(terms), md_escape(", ".join(terms)) or "(vide)"))
    out.append("")
    out.append("## Récapitulatif")
    out.append("")
    out.append("| " + " | ".join(SUMMARY_HEADERS + ["WER global"]) + " |")
    out.append("|" + "---|" * (len(SUMMARY_HEADERS) + 1))
    for s, row in zip(summaries, summary_rows(summaries)):
        out.append("| " + " | ".join(md_cell(c) for c in row + [format_pct(s.wer_global)]) + " |")
    out.append("")
    out.append("\\* Coût estimé avec les prix/min de la table en tête de `bench.py`, **à vérifier** sur les pages "
               "tarifaires. Le coût du banc ne compte que les appels réussis.")
    out.append("")
    out.append("WER moyen = moyenne des WER par fichier. WER global = total des erreurs / total des mots de "
               "référence (les longues dictées pèsent plus). Rappel vocab. = part des termes du vocabulaire "
               "présents dans la référence qui sont correctement écrits dans la transcription.")
    out.append("")
    for line in verdict_lines(summaries):
        out.append("- " + line)
    out.append("")
    out.append("## Vérification du format des requêtes")
    out.append("")
    out.append("| Configuration | Appels réussis | Statut |")
    out.append("|---|---|---|")
    for s in summaries:
        if s.errors == 0:
            status = "OK : modèle et format acceptés"
        elif s.errors == s.calls:
            status = "ÉCHEC : " + md_cell("; ".join(s.error_messages)[:400])
        else:
            status = "Partiel : " + md_cell("; ".join(s.error_messages)[:400])
        out.append("| {0} | {1}/{2} | {3} |".format(md_cell(s.config.label), s.calls - s.errors, s.calls, status))
    out.append("")
    out.append("## Détail par échantillon")
    out.append("")
    out.append("Légende des différences : ~~mot~~ = mot de la référence manquant ou mal transcrit ; "
               "**mot** = mot transcrit fautif ou en trop. Comparaison faite après normalisation "
               "(minuscules, sans ponctuation).")
    for sample in samples:
        out.append("")
        duration = " · {0:.1f} s".format(sample.duration_s).replace(".", ",") if sample.duration_s else ""
        out.append("### {0}{1}".format(md_escape(sample.name), duration))
        out.append("")
        if sample.reference is not None:
            out.append("**Référence :** " + md_cell(sample.reference))
        else:
            out.append("*Pas de fichier .txt de référence : transcriptions non notées.*")
        out.append("")
        out.append("| Configuration | WER | Latence | Vocab. | Transcription |")
        out.append("|---|---|---|---|---|")
        sample_results = [r for r in results if r.sample is sample]
        diffs = []
        for config in configs:
            runs = [r for r in sample_results if r.config is config]
            ok = [r for r in runs if r.error is None]
            if not ok:
                message = runs[0].error if runs else "non testé"
                out.append("| {0} | – | – | – | ⚠ {1} |".format(md_cell(config.label), md_cell(message or "")))
                continue
            first = ok[0]
            wers = [r.wer for r in ok if r.wer is not None]
            mean_wer = sum(wers) / len(wers) if wers else None
            latency = statistics.median([r.latency_ms for r in ok])
            vocab = "{0}/{1}".format(first.vocab_found, first.vocab_expected) if first.vocab_expected else "–"
            failures = len(runs) - len(ok)
            note = " (+{0} erreur(s))".format(failures) if failures else ""
            out.append("| {0} | {1} | {2}{3} | {4} | {5} |".format(
                md_cell(config.label), format_pct(mean_wer), format_ms(latency), note, vocab,
                md_cell(first.text or "") or "*(vide)*"))
            if sample.reference is not None:
                diffs.append((config.label, first))
        if diffs:
            out.append("")
            out.append("Différences avec la référence (1re transcription réussie) :")
            out.append("")
            for label, run in diffs:
                missed = ""
                if run.vocab_missed:
                    missed = " · termes manqués : " + md_escape(", ".join(run.vocab_missed))
                out.append("- **{0}** ({1} erreur(s){2}) : {3}".format(
                    md_escape(label), run.errors, missed, diff_markdown(sample.reference, run.text or "")
                    or "*(vide)*"))
    out.append("")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(out))


CSV_HEADERS = ["fichier", "fournisseur", "modele", "essai", "duree_audio_s", "latence_ms", "wer",
               "erreurs_mots", "mots_reference", "vocab_trouves", "vocab_attendus", "vocab_manques",
               "statut_http", "erreur", "transcription", "reference"]


def write_csv(path: str, results: Sequence[RunResult]) -> None:
    """CSV séparé par des points-virgules, encodé UTF-8 avec BOM : s'ouvre directement dans Excel en français."""
    with open(path, "w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle, delimiter=";")
        writer.writerow(CSV_HEADERS)
        for r in results:
            writer.writerow([
                r.sample.name,
                r.config.provider,
                r.config.model,
                r.attempt,
                _csv_num(r.duration_s, 2),
                _csv_num(r.latency_ms, 0),
                _csv_num(r.wer, 4),
                "" if r.errors is None else r.errors,
                "" if r.ref_words is None else r.ref_words,
                r.vocab_found if r.vocab_expected else "",
                r.vocab_expected if r.vocab_expected else "",
                ", ".join(r.vocab_missed),
                "" if r.status is None else r.status,
                r.error or "",
                r.text or "",
                r.sample.reference or "",
            ])


def _csv_num(value: Optional[float], digits: int) -> str:
    if value is None:
        return ""
    return ("{0:." + str(digits) + "f}").format(value).replace(".", ",")


# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------


def describe_request(request: PreparedRequest) -> str:
    body, content_type = encode_multipart(request.fields, boundary="----dictee-bench-EXEMPLE")
    headers = mask_headers(request.headers)
    headers["Content-Type"] = content_type
    lines = ["POST " + request.url, "En-têtes :"]
    for name, value in headers.items():
        lines.append("  {0}: {1}".format(name, value))
    lines.append("Champs multipart (dans l'ordre) :")
    for name, value in request.fields:
        if isinstance(value, FilePart) and value.content_type == "application/json":
            pretty = json.dumps(json.loads(value.data.decode("utf-8")), ensure_ascii=False, indent=2)
            lines.append("  {0} ({1}) :".format(name, value.content_type))
            lines.extend("    " + l for l in pretty.splitlines())
        elif isinstance(value, FilePart):
            lines.append("  {0} = {1!r}".format(name, value))
        else:
            lines.append("  {0} = {1}".format(name, value))
    lines.append("Taille du corps : {0} octets".format(format_int(len(body))))
    return "\n".join(lines)


def dry_run(samples: Sequence[Sample], configs: Sequence[Config], keys: Dict[str, str],
            language: str, vocabulary: str, region: str) -> None:
    sample = samples[0]
    print("Mode --dry-run : aucune requête n'est envoyée. Exemple construit avec « {0} » "
          "({1} échantillon(s) au total).".format(sample.name, len(samples)))
    for config in configs:
        key = keys.get(config.provider) or "CLE-ABSENTE"
        request = build_request(config.provider, sample.audio, sample.extension, key, config.model,
                                language, vocabulary, region)
        print()
        title = "{0} ({1})".format(config.label, "clé présente" if keys.get(config.provider) else "clé absente")
        print(title)
        print("-" * len(title))
        print(describe_request(request))


# ---------------------------------------------------------------------------
# Ligne de commande
# ---------------------------------------------------------------------------


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(
        description="Compare la précision et la rapidité des moteurs de transcription de Dictée.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Clés : OPENAI_API_KEY, MISTRAL_API_KEY, AZURE_SPEECH_KEY (+ AZURE_SPEECH_REGION, défaut eastus).",
    )
    parser.add_argument("samples", nargs="?", default=os.path.join(script_dir, "echantillons"),
                        help="dossier des enregistrements (ou un seul fichier). Défaut : echantillons/ à côté du script")
    parser.add_argument("--providers", help="liste séparée par des virgules parmi openai,mistral,microsoft "
                                            "(défaut : tous ceux dont la clé est définie)")
    parser.add_argument("--openai-model", default=DEFAULT_MODELS["openai"],
                        help="défaut : %(default)s")
    parser.add_argument("--mistral-model", default=DEFAULT_MODELS["mistral"],
                        help="défaut : %(default)s")
    parser.add_argument("--microsoft-model", default=DEFAULT_MODELS["microsoft"],
                        help="défaut : %(default)s")
    parser.add_argument("--compare-openai-models", metavar="M1,M2",
                        help="teste plusieurs modèles OpenAI, ex. gpt-transcribe,gpt-4o-transcribe")
    parser.add_argument("--compare-mistral-models", metavar="M1,M2",
                        help="ex. voxtral-small-transcribe-3,voxtral-mini-transcribe-3")
    parser.add_argument("--compare-microsoft-models", metavar="M1,M2", help="plusieurs modèles Microsoft")
    parser.add_argument("--language", default=DEFAULT_LANGUAGE, help="défaut : %(default)s (vide = détection auto)")
    parser.add_argument("--vocabulary", default=None, help="vocabulaire (défaut : celui de l'app, SPEC §3)")
    parser.add_argument("--vocabulary-file", help="fichier texte contenant le vocabulaire")
    parser.add_argument("--azure-region", default=None,
                        help="région Azure (défaut : AZURE_SPEECH_REGION, sinon eastus)")
    parser.add_argument("--repeat", type=int, default=1, help="nombre de passages par fichier (défaut : 1)")
    parser.add_argument("--timeout", type=float, default=TIMEOUT_SECONDS, help="délai par requête en s (défaut : 120)")
    parser.add_argument("--output-dir", default=script_dir,
                        help="dossier des rapports (défaut : le dossier du script)")
    parser.add_argument("--dry-run", action="store_true",
                        help="construit et affiche les requêtes sans les envoyer")
    args = parser.parse_args(argv)
    if args.repeat < 1:
        parser.error("--repeat doit valoir au moins 1")
    if args.vocabulary_file:
        args.vocabulary = read_text_file(args.vocabulary_file)
    elif args.vocabulary is None:
        args.vocabulary = DEFAULT_VOCABULARY
    args.azure_region = or_default(args.azure_region or os.environ.get("AZURE_SPEECH_REGION"),
                                   DEFAULT_AZURE_REGION)
    return args


def read_keys() -> Dict[str, str]:
    return {provider: (os.environ.get(env) or "").strip() for provider, env in KEY_ENV.items()}


def configure_console() -> None:
    """Évite les plantages d'encodage dans les consoles Windows anciennes."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, ValueError):
            pass


def main(argv: Optional[Sequence[str]] = None) -> int:
    configure_console()
    if sys.version_info < (3, 9):
        print("Python 3.9 ou plus récent est nécessaire.", file=sys.stderr)
        return 2
    args = parse_args(argv)
    keys = read_keys()
    samples = find_samples(args.samples)
    if not samples:
        print("Aucun enregistrement trouvé dans {0} (extensions : {1}).".format(
            args.samples, ", ".join(sorted(AUDIO_EXTENSIONS))), file=sys.stderr)
        return 1
    providers = resolve_providers(args.providers, keys, args.dry_run)
    configs = build_configs(args, providers)
    terms = vocabulary_terms(args.vocabulary)

    if args.dry_run:
        dry_run(samples, configs, keys, args.language, args.vocabulary, args.azure_region)
        return 0

    without_ref = [s.name for s in samples if s.reference is None]
    print("{0} enregistrement(s), {1} configuration(s), {2} passage(s) : {3} appel(s).".format(
        len(samples), len(configs), args.repeat, len(samples) * len(configs) * args.repeat))
    if without_ref:
        print("Sans .txt de référence (transcrits mais non notés) : " + ", ".join(without_ref))
    print("Les enregistrements sont envoyés à : " + ", ".join(PROVIDER_LABELS[p] for p in providers) + ".")
    print()

    results = run_benchmark(samples, configs, keys, args.language, args.vocabulary,
                            args.azure_region, args.repeat, args.timeout)
    summaries = [Summary(c, [r for r in results if r.config is c]) for c in configs]
    print_summary(summaries)

    os.makedirs(args.output_dir, exist_ok=True)
    stamp = _dt.datetime.now().strftime("%Y-%m-%d-%H%M")
    md_path = os.path.join(args.output_dir, "rapport-{0}.md".format(stamp))
    csv_path = os.path.join(args.output_dir, "rapport-{0}.csv".format(stamp))
    write_markdown_report(md_path, samples, configs, summaries, results, args, terms)
    write_csv(csv_path, results)
    print()
    print("Rapport détaillé : " + md_path)
    print("Tableau CSV      : " + csv_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
