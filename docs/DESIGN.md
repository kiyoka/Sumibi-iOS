# Sumibi-iOS Design

## 1. Purpose

Sumibi-iOS is an iOS custom keyboard that converts romaji or English text into natural Japanese with an LLM. It brings the modeless workflow of the Emacs version of Sumibi to iPhone and iPad.

## 2. Product principles

- Keep Japanese input modeless: users type with an English QWERTY layout and explicitly request conversion.
- Make conversion reversible: the original text must remain available for Undo.
- Minimize data sent to external services and explain network use clearly.
- Keep the keyboard responsive even while an LLM request is running.
- Separate keyboard UI, conversion logic, provider integration, and settings storage.

## 3. MVP scope

### Included

- English QWERTY keyboard layout
- Romaji and English input
- A dedicated Convert key
- LLM-based Japanese conversion
- A candidate bar for alternative results
- Undo to restore the original text
- OpenAI-compatible provider configuration
- API key and model configuration in the containing app
- Onboarding for enabling the keyboard and Allow Full Access
- Clear error states for missing full access, network failure, timeout, and invalid credentials

### Not included in the first release

- Flick keyboard layout
- Ambient conversion
- Local Mozc provisional conversion
- Japanese-to-English translation
- Cloud synchronization
- User dictionary
- Voice input

## 4. System architecture

### Containing app

Responsibilities:

- Onboarding and keyboard setup instructions
- Provider, endpoint, model, and API key configuration
- Privacy explanation and consent
- Conversion test screen
- Diagnostics that do not record typed text

### Keyboard extension

Responsibilities:

- Render QWERTY keys and candidate bar
- Track text inserted by the current keyboard session
- Determine the conversion target
- Start and cancel conversion requests
- Replace the source text with the selected result
- Restore the source text with Undo
- Show full-access and network error guidance

### SumibiCore

A shared Swift package or framework containing:

- Conversion request and response models
- Romaji input tracking
- Conversion-target selection
- Prompt construction
- OpenAI-compatible HTTP client
- Candidate parsing
- Retry, timeout, and cancellation policy
- Provider-independent error types

### Shared configuration

The containing app and keyboard extension use an App Group for non-secret settings. Secrets are stored using Keychain Sharing when supported by both targets.

Proposed identifiers:

- App bundle: org.sumibi.Sumibi-iOS
- Keyboard extension: org.sumibi.Sumibi-iOS.Keyboard
- App Group: group.org.sumibi.Sumibi-iOS

These identifiers are provisional until the Apple Developer account configuration is confirmed.

## 5. Conversion flow

1. The user types romaji or English with the Sumibi keyboard.
2. The extension records only text that it inserted during the current valid composition session.
3. The user taps Convert.
4. The extension captures the source text and limited surrounding context.
5. SumibiCore sends a conversion request to the configured provider.
6. The source text remains visible while a progress state is shown.
7. On success, the extension deletes the tracked source range and inserts the first candidate.
8. Alternative candidates appear in the candidate bar.
9. Undo restores the exact original source text.

The tracked composition is invalidated when cursor movement, external edits, keyboard switching, or inconsistent document context makes replacement unsafe.

## 6. Keyboard UI

Initial layout:

- Standard English QWERTY letter rows
- Shift, delete, numbers/symbols, globe, space, return
- A visually distinct Convert key
- Candidate bar above the key rows

Candidate bar states:

- Idle: short guidance or hidden
- Converting: progress indicator and Cancel
- Success: converted candidate, alternatives, and Original
- Error: concise message with Retry when appropriate

## 7. Network and privacy

The keyboard requires Allow Full Access because conversion uses a network service and shared configuration. The app must explain this before directing the user to Settings.

Privacy rules:

- Send text only after the user taps Convert.
- Send the smallest useful amount of surrounding context.
- Never persist keystrokes or conversion source text in logs.
- Never collect unrelated clipboard, contact, location, or identifier data.
- Do not retain conversion requests on a Sumibi-operated server.
- Redact API keys and input text from diagnostics.

Known platform limits:

- iOS replaces third-party keyboards in secure text fields.
- Some phone-number fields use the system keyboard.
- Host apps can disable third-party keyboards.
- Network and shared-container writes require Allow Full Access.

## 8. Error handling

- Full access disabled: show setup guidance without attempting a request.
- Missing configuration: direct the user to the containing app.
- Unauthorized response: report invalid API credentials.
- Rate limit: provide Retry and preserve the source text.
- Timeout or offline: preserve source text and allow Retry.
- Cancellation: return to the unmodified source text.
- Unsafe replacement state: show candidates without modifying host text.

## 9. Testing strategy

- Unit tests for target detection, prompt generation, parsing, and error mapping
- Mock URLProtocol tests for provider communication
- Keyboard state-machine tests
- UI tests in the containing app
- Manual tests across common host apps
- Device tests with and without Allow Full Access
- Privacy tests ensuring input and credentials never appear in logs

## 10. Milestones

1. Xcode project with app and keyboard-extension targets
2. App Group configuration and shared settings
3. Minimal QWERTY keyboard that inserts and deletes text
4. Composition tracking and Convert key
5. Mock conversion client and candidate bar
6. OpenAI-compatible API integration
7. Undo, cancellation, and error handling
8. Onboarding, privacy text, and device validation

