# Native string ownership audit

## Immutable evidence and scope

Baseline: `b920a201584d53ab568a648c413aaf794348d5d0` (default branch).
Guidance: `miyako/skills`, revision
`e6b492fcb81e5e1a7f7db723594b420e63bf6eb9`,
`4d-skills/skills/4dplugin/SKILL.md`.
Issue: #2. This is an ownership audit, not a general security review.

The complete bundled SDK is compiled unchanged by the harness. Its own banner
says `rev : v14`; this is not independently verified upstream version metadata.
Git blob IDs at the baseline:

| SDK file under `4D Plugin API/` | Git blob |
|---|---|
| `4DPluginAPI.c` | `62f745e91d81ef2c3c901c656ea8e175d3b173e8` |
| `4DPluginAPI.h` | `528bf1d2552df08d6a8b1bc95011a9b72934ad5c` |
| `PublicTypes.h` | `9ae20b001bff9128f690fff3e6c3f873b6238333` |
| `PrivateTypes.h` | `a3098cb662cdbc43ba574fdef72a059c4c6d1cd4` |
| `EntryPoints.h` | `da428d5f6ca23b0a30371c7288a01d29aa3c466a` |
| `Flags.h` | `7a5a35539f27430a3fd9cb711d6b789051316471` |
| `4DPluginAPI.def` | `5bbdb82fb724b6f8e307feb01d9f158b802de89d` |

Production changes are confined to `support/4DPlugin-JSON.cpp` (baseline blob
`74c880fb70dccb2d707fc8372880ff5c3492de41`).
SDK files, ABI headers, manifests, project files, vendored libraries and shipped
binaries retain their baseline bytes and modes. The source's existing mixed
CRLF/LF layout is preserved. No release metadata changes are needed.

## Complete native inventory and reachability

The root manifest and shipped bundle manifest declare only
`NED Detect encoding(&O;&J):J`, selector 1: BLOB, object, object result.
Neither declares text arrays. This was not used to exclude scalar or internal
helpers. `PluginMain` dispatches initialization/server initialization and selector
1; no callback method or deferred string callback is present.

Both `Native Encoding Detection.vcxproj` and the Xcode Sources phase compile
exactly `4DPlugin-Native-Encoding-Detection.cpp`, `support/4DPlugin-JSON.cpp`
and `4D Plugin API/4DPluginAPI.c`. Windows exports `FourDPackex` via the `.def`;
the SDK entry point delegates to `PluginMain`. Xcode sets private extern
symbols. Helpers not called by the dispatcher are still compiled, not excluded
on the basis of export or command-manifest reachability.

| Tracked native surface | Ownership inventory |
|---|---|
| `4DPlugin-Native-Encoding-Detection.cpp/.h` | Entire dispatcher and platform branches read. `collection_push` places an independently created object into a temporary object variable, sets the collection element, then clears the temporary. Result collection/object setters and `PA_ReturnObject` retain the existing owning handoffs. Windows options use `ob_get_a/n`; Windows metadata uses wide text setters; macOS metadata and error reporting use UTF-8 setters. Input options are borrowed. No direct text-array calls. |
| `support/4DPlugin-JSON.cpp/.h` | Entire implementation/declarations read, including unused overloads: `json_wconv`; picture setter; both UTF-8 setters; both UTF-16/wchar setters; both object setters; collection setter; both real setters; integer/boolean setters; both null setters; existence check; text/boolean/real/collection getters; stringify. Fixed four string initial-owner overwrites and one picture initial-owner overwrite. Fixed successful getter cleanup, owning mismatches, and failure-output adoption; matching collection getter still transfers its owning output. Stringify saves the command error before argument cleanup; failed raw outputs are neither normalized nor cleared. Successful wrong-type outputs are cleared and errors are explicitly thrown, not silently converted to empty output. |
| `Classes/ARRAY_TEXT.cpp/.h` | Entire dormant implementation read. Borrowed parameter strings are copied to `CUTF16String` before mutation. Array output creates a distinct owner per element, including index zero, and does not dispose accepted assignments. Replacement, shrink, clear, UTF conversions and Objective-C conversion/path methods inspected. No unconditional disposal-removal fix is appropriate. Allocation/resize failure limitation below. |
| `Classes/C_TEXT.cpp/.h` | Entire dormant implementation read. Borrowed input copied by explicit UTF-16 length. Parameter and return paths call the content setter, not scalar shallow assignment. UTF conversions, Objective-C path/string copies/releases and replacement helper inspected. Copy construction/assignment already disabled. |
| `Classes/C_BLOB.cpp/.h` | Entire dormant `CBytes` and `C_BLOB` implementations read. BLOB handles, byte vectors, hex/base64 conversions pass independently owned text through `C_TEXT`; no `PA_Unistring` owner transfer. Handle-allocation failure limitation below. |
| `Classes/C_LONGINT.cpp/.h`, `Classes/C_TYPES.h` | Entire scalar implementation and shared types read. No SDK string owners or callbacks. |
| `4D Plugin API/4DPluginAPI.c/.h`, `PublicTypes.h`, `PrivateTypes.h`, `EntryPoints.h`, `Flags.h` | Exact bundled implementations, forwarding fields, error storage, variable/string kinds and ABI layouts used, not a substitute SDK. Relevant contracts below; SDK internals left unchanged. |
| `include/json/{allocator,assertions,autolink,config,features,forwards,json,reader,value,version,writer}.h` | Vendored JsonCpp declarations/templates and ordinary C++ allocation boundary; no 4D ownership calls/types. Neither actual plugin source nor helper includes JsonCpp. Static archives `a/libjsoncpp.a`, `lib/windows/jsoncpp.lib`, `lib/windows64/jsoncpp.lib` are not modified or treated as inspected native source. |

