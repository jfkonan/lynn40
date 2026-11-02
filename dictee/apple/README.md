# Dictée

Un clavier iPhone qui transcrit votre voix avec **votre propre clé API OpenAI**, sur le principe de Wispr Flow.

## Comment ça marche

iOS interdit aux claviers d'utiliser le micro. Dictée est donc composée de deux éléments :
- **l'app Dictée**, qui écoute, envoie l'audio à OpenAI et garde votre clé ;
- **le clavier Dictée**, qui affiche un gros bouton micro et insère le texte.

Le principe est celui de Wispr Flow : vous démarrez une « session » une fois, puis vous dictez dans n'importe quelle app sans la quitter.

## Utilisation

1. **Première fois** : ouvrez l'app Dictée et collez votre clé OpenAI (`sk-…`).
2. **Installez le clavier** : Réglages > Général > Clavier > Claviers > Ajouter > Dictée, puis activez « Autoriser l'accès complet ». Cet accès sert à communiquer avec l'app ; le clavier n'envoie rien lui-même sur Internet.
3. **Pour dicter** :
   - Passez au clavier Dictée avec le globe 🌐 et touchez le micro.
   - Si aucune session n'est active, l'app s'ouvre. Revenez à votre app avec « ‹ » en haut à gauche.
   - Touchez le micro, parlez, puis retouchez-le : le texte s'insère au curseur.
4. La session s'arrête seule après 10 minutes sans dictée. Ce délai est réglable.

## Réglages

| Réglage | Par défaut | Rôle |
|---|---|---|
| Modèle | `gpt-4o-transcribe` | `gpt-4o-mini-transcribe` coûte moitié moins cher |
| Langue | `fr` | Code ISO de la langue parlée |
| Vocabulaire | sigles OHADA, termes de droit des sociétés | Aide le modèle à bien orthographier vos termes |
| Nettoyer le texte | désactivé | Ponctue et retire les « euh » sans reformuler (second appel, `gpt-4o-mini`) |

## Confidentialité

- Votre clé API reste dans le Trousseau de l'iPhone.
- L'audio est envoyé uniquement à OpenAI, avec votre clé. Il est supprimé du téléphone juste après la transcription.
- Pendant une session, iOS affiche le point orange du micro.

## Compiler le projet

Voir [HANDOFF.md](HANDOFF.md). Il faut un Mac, Xcode et XcodeGen.
