![version](https://img.shields.io/badge/version-17%2B-3E8B93)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm%20|%20win-64&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-native-encoding-detection)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-native-encoding-detection/total)

# 4d-plugin-native-encoding-detection

Detects the character encoding of a BLOB of text by handing it to the host OS's own encoding-detection engine — `IMultiLanguage2::DetectInputCodepage` (MLang) on Windows, `TECSniffTextEncoding` (Text Encoding Converter) on macOS — and returns the candidate encodings as a 4D `Object`, ranked from most to least likely.

| Command | Returns | Purpose |
|---|---|---|
| [`NED Detect encoding`](#ned-detect-encoding) | `Object` | Detect the likely character encoding(s) of a BLOB of text. |

**Platforms:** macOS (Intel & Apple Silicon), Windows 64-bit — 4D v17+ (for v17, move `manifest.json` into the plugin's `Contents` folder manually; from v18 this is automatic).

---

## Requirements & platform notes

- The plugin exposes exactly one command, `NED Detect encoding` — confirmed from the `switch(selector)` dispatch in `PluginMain`; the only other selector cases (`kInitPlugin`/`kServerInitPlugin`) are internal setup, not callable commands.
- `NED Detect encoding` is declared **thread-safe** in the plugin's manifest, so 4D may call it from preemptive/worker processes as well as the main process.
- The input BLOB is capped at **256 MB**. A larger BLOB is rejected outright (see [Error handling](#error-handling--troubleshooting)) rather than processed — pass a representative sample of a large file rather than the whole thing.
- The optional `params` object's `sourceTextType` and `preferredCodePage` properties **only affect Windows** — they're read but have no effect on the macOS code path.
- **On Windows**, each call creates its own `IMultiLanguage2` COM instance, which requires COM to already be initialized on the calling thread. If it isn't, the call silently succeeds with an empty `encodings` collection rather than failing loudly — see [Error handling](#error-handling--troubleshooting).
- Whether a minimum macOS/Windows version is required beyond "the OS component is present" isn't something the source establishes — `TECSniffTextEncoding` and `IMultiLanguage2` are long-standing OS facilities with no version-gated feature usage visible in this plugin's code, so no specific floor is asserted here beyond the v17+ 4D requirement above.

---

## Manual version and release workflows

**Bump version** and **Build** are independent manual Actions workflows. Select
the source branch in the Actions UI. Bump version offers only `patch`, `minor`,
and `major`; it commits source metadata to that branch without creating a tag,
release, or Build run. Build has **zero inputs** (no tag input), derives
`vX.Y.Z` from the selected source, and publishes only a new tag and release.
Neither workflow runs on a push. Every checkout uses the immutable dispatch
`${{ github.sha }}`, not a moving branch or tag. No new branch restriction is
introduced; Bump requires the selected ref to be a branch.

The source version must be one strict `X.Y.Z` across all six
`MARKETING_VERSION` and six `CURRENT_PROJECT_VERSION` assignments in
`Native Encoding Detection.xcodeproj/project.pbxproj`, `Info.plist`, and the two
version displays in `English.lproj/InfoPlist.strings`. Supported Xcode references
are preserved, as is an absent optional `CFBundleVersion`; unknown/cyclic
references, inconsistent values, duplicate keys (including quoted localized
keys), and unsupported serialization fail before a bump writes anything.
Rewrites preserve BOMs, each line ending (including CR-only/mixed files), modes,
whitespace, copyright, and unrelated bytes. Prebuilt bundles/archives,
dependencies, Windows project metadata, manifests, schema versions, and 4D
data/catalog/localization counters are not version inputs.

### Version authority and intake repair

The original workflow is evidence for coordination, not independent build
numbering:

| Evidence | Meaning |
| --- | --- |
| `2a22674`, `mv` | Earlier header chose marketing first and current only as fallback. Rename-follow history traces the source plist and English strings to their original nested paths. |
| `d04bbca`, `Rework CI workflows and sync version fields` | Later header explicitly promises to write both `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` and both plist version keys. The commit synchronized the project/plist to `1.0.8`; this explicit coordinated contract supersedes the earlier fallback wording. |
| `e5b7e1b`, `6a88518` | The buggy marketing-first body subsequently advanced only marketing and the source plist to `1.0.10`, leaving all six current/build fields at `1.0.8`. |
| Source resource wiring | The Xcode Resources phase copies `English.lproj/InfoPlist.strings`, still displaying `1.0.0`, into the built bundle. `Info.plist` is the configured source plist. |

This migration repairs only those six current/build fields and the two
localized displays to the **existing `1.0.10`**, without incrementing intake,
adding an absent `CFBundleVersion`, rewriting the plist, changing the CR-only
localization/copyright, or modifying prebuilt metadata. Build never repairs
drift automatically.

The remote already has `v1.0.10`. Intake intentionally does not create a new
release version: a maintainer must run Bump version before a future Build can
publish a fresh version; building the intake version stops at availability.

The implementation adapts the full helpers/tests from
[`4d-plugin-arguments` at `38a45cd`](https://github.com/miyako/4d-plugin-arguments/tree/38a45cd0e30dc015ed430e8dd3c95c5c31f4a1fc)
and compares the coordinated
[`process` at `ec2611e`](https://github.com/miyako/4d-plugin-process/tree/ec2611e6bbe97e87982cb84bb603462d0458612c)
with the independent-build contracts in
[`common-string-algorithm` at `2606a68`](https://github.com/miyako/4d-plugin-common-string-algorithm/tree/2606a68201866ec9fcbb38b51462d79215f504ef)
and corrected
[`window-button` at `3f14fac`](https://github.com/miyako/4d-plugin-window-button/tree/3f14facb9aaaaff0e22eeb8e07531163680c3a8a).
Independent build policy is not imported into this coordinated project.

### Publication safety and manual recovery

Bump requires a clean checkout, the exact selected remote branch SHA, and a
source-only, single-parent direct-child commit with the Copilot coauthor trailer.
An executable pre-push guard is mandatory both before editing and immediately
before pushing. It checks Git's advertised old SHA, literal new SHA/HEAD, target
branch, parentage, and exactly one update, rejecting advance/rewind/deletion and
same-result races. Pushes are nonforce with both `push.followTags=false` and
`--no-follow-tags`.

Build retains Windows x64/MSBuild v143/Windows SDK 10.0 and macOS universal
arm64+x86_64/Xcode Default, the deployment override, dependencies, resources,
`windows-binaries` artifact, all six signing/notary secret names, and ZIP/DMG
asset names (`Native Encoding Detection-X.Y.Z.zip` and `.dmg`). It invalidates
only stale native products, requires exact output paths and source-matching
bundle metadata, verifies both architectures and the signature, requires
`Accepted` for **both** notarizations, then staples the DMG. No native build,
signing, notarization, or 4D execution is part of the local test suite.

All branches share the constant `release-publication` concurrency group with
cancellation disabled. Before native work, and again **after every native,
signing, notarization, and staple gate**, publication checks the exact remote tag
and authenticated, paginated releases (including drafts). Every page/entry must
be valid; 404/auth/network/malformed/later-page failures are errors, never
absence. An atomic create-only `POST git/refs` pins the tag to the selected SHA;
remote verification precedes a separate `POST releases` with explicit public,
nonprerelease fields and the original empty release body (no generated notes).
Assets are POSTed only to the newly returned release ID.

Existing tags/releases are never reused, updated, deleted, or clobbered. There
is no automatic rollback or retry, including when a response is ambiguous:
**partial tags, public releases, and successful earlier uploads remain**.
On failure, inspect the run's selected SHA/tag and remote tag, draft/public
release, and asset state before any further action. A maintainer must decide
whether to finish recovery manually or bump the source to a fresh version.
Do not blindly rerun publication; an existing tag or release deliberately
blocks it. A branch race likewise requires a fresh Bump dispatch after review,
not a forced push.

### Local workflow checks

Run `actionlint .github/workflows/*.yml` and
`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/tests -v`.
PowerShell (`pwsh`) enables the Windows shell harness. Tests derive live fixture
versions and also use stable fixtures, disposable local bare Git remotes,
mocked authenticated API responses, and a closed-PATH native-tool stub harness.
They cover advertised-SHA races, initial/late hook loss, merge commits,
source-only commits, page-two/API failures, retained partial publication,
byte/mode/endings/reference/duplicate-key handling, exclusions, exact native
outputs, architectures, signing, notarization, and stapling. No test dispatches
Actions or publishes to GitHub.

## NED Detect encoding

### Syntax

```4d
status := NED Detect encoding( data ; params )
```

| Parameter | Type | Description |
|---|---|---|
| `data` | BLOB | The source text to analyze. Read via `PA_GetBlobParameter` — mandatory; if the BLOB is empty (length 0) or exceeds 256 MB, `encodings` in the result is empty and `error` is set (larger-than-256MB case only). |
| `params` | Object | Optional. Detection hints — see the table below. Read via `PA_GetObjectParameter`; if omitted, the command runs with default detection behavior. **Ignored entirely on macOS.** |
| Result | Object | The detection results — see the table below. |

`params` properties (Windows only — no effect on macOS):

| Property | Type | Description |
|---|---|---|
| `sourceTextType` | Text | One of `"7bit"`, `"8bit"`, `"dbcs"`, `"html"`. Maps to MLang's `MLDETECTCP_7BIT` / `MLDETECTCP_8BIT` / `MLDETECTCP_DBCS` / `MLDETECTCP_HTML` flags, telling the Windows detector what kind of byte stream to expect. Any other value is silently ignored and detection proceeds with no flag set. |
| `preferredCodePage` | Number | A Windows code page number passed to MLang as a bias when several encodings are equally plausible. |

Result object properties:

| Property | Type | Description |
|---|---|---|
| `encodings` | Collection | Zero or more candidate-encoding objects (fields below), ordered from most to least likely. Always present, possibly empty. |
| `error` | Text | Present only when detection could not run at all — see [Error handling](#error-handling--troubleshooting). Absent on a normal call, including one that legitimately finds zero candidates. |

Each entry in `encodings`:

| Property | Type | Platform | Description |
|---|---|---|---|
| `code` | Number | Both | Numeric code page. On macOS this is the *Windows-equivalent* code page for the detected encoding, and is `-1` when there is none (`kCFStringEncodingInvalidId`). |
| `charset` | Text | Both | IANA charset name (e.g. `shift_jis`, `windows-1252`, `utf-8`). On macOS this can be absent from the object entirely if `CFStringConvertEncodingToIANACharSetName` returns no name for that encoding. |
| `name` | Text | Both | Human-readable/platform-specific encoding name. On macOS this can likewise be absent if `CFStringGetNameOfEncoding` returns no name. |
| `language` | Number | Both | Platform-specific language identifier. `-1` on Windows when no specific language applies. |
| `script` | Number | macOS only | The Mac script code associated with the encoding. Not present on Windows. |
| `percentage` | Number | Windows only | MLang's estimated percentage of the document matching this encoding. Not present on macOS. |
| `confidence` | Number | Windows only | MLang's confidence score for this candidate. Not present on macOS. |
| `fixedWidthFont` | Text | Windows only | Suggested fixed-width font for displaying text in this encoding. |
| `proportionalFont` | Text | Windows only | Suggested proportional font for displaying text in this encoding. |

### Description

The command copies the BLOB into memory once, then hands it to the OS's native encoding sniffer and translates whatever that sniffer reports into a 4D object per candidate.

**On Windows**, `count_windows_encodings` (the number of installed code pages, counted once at plugin init) sets the maximum number of candidates MLang can return; the loop then keeps every candidate MLang reports with a non-zero language ID, in the order MLang returns them (`percentage`/`confidence` reflect MLang's own ranking — the plugin doesn't re-sort).

**On macOS**, the sniffer is asked about every text encoding the OS makes available, and the results loop **stops at the first candidate that has any conversion errors** (`numErrsArray[i]` non-zero) — so a mid-list encoding with a single flagged error ends the list there, even if later, lower-probability encodings in the array would otherwise have matched cleanly. This is a deliberate reading of the source's `break` on first error, not a bug to route around when calling this command — just be aware `encodings` on macOS is "best consecutive run," not "every clean match in the array."

If the BLOB is larger than 256 MB, or an internal error occurs while processing it (e.g. the allocation itself fails), the command does **not** raise a 4D error — it returns `encodings: []` plus an `error` text property explaining why (see [Error handling](#error-handling--troubleshooting)).

### Example

From the plugin's own test method (`TEST.4dm`):

```4d
$params:=New object
CONVERT FROM TEXT("〠ゆうびん";"x-mac-japanese";$source)
$status:=NED Detect encoding($source;$params)
```

Reading the best guess and falling back to a default:

```4d
$status:=NED Detect encoding($fileBlob)
If($status.encodings.length>0)
	$charset:=$status.encodings[0].charset
Else
	$charset:="utf-8"
End if
```

Giving Windows a hint (harmless no-op on macOS, since `params` is ignored there):

```4d
$params:=New object
$params.sourceTextType:="html"
$params.preferredCodePage:=1252
$status:=NED Detect encoding($htmlBlob;$params)
```

---

## Error handling & troubleshooting

- **An empty `encodings` collection is not itself an error.** It means the OS detector found no plausible candidate for these bytes — always check `.length` before indexing `.encodings[0]`.
- **`status.error` only appears when detection couldn't run at all.** Confirmed values from the source: `"blob exceeds maximum supported size"` (BLOB over 256 MB — pass a smaller sample instead of the whole file), `"allocation failed"` (the BLOB copy couldn't be allocated), and `"unexpected error during encoding detection"` (any other internal exception). A normal call that just found zero candidates will have `encodings: []` and no `error` property at all — check for the property's presence/type, don't assume its absence means success.
- **On Windows, a COM initialization failure on the calling thread fails silently.** Because the command is thread-safe and creates its own `IMultiLanguage2` instance per call, if COM isn't initialized on whatever thread 4D uses to run it, `CoCreateInstance` fails, and the command returns an empty `encodings` collection with no `error` set — there's no distinguishing this from "the detector legitimately found nothing" from the result object alone.
- **`params` has no effect on macOS.** Setting `sourceTextType`/`preferredCodePage` and seeing no behavior change on Mac is expected, not a bug — those properties only reach MLang's Windows call.
- **On macOS, a real match past an early bad candidate won't show up.** If you expected a specific encoding to appear in `encodings` and it's missing, check whether an earlier-ordered encoding in the OS's own list could have produced a conversion error on your sample — the loop stops there rather than skipping past it.

---

## Quick reference

```4d
$params:=New object
$params.sourceTextType:="html"      //Windows only; harmless elsewhere
$params.preferredCodePage:=1252     //Windows only; harmless elsewhere

$status:=NED Detect encoding($blob;$params)

If(Value type($status.error)=Is text)
	$charset:="utf-8"  //detection didn't run; fall back
Else if($status.encodings.length>0)
	$charset:=$status.encodings[0].charset
Else
	$charset:="utf-8"  //ran, found nothing
End if

CONVERT FROM TEXT($blob;$charset;$text)
```