There are no other tracked C/C++/Objective-C implementation files, no `CPicture`
class, no file-to-picture command wrapper, and no plugin
`PA_ConvertCharsetToCharset` caller. The full SDK contains its own general-purpose
scalar/array/object/collection/method helpers, which are not rewritten.

## Exact bundled contracts

Line references here refer to the immutable baseline `4DPluginAPI.c`.

| Contract | Evidence and consequence |
|---|---|
| String creation/disposal/content update | Lines 265-299 forward to `EX_CREATE_UNISTRING`, `EX_DISPOSE_UNISTRING`, `EX_SET_UNISTRING`; disposal resets the caller descriptor. Content update is distinct from assigning an owning descriptor. Allocation/engine failure outputs are not promised usable. |
| Initial owners | `PA_CreateVariable`, lines 3920-4077, creates an empty owned string for `eVK_Unistring` (4030), and a picture for `eVK_Picture`. Undefined has no allocated payload. |
| Scalar shallow setters | Lines 4254-4259 directly assign the string struct; picture/object/collection setters likewise assign their references. They do not clear a preexisting owner. Initialize temporary overwritten values as Undefined, then keep the existing single `PA_ClearVariable` cleanup. |
| Property/collection getters | Lines 587-602 and 636-653 explicitly say the returned variable should be cleared after use. Engine fills a local variable through `fPtr2`; that local is not initialized before the call. Check the immediately saved error before inspecting or adopting a failure result. On success, cleanup also applies to a type mismatch. A matching collection reference is handed to the caller as the existing owning result, not cleared behind the caller's back. |
| Property/collection setters | Lines 604-616 and 656-669 forward the variable through `EX_SET_OBJ_VALUE`. Existing helpers clear the temporary afterward; the harness models property/collection storage as an independent copy/retained reference. This engine boundary is a model of intended host behavior, not actual 4D execution. |
| Borrowed array getter | Lines 4738-4755 return a shallow descriptor alias, expressly read-only. Wrapper copies before mutation. |
| Conditional array transfer | Lines 4933-4947 require exactly Unicode-array kind, non-null `fData`, `0 <= index <= fNbElements`, non-null descriptor pointer. Accepted assignment disposes the old element then shallow-assigns the incoming descriptor. Rejections do not consume it. Index zero is accepted. No shared source allocation or post-transfer disposal is introduced. |
| Command failures | Lines 5778-5815 start with a zeroed raw returned struct. Undefined initialization occurs only after command-handle allocation succeeds. Handle failure can therefore leave raw kind zero, which `UnifyVarKind` normalizes as string. Save/check `PA_GetLastError` before argument cleanup (which overwrites the error); never read/clear unspecified failure output. |
| Return paths | `PA_ReturnString` (2600-2603) uses `PA_SetUnistring`, forwarding content; `PA_ReturnObject` (2641-2644) directly hands off the object. These are not array-setter semantics. The harness asserts independent scalar content under the modeled engine content-setter contract and preserves the actual object handoff. |
| Conversion units | `PA_ConvertCharsetToCharset` (5296-5314) explicitly returns bytes, not UTF-16 units. No plugin caller exists here, so no unrelated divide-by-size patch is made. |

`ob_get_a` still returns whether a property exists, even for an incompatible
successful value; boolean/real getters preserve existing mismatch defaults.
Only actual failures now throw `std::runtime_error`. The existing detection
command's exception handler returns its explicit error property. Unused helper
callers receive the exception rather than an empty success.

## Reproducible unsigned regression