## 11. Open decisions

- Minimum supported iOS version
- Final bundle and App Group identifiers
- First default provider and model
- Maximum surrounding-context size
- API-key sharing mechanism between app and extension
- Whether candidate requests should return multiple candidates in one response
- Licensing and App Store privacy disclosures

## 12. Conversion target and composition tracking

### MVP decision

The MVP converts only a composition that was inserted and is still owned by the
current Sumibi keyboard session. It does not infer an arbitrary editable range
from the host application's document.

This is intentionally narrower than the Emacs version. A keyboard extension can
read limited text around the cursor through the document proxy, but it does not
own the host document or a stable selection range. Restricting replacement to
tracked input avoids deleting unrelated text after cursor movement or host-side
editing.

### Tracked composition

`CompositionTracker` maintains:

- `source`: the exact text inserted by Sumibi since the last hard boundary
- `revision`: a monotonically increasing local edit revision
- `expectedSuffix`: a bounded suffix used to verify the cursor context
- `isReplaceable`: whether automatic replacement is still safe

The tracker appends ordinary printable input. Delete removes the last extended
grapheme cluster when the proxy context still matches. The tracker is cleared
after return, keyboard switching, an explicit reset, or successful conversion.

Space and punctuation are retained in the composition so that a phrase such as
`watashi ha kiyoka desu .` can be converted as one unit. Return is a hard
boundary. To prevent unbounded requests, the tracker keeps at most 512
characters for an MVP conversion target; older text may still be used as
read-only context.

### Safety validation

Before starting a request and again before replacing text, the keyboard checks
that the available `documentContextBeforeInput` ends with `expectedSuffix`.
The second check also requires the same local `revision` captured by the
request.

If either check fails:

- do not delete or replace host text;
- retain the returned candidates for manual inspection;
- show a short message that the text changed;
- allow the user to copy or dismiss the result;
- start a fresh composition with the next key input.

This rule covers cursor movement, edits made by the host app, Dictation, text
replacement, and continued typing while a request is in flight.

### Replacement

On a valid result:

1. Revalidate the tracked suffix and request revision.
2. Call `deleteBackward()` once per extended grapheme cluster in `source`.
3. Insert the selected candidate.
4. Store an `UndoRecord` containing the original, replacement, and a new
   expected suffix.
5. Clear the active composition.

Deletion is grapheme-based rather than UTF-16-length-based so that emoji and
combined characters do not cause an incorrect number of delete operations.

### Undo

Undo is available only while the cursor remains directly after the exact
replacement inserted by Sumibi. It performs the same suffix validation, deletes
the replacement by extended grapheme cluster, and reinserts the original source.
Any unrelated insertion, deletion, cursor movement, keyboard switch, or new
conversion invalidates the `UndoRecord`.

### Explicit non-goals for the MVP

- Converting an arbitrary selection created in the host application
- Reconstructing an entire document from proxy context
- Replacing text after validation fails
- Ambient conversion

## 13. Keyboard state machine

The UI and controller use one explicit state value. Network callbacks carry a
request ID and are ignored when they no longer match the active request.

### States

- `idle`: no tracked input
- `composing`: tracked input is valid and Convert is enabled
- `converting`: one request is active; source text remains unchanged
- `candidates`: conversion succeeded and alternatives are available
- `staleResult`: conversion succeeded but the source is no longer replaceable
- `error`: the request failed without modifying the source

### Transitions

| Current state | Event | Next state | Effect |
| --- | --- | --- | --- |
| `idle` | printable key | `composing` | Insert and begin tracking |
| `composing` | printable key or delete | `composing` | Insert/delete and increment revision |
| `composing` | Convert | `converting` | Validate, snapshot, and start request |
| `converting` | Cancel | `composing` | Cancel request; preserve source |
| `converting` | key input | `composing` | Cancel or supersede request; preserve responsiveness |
| `converting` | valid response | `candidates` | Replace with first candidate and create Undo record |
| `converting` | response after edit mismatch | `staleResult` | Never modify host text |
| `converting` | failure | `error` | Preserve source and offer Retry |
| `error` | Retry | `converting` | Revalidate and issue a new request |
| `candidates` | alternative selected | `candidates` | Safely replace the current Sumibi result |
| `candidates` | Original/Undo | `composing` | Restore the exact source |
| any | context validation failure | `idle` or `staleResult` | Invalidate automatic replacement |

### Concurrency rules

- At most one request controls automatic replacement.
- Starting a new request cancels the previous task and changes the request ID.
- Cancellation is cooperative; a late response is ignored.
- Main-actor state changes are serialized.
- Source text is never removed merely to show a progress state.
- Retry creates a new request ID and rechecks document context.

### Candidate behavior

The first valid response is inserted immediately to preserve the modeless Sumibi
workflow. The candidate bar then shows alternatives and `Original`. Selecting
another candidate is allowed only while the current inserted result still
matches the expected suffix. Otherwise the state becomes `staleResult` and no
replacement occurs.

For the initial API contract, one request should return up to three ordered
candidates. If a provider returns only one result, the candidate bar still
offers `Original`.
