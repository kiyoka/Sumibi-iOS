# App Store Product Page Metadata (English — United States)

Metadata draft for the Sumibi 1.2.0 release. The app UI is currently in Japanese.

## App Information

### App Name

29 characters (30 maximum).

```text
Sumibi - AI Japanese Keyboard
```

### Subtitle

26 characters (30 maximum).

```text
Romaji to Natural Japanese
```

## Version Information

### Promotional Text

```text
Type Japanese from one QWERTY keyboard without switching layouts. Bring your own OpenAI-compatible API settings to turn romaji into natural Japanese.
```

### Description

```text
Sumibi is a custom iPhone keyboard that uses AI to convert sentences typed in romaji into natural Japanese.

Type with a single English QWERTY layout and tap Convert. You can enter Japanese without switching to a kana keyboard, while ordinary English typing remains available on the same keyboard.

KEY FEATURES
• Convert romaji sentences into natural Japanese
• Use one QWERTY layout without switching to a kana keyboard
• Convert only a selected range while leaving surrounding text unchanged
• Request additional candidates, including different kanji and expressions with the same reading
• Restore the original text with Undo
• Register preferred product names and proper nouns in a user dictionary
• Save up to three writing-style presets for language, tone, punctuation, or formatting
• Compare results with and without a writing-style prompt before saving it
• Review conversion counts, token usage, and estimated API cost by model
• Enter numbers and symbols without leaving the Sumibi keyboard
• Configure haptic feedback and key-click sounds

REQUIREMENTS
AI conversion requires an OpenAI-compatible API endpoint, model name, and API key supplied by the user. API charges and terms are determined by the selected API provider and are not included with the Sumibi download.

To use network conversion, add Sumibi in iOS keyboard settings and enable Allow Full Access. Without Full Access, ordinary QWERTY typing, delete, space, return, symbols, and keyboard switching remain available, but AI conversion is disabled.

PRIVACY
AI conversion occurs only after the user reviews the destination and explicitly consents to sending data to the selected third-party AI service. When Convert is tapped, the selected text, the minimum surrounding context needed for conversion, the registered user dictionary, and the active writing-style prompt are sent to the displayed API endpoint.

Data does not pass through a server operated by the Sumibi developer. Sumibi does not store keystrokes, source text, the user dictionary, or API keys on a developer-operated server. The API key is stored in the device Keychain and is not synchronized through iCloud. Processing and retention by the destination service are governed by the selected API provider's terms.

The app's settings interface and help text are currently in Japanese.

Sumibi is open-source software.
```

### Keywords

```text
romaji,IME,typing,conversion,QWERTY,kanji,kana,writing,input,language
```

### What's New in Version 1.2.0

```text
• Added writing-style presets for output language, tone, punctuation, and formatting
• Added an in-app comparison of results with and without a writing-style prompt
• Added Ember Glass effects to conversion controls on iOS 26 and later
• Improved key, candidate-selection, and conversion-state animations
• Refined delete-key repeat timing and key-press responsiveness
• Improved usability and stability
```

## URLs

| Field | URL |
| --- | --- |
| Support URL | https://kiyoka.github.io/Sumibi-iOS/support.html |
| Privacy Policy URL | https://kiyoka.github.io/Sumibi-iOS/privacy.html |
| Marketing URL | https://kiyoka.github.io/Sumibi-iOS/ |

## Registration Notes

- Add the `English (U.S.)` localization in App Store Connect.
- Clearly state that the app interface is currently in Japanese.
- Do not include review credentials, API keys, or personal information on the product page.
- Verify all field lengths in App Store Connect before saving.
- Use screenshots that show the app and keyboard actually in use. Decide whether Japanese screenshots are sufficient or localized captions are needed for the U.S. storefront.