Run `PYTHONDONTWRITEBYTECODE=1 python3 .github/tests/test_ownership.py`.
The runner compiles the entire actual SDK, all four dormant Classes `.cpp`
files, actual JSON helpers, and the actual dispatcher included in the host
translation unit. Platform sniffing/name/charset entry points are redirected
before the dispatcher is compiled: initialization yields zero encodings,
and any unexpected platform operation is fatal. All engine selectors are
allowlisted synthetic operations. No actual 4D installation, file access,
networking, COM activation, encoding sniffing or user BLOB is used. CoreFoundation
text conversion processes only synthetic strings.

ASan and UBSan are enabled; alignment instrumentation is disabled for the SDK's
packed ABI. LeakSanitizer is disabled on macOS, so explicit string allocation,
picture reference, object/collection reference and handle counters must each
return to zero. Read checks assert exact UTF-16 lengths, allocation capacities,
contents and terminators; output checks assert exact UTF-8 bytes.

The final identical harness was run against a `git archive` of the immutable
baseline using `OWNERSHIP_SOURCE_ROOT`, then against the fixed actual sources.
Both compile the complete same SDK blob. The matrix has 31 scenarios times
ASCII/BMP/supplementary/empty text times allocated/null-empty engines:
**248 subcases**. Baseline: **168 fail, 80 pass**. Fixed: **248 pass**.

| Differential | Baseline failure count | Fixed |
|---|---:|---|
| Four string setter overloads | 16 | Pass; empty allocation no longer overwritten |
| Picture setter | 8 | Pass; initial picture no longer overwritten |
| Text getter and string mismatches in boolean/real/collection getters | 28 | Pass; owning output cleared (the null-empty baseline controls do not allocate) |
| Collection/object mismatches in text/boolean/real getters | 24 | Pass; acquired references released |
| Picture mismatches in text/boolean/real getters and object mismatch in collection getter | 32 | Pass; acquired references released |
| Four poisoned property-getter failure paths | 32 | Pass; errors surfaced before adoption; baseline UBSan invalid-kind normalization |
| Poisoned stringify command failure | 8 | Pass; baseline UBSan invalid-kind normalization |
| Stringify command-handle allocation failure | 8 | Pass; baseline attempts to read raw-kind-zero sentinel as string |
| Successful stringify wrong-type output | 8 | Pass; owning mismatch cleared and explicit exception, not silent success |
| Actual dispatcher empty/nonempty zero-encoding/oversize branches | 4 | Pass; oversize error-string setter no longer leaks allocated empty owner |

Unchanged controls: normal array accepted transfer, borrowed copy, replacement,
distinct element ownership, shrink/clear and rejected kind/data/index/null
descriptor; scalar borrowed copy and both wrapper/SDK scalar returns; matching
boolean/real getters; missing properties; matching object/collection setter and
owning collection getter handoffs; successful stringify. Ordinary null-empty
setter cases also passed the baseline. A null empty representation cannot
demonstrate a leaked allocated empty owner.

The new path-scoped `Ownership regression` workflow performs only this unsigned
test on push and pull request. Existing `Bump version` and `Build` workflows are
manual-only. No branch protection or rulesets were configured at audit time;
the new check is nevertheless required to pass operationally before merge.

## Explicit deferrals and safety limits

This is not Windows, actual 4D, or production crash certification. Windows COM
branches and their real engine/platform contracts were read but not executed.
macOS sniffing is denied in the harness, not exercised. Real host retention,
initial engine allocation/OOM, conversion failures and SDK-only metadata are
not certified from synthetic successful executions.

Dormant `ARRAY_TEXT` does not check initial array/string allocations or resize
success. The SDK's `PA_ResizeArray` can write the requested element count even
when handle resizing fails, and can dispose tail elements before a failed
shrink. Thus neither the reported count nor a naive clear/rollback is a safe
preservation contract. No speculative SDK/wrapper OOM patch is included; the
normal transfer/rejection controls do not certify these failure paths.
`CBytes::toParamAtIndex` disposes the old BLOB handle before allocating its
replacement and only assigns the new handle on success; allocation failure
can leave the old alias. It is dormant and outside string ownership; safe
failure-preserving BLOB redesign is deferred, not described as fixed.
The plugin's existing broad exception boundary, generic SDK factory failures,
and dormant wrapper C++ copy semantics are not general-audit targets here.

No project build was run. Xcode's Deployment shell phase removes signatures,
signs, packages and submits notarization; the shared scheme uses Deployment
for launch/profile/archive. Release workflows also publish artifacts. No
signing, packaging, releases, tags, manual dispatches, binary updates or real
platform/data operations are needed for this audit.

Prior art consulted without another checkout:
`miyako/4d-plugin-jpegoptim` at
`e49adcd32bd5500cf3de680faa3649b32463ff5e`,
`.github/tests/ownership_host.mm` and `test_ownership.py`.
The host here is adapted to this SDK and dispatcher, not a copied picture-only
or success-shaped mock. Immutable baseline/fixed logs and the full tracked
mode/blob inventory are retained as session artifacts.
