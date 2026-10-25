# Warden reversal guide

This is the curated, reproducible guide for reversing the captured WoW/Warden client. It is intentionally separate from `reversing-warden.md`, which remains the chronological research journal and evidence archive. Findings below are specific to the captured Retail build 69933 unless stated otherwise.

## 0. Campaign status (paused 2026-10-03)

The dispatcher/selector capture campaign is PAUSED. Everything learned is in
§12; the remaining path is the NPT/EPT hypervisor plan in §12.11. Why we
paused, in one paragraph:

The `.eid` section (5.5 MiB, `wow_loader.eid`) holds Eidolon-encrypted code,
byte-identical across sessions (fixed per-build key). The decrypted window is
only reachable while the game executes it. We built and tested every
user-mode instrument: (1) VEH fault observation — no fault exists; the decode
is explicit, raising nothing. (2) Edge-site hooks on the two verified
loader→`.eid` jumps (`0x1625FEA` → `.eid+0x8033`, `0x161185E` →
`.eid+0x3D1864`) — zero hits across runs; those blocks do not execute during
login/world-entry Warden activity. (3) A VirtualProtect interception was
planned but is IMPOSSIBLE for this build: the loader has no hookable import
stubs (zero MBA stubs, zero valid IAT entries, zero import pointers in
`.data`; PE headers are wiped to 0xFF at runtime). (4) A write-trap
(`native/eid_writetrap.h`) made `.eid` pages read-only to fault the decoder's
first store — zero snapshots; the game can also VirtualProtect the trap away.
All instruments are retained in the source tree for future captures. The
next step, when resumed, is the AMD SVM/NPT hypervisor (§12.11).

Housekeeping on 2026-10-03: the MCP server/connector was removed from the
project entirely (source, GUI controls, registration scripts, binaries) — it
was never used and was pure bloat. Older sections of this guide still mention
it historically; those mentions are superseded. Capture folders are now
named `<exename>-<month.day.year>-<UTC HHMMSS>` (for example
`wow-10.3.26-132100`) instead of `dump-YYYYMMDDxHHMMSS-mmm`.

## 1. Reproduction target and scope

The workflow is:

1. Build the standalone `C:\Users\<user>\Documents\GitHub\WardenDump` tool with `build.bat`, then run `release\WardenDump.exe`. Select the process and WoW Retail/Classic engine and start capture. Historical captures in this guide were produced by WINKR; their addresses do not identify a new session.
2. Let the target run through the activity of interest, then choose **Stop & finalize**. The standalone tool retains the original main-image/Eidolon and loader path, adds executable-allocation snapshots and observed thread-origin module images, and embeds census metadata in one `dump.bin`. Each run has its own `release\captures\dump-YYYYMMDDxHHMMSS-mmm` directory.
3. Open `dump.bin` in IDA Pro 9.3 as AMD64 PE.
4. Import the focused appended loader/module records with the supplied `dump_segments.py` script.
5. Recover protected bodies and flattened control flow using the saved IDA database, native byte evidence and D810/CoBRA where appropriate.

For a new launch, choose the executable in WardenDump's launch selector and click **Arm for next launch** before starting the game. Existing instances are ignored; a 100 ms watcher detects the next instance and checks process creation identity. The capture DLL waits for the relevant game loader DLL before main-image decryption. This avoids a workflow requirement to enter the world before requesting capture, but is not a guarantee of first-instruction coverage or successful loading into a protected process. Stop cancels the watcher or loader-readiness wait.

When loading fails, inspect `loader_diagnostics.json`: it distinguishes bootstrap progress, the full returned module handle, the target thread's immediate Windows error, and subsequent file-identity verification. The older generic “Windows did not load the capture DLL” message does not establish a cause. The 2026-10-02 17:46:33 failure remains unresolved on the real target; zero queried process-policy flags were observed, and that process exited before a diagnostic load could be repeated. Fixture tests validate diagnostic reporting and launch controls, not live-game recovery.

The IDA recovery steps operate on saved evidence. Capture itself is active: the standalone host loads a capture DLL through Windows `LoadLibraryW`, starts its exported worker, and retains the original WoW page-copy/decryption behavior, including temporary page-permission changes. The target continues running. Do not describe the capture stage as static analysis.

The standalone GUI includes **Start MCP**, **Restart MCP**, and **Stop MCP** controls. `register-mcp.bat` registers its `WardenDumpMCP.exe` connector with Codex/Claude or exports configuration snippets using the installation's actual path. The GUI target dropdown includes only supported WoW variants and Hearthstone. Configuration and file format are documented in [the standalone README](../../../WardenDump/README.md).

Builds overwrite generated files in the single `release` directory while preserving capture evidence. **Force stop target** terminates the active capture's process after checking its PID and creation time; it leaves an incomplete capture, not a finalized dump. MCP provides the same action through `force_stop_capture`. Cooperative Stop remains preferable when responsive.

WardenDump 1.3 replaces per-byte live gadget queries with buffered executable-page scanning, cancellation checks and a five-second budget between reads. The observed 18:03 launch attempt loaded the DLL and started its worker, then remained at gadget discovery with high worker CPU despite Stop. This supports a post-load scan hang; it does not establish a crash or explain the separate bootstrap-stage-0 failures. Scanner and force-stop fixture regressions passed, but live decryption remains unvalidated. The Windows loader mechanism was retained.

Follow-up evidence from 18:19 separates two additional failure points. Armed capture `dump-20261002x181930-230` reached loader stage 2 and started the worker, which then reported that no Eidolon signature was present in readable executable pages. Subsequent attempts against PID 19028 returned to bootstrap stage 0, before a meaningful Windows loader error was recorded. The cause of those stage-0 attempts remains open. The newest build records remote bootstrap buffer addresses to make the next failure more diagnostic. Its GUI also follows the launched PID and mode, and labels the main controls while armed, capturing, or stopping.

Live analysis runs in the GUI host through Windows memory APIs, independently of the capture DLL. MCP exposes raw/scalar/string reads and writes, expected-byte patches, guarded undo, memory-region enumeration, byte-pattern scanning, and thread-start queries, in addition to capture controls and saved-artifact reads. Writes preserve original bytes in `analysis.jsonl`, verify readback, and report partial-write/protection-restoration failures; protected edits require explicit temporary permission changes. Undo checks process identity and current bytes. These operations do not suspend the target, and thread starts do not establish current RIPs. The injected DLL remains dedicated to capture/decryption and unloads afterward. The tool does not provide decoded selector transactions or inherit the experimental WINKR dispatcher tracer.

Validation scope: the native GCC build and end-to-end Generic-mode fixture tests passed on 2026-10-02, including the expanded 1.1 analysis/GUI tests and portable registration tests. The tests verify combined-container contents, a private executable allocation, a thread-origin DLL, repeated capture, DLL unloading, host-side memory editing and undo before injection, code-page protection restoration, MCP lifecycle controls, and failure reporting. The retained Eidolon/loader path still requires validation against the intended WoW capture; fixture success is not a decryption result. Generic/Hearthstone mode captures readable memory without applying WoW decryption.

## 2. IDA setup

Known environment:

- IDA Professional 9.3: `C:\Program Files\IDA Professional 9.3`
- Python 3.14 supplied by IDA
- `ida-pro-mcp`, listening on `127.0.0.1:13337`
- D810-ng `cfg-recon-mainline`
- D810-CoBRA backend
- Recommended D810 profile: `eidolon_v4_const_simplify_solve.json`
- Capture IDB: `C:\Users\<user>\Desktop\dump\dump.bin.i64`

After the PE finishes initial analysis, run this in IDA's Python console to import the focused records:

```python
exec(compile(open(r"C:\Users\<user>\Desktop\dump\dump_segments.py", encoding="utf-8").read(),
             "dump_segments.py", "exec"))
```

Use the importer supplied with the specific capture. The standalone importer maps the latest loader and thread-origin image records and committed regions of the latest allocation snapshots, with permissions from the census. Thread-origin images can include system DLLs. It does not decrypt bytes by itself, save the IDB, or close IDA. A Win32 thread start does not establish current execution, allocation ownership, or creator ancestry.

For whole-database analysis, allow IDA autoanalysis to finish, then use IDA's reanalysis command over the imported segments. Do not force every data segment into code: `.rdata`, `.data`, `.pdata`, loader metadata and encrypted/padding regions must remain data unless native references prove otherwise.

## 3. IDA recovery procedure

Use this order for a new body:

1. Confirm the exact runtime-function bounds from `.pdata` and retain original bytes, types, names, frame size and chunks.
2. Build a conservative flag/control-flow graph from native instructions. Do not collapse an exceptional branch solely because it looks unreachable under an assumed stack state.
3. Repair only closed, bounded overlapping instruction ranges. Preserve `EB FF` alternate-entry evidence and reject unresolved indirect edges.
4. Repair cumulative SP metadata from graph-proved incoming depths. IDA's user stack-point delta is relative to the preceding point; it is not the literal native depth.
5. Regenerate F5 with a fresh no-cache decompilation after autoanalysis settles.
6. Apply types only where the ABI and field offsets are proven. A type layout does not establish a runtime allocation bound.
7. Run D810/CoBRA deliberately on selected functions. A shorter pseudocode listing is not accepted without native correspondence and preserved warnings.
8. Add an IDA comment with the evidence scope, unresolved paths and a journal filename. Save the IDB.

Never convert an unresolved encrypted/padding region into a large invented function merely to make it blue.

## 4. How the dump is decrypted

### 4.1 Eidolon/page path

The dump DLL locates an Eidolon read gadget in the target WoW image. The gadget is used as a QWORD transform for executable pages:

```c
for (int i = 0; i < 512; ++i)
    decrypted_page[i] = eidolon_gadget(&encrypted_page[i]);
```

The focused dump copies committed pages into a `SizeOfImage`-sized main-image buffer. Executable pages are passed through the gadget when available; data pages are copied with temporary read access. A raw copy is never silently labeled decrypted. The front PE image is rebuilt with the captured headers/TLS/IAT state and a `main_final` observation is appended to the same `dump.bin`.

The captured descriptor table is at `0x7FFAF4346790`. It contains 24-byte records `(image_base, image_size, eid_metadata)`; record zero describes WoW base `0x7FF641320000`, size `0x6D9E000`, and metadata `0x7FFAF4420018`. The table is data, not code. The `.eid` metadata format is only partially recovered in this capture.

For the current dump DLL, the preferred gadget locations are Retail RVA `0x1E7040` and Classic RVA `0x6629E0`. The expected fast-path signature is `48 8B 01 C3` (`mov rax,[rcx]; ret`); if it is absent, the DLL scans the image for the same four-byte gadget and refuses to label executable pages decrypted when no gadget is found. A later loader-specific gadget can temporarily replace the WoW gadget while `Wow_loader.dll` is dumped, then the previous pointer is restored.

### 4.2 Protected Warden/module bodies

The loader and Warden bodies use an inline byte transform. Historical notes and the current IDA evidence preserve the operation as a keyed XOR stream over a bounded body:

```c
decrypt_base = address + 20;
decrypt_end  = address + body_length + 20;
for (p = decrypt_base; p < decrypt_end; ++p)
    *p ^= key[(decrypt_end - p) % key_length + 15];
```

The exact body header/key material is capture-specific. Use the supplied recovered ranges, original-byte hashes and current IDA comments rather than applying this routine blindly to arbitrary data. All 17 identified candidate-A006 bodies and cached module ID 1's 149 decoded ranges have retained provenance in the journal; that is not the same as completing the semantic reversal of every range.

Important distinction: the SHA-256 values in the journals are **integrity fingerprints**, not decryption keys. They let you prove that an IDA recovery started from the same bytes and that an analysis-only normalization did not silently change an unrelated body. For example, the three unresolved main-image runtime-function extents have these complete captured hashes:

```text
4FBD90..4FEE92  EA6EAC04C9A49FDE084A845249023CF3F70AB7018FDBA95EB7E4085DDC7D11C6
5DD680..5DD6F5  149FD70283CC1C28B199BD851500A15E12125CA0E74B71C52C34AD50A959891E
5E0550..5E095B  3804B1D9C4B221904305609238F3AA4E85E8601AEE8B24DB078F6B8E1CC2557D
```

The dump DLL also emits build-specific `eidolon_key1`, `eidolon_key2` and `eidolon_run` lines in `wow_loader_crypto.txt`. Those are hardcoded extraction/reporting constants in the current source and were **not** independently verified as the current build's complete key material. Do not substitute them for the live gadget transform. The verified executable-page operation is the 512-QWORD gadget call above; the verified inline body operation is the bounded XOR loop above.

### 4.3 Network response cryptography

The dispatcher receives an encrypted request, validates its header, and selects one of 35 handlers (selectors 0 through 34). The shared transport path:

- decrypts a bounded request span (strict captured cap: 1008 bytes);
- restores input CBC feedback before header/payload processing;
- executes a selector handler;
- optionally appends a handler record to the caller's output descriptor;
- builds a response header containing FNV32, copied input metadata, handler status and payload length;
- adds checksum/padding/alignment bytes;
- encrypts the response with the captured RC5-32/12-compatible core and output CBC feedback;
- copies the published used length back to the host callback context.

The captured response subkeys are retained in `warden-selector18-crypto-input-contract-20260930.json`; the SHA-256 of the 26 little-endian expanded DWORDs is `1941a129aef01b91e181b178e1919daae773acbec4c497f5a46e03bb2842e08f`. This is the client response cipher, not proof of the server protocol or a server verdict.

The captured response schedule is reproducible exactly:

```text
rounds = 12
S[0]   = 0xB7E15163
Q      = 0x9E3779B9
source schedule = 26 little-endian DWORDs at loader/WMP1 table BB83A0

A6C1323C 15CBEC91 29ED8F81 D8A111C9 3C7421A7 5E6AA184
34609276 55749F7C 73506AF7 9889A88D C3BD3D65 B2457F6A
8BA27322 29D8C691 D6D81880 B5E6E638 793151A7 4F290E40
D8F59B95 9442ECDE 5DEB4072 25116A10 1AF80042 F933AE54
814D9412 9A101C0B
```

This is an unrolled 8-byte RC5-32/12-compatible encryption core with 26 fixed captured-state subkeys. The original user-key length/material that produced this expanded schedule has not been established, and it must not be conflated with a separately expanded selector32 key.

The schedule's recognizable initialization is RC5's `P=0xB7E15163`, `Q=0x9E3779B9`, followed by 78 mixing updates over 26 `S` words and four key words (indices wrap modulo26 and4). That identifies the expanded schedule construction; it does **not** recover the original four-word user key.

Other captured constants needed to reproduce the transport analysis are:

```text
initial working CBC state: F7DEFB7B28AD8B97 (embedded baseline, not a live IV claim)
input snapshot seed:       EB171F52 -> captured default seed 0
output snapshot seed:      73BE388E -> captured default seed 0
response FNV seed:         0x73BE388E -> 0/default in the response envelope
input FNV seed:            0xEB171F52 -> 0/default in the request path
```

The input path restores the input snapshot before decrypting the header/padded payload and saves it after the input phase. The output path restores the output snapshot before response encryption and saves it after ciphertext generation. A normal selector18 37-byte record has a 37-byte header payload, FNV coverage of 49 bytes (`packet + 4` through the payload), 11 late alignment bytes and a 64-byte ciphertext extent when capacity is sufficient. The no-record response is a different filler path: marker `0x3D4270F7` (little-endian bytes `F7 70 42 3D`), 16–111 inclusive PRNG iterations, optional 16-byte preheader alignment and a 32–128-byte header payload range. These two paths must not be merged.

The SHA-256 schedule fingerprint is an evidence check: calculate SHA-256 over the 26 DWORDs serialized little-endian and compare with the value above. It is not a SHA-256-derived secret and does not decrypt a new capture by itself. Re-run the native extraction for a different build and expect the schedule, CBC constants and body keys to change.

CBC snapshots are separate input/output direction state. Normal first-record analysis shows input feedback may already be saved before checksum or stop-gate failure; output feedback is saved only after the corresponding output phase. Later records can inherit state from earlier records in the same dispatcher call.

### 4.4 Raw TCP capture boundary

The 2026-10-02 PktMon capture confirms a process-correlated TCP/3724 flow contains the plaintext line `WORLD OF WARCRAFT CONNECTION - CLIENT TO SERVER - V2` followed by LF. WoW main-image code compares a 52-byte server greeting before sending that line. The downstream PacketPipe reader consumes a 32-bit little-endian length followed by exactly that many bytes; however, early TCP/3724 records in this capture have an additional 12-byte field between the observed length and the length-sized typed message, so the code that removes or consumes this outer field has not yet been identified. One captured client message `0x00440003` and server message `0x004C0004` decode exactly against main-image serializers/handlers. The server record carries a DWORD, a 64-byte signature, and a flag; IDA routes the signature through an Ed25519-style context-separated verifier and then a NetClient connection/region callback. IDA does not route this record to the Warden selector dispatcher. Later records contain high-entropy 12-byte fields and bodies whose cryptography is not recovered. A separate NetClient helper validates a 12-byte checksum/zlib envelope only for typed message `0x004C000E`; this is not evidence that the outer 12-byte capture field is that zlib header. The `<host>:3724` trace remains incomplete: its client SYN is present, but its server SYN-ACK/greeting and substantial TCP sequence ranges are missing. Keep these WoW connection/transport findings separate from the Warden dispatcher's RC5 response cipher. Detailed bytes and IDA joins are in the journal's 2026-10-02 manual decode entry.

### 4.5 Runtime selector trace

The dumper writes `warden_dispatch_trace.jsonl` during a WoW capture. It scans observed private executable candidate allocations for a 19-byte dispatcher-entry signature, then finds the selector `MOVZX` and requires a unique match. It also derives the validated request pointer and total-length stack slots from repeated pointer/length load instructions in the loaded dispatcher; it does not assume fixed absolute addresses or hardcode those stack displacements. A hardware execution breakpoint at the shared switch records every selector that reaches it, QPC, thread ID, allocation base/RVA, the validated plaintext request bytes (up to 1 KiB), and a bounded raw stack snapshot. The handler writes to a preallocated ring; the dump worker drains it to disk and reports dropped events and breakpoint-install failures.

This is active instrumentation: it does not patch Warden instructions, but sets per-thread debug registers and may be detected or affect timing. Capture begins only after signature discovery and thread attachment, and can miss events when a thread is not attached or the bounded ring overflows. The trace records dispatcher input, not the handler's completed output or the final encrypted response. `warden_network.pcapng` remains an all-NIC capture containing unrelated traffic. Use selector events as positive evidence that a Warden request reached dispatch, then correlate QPC and PID-owned endpoint snapshots with packet timestamps; do not equate one selector event with one wire frame without sequence-level evidence. The generic request capture has compiled but has not yet been validated against a live client.

The GUI also recognizes `Hearthstone.exe`. Hearthstone uses a separate external read-only mapped-PE capture in `dump/hearthstone_<pid>/dump.bin`; it does not use WoW offsets, core injection, or the Warden dispatcher trace. When packet capture is selected, its PktMon artifacts use a `hearthstone_` filename prefix. This path is build-validated but still needs a live Hearthstone capture.

The loader relationship needs careful wording. The dump includes the loaded `Wow_loader.dll` image and separately records private executable allocations and queried thread start addresses. User observations place many Warden thread starts inside the loader's address range, which supports a loader role in hosting or starting Warden work. It does not prove that every module's code resides in that DLL, that every Warden thread starts there, or which thread created a given allocation. Keep loader code, separately allocated/decrypted module bodies, and thread creator ancestry as distinct questions until the runtime trace connects them.

## 5. The dispatcher

The dispatcher is the protocol-to-handler bridge. It is the code that receives the decrypted request, validates the common framing, selects a handler, brokers its output and turns the result back into an encrypted response. It is not itself one of the 35 selectors.

The recovered shared body is `0x7FF697B93970..0x7FF697B9D8ED`. The normal call wrapper is `0x7FF697AE14E0..0x7FF697AE179B`; it receives a context and output object and passes the protected context token through the native ABI. The header/length path at `0x7FF697ADEF30`/`0x7FF697B72670` validates the decrypted request span, reads the selector WORD, rejects selectors above34, and clears/returns a framing error before the case table when the common header is invalid.

The native case switch begins at `0x7FF697B95C65` and uses the captured table at `0x7FF697BB84EC`. It has exactly 35 entries, selectors0 through34. Selector18's dispatch edge is `0x7FF697B9CAD3`, which calls `wmp1_selector18_call_wrapper` at `0x7FF697AB4C90`. The handler receives a decoded request pointer and length plus the output descriptor; it does not receive a server-side command name.

The output object is a caller-owned prefix:

```text
+0x00  data pointer
+0x08  used DWORD
+0x0C  capacity DWORD
+0x10  ownership byte
```

The dispatcher saves the old used length, gives each handler the remaining capacity, and commits only when the handler's append fits. A selector can return success without appending anything; a report can also be skipped because capacity is insufficient while the handler's local comparison still returns zero. The dispatcher then creates the common response header: FNV32 at+0, a copied parsed-input field at+4, handler status at+8, and published payload length at+12. It hashes the packet beginning at+4, adds the checksum/alignment bytes and sends the encrypted response through the 4.3 crypto path.

The important status layers are separate:

- handler status: selector-specific result such as selector18's0/1/257;
- gate status:0 continue,6 stop callback, or1030 wait/deadline result;
- dispatcher/transport status:0 normal response,1024 input/checksum failure,1026 output capacity/alignment failure,1027 malformed/too-short request, and1028 output cipher/block failure.

At normal completion the published used length is copied to the host callback context (`context+80` data pointer, `context+88` used length). The final dispatcher status is kept separately from the handler status. Input/output CBC snapshots are direction-specific, and first-record failure analysis shows that input feedback can be saved before a later checksum or gate error; this is why the dispatcher must be understood before interpreting any selector's status.

The dispatcher can process more than one record in a call. A continuation flag and remaining-length test control the next record, so a later failure can inherit feedback and output state from an earlier successful record. This is also why “selector18 returned0” is insufficient to conclude that the server received a registry report.

## 6. What a selector is

A selector is a command number in the decrypted Warden request header. It is not a Windows thread ID, module ID, function ordinal or encryption key. In this capture the shared dispatcher reads the selector WORD, validates that it is at most `34`, and uses it to choose one of 35 handler branches. The request is encrypted before this point; the server/request producer is not directly visible in the static client dump, so “selector 18 means registry comparison” describes the client branch we recovered, not a proven server-side command name.

The handler receives a decoded request pointer, the request's validated/derived length and an output descriptor. It may query local state, append records, return a handler status, or do nothing. The dispatcher then wraps that result in the common response envelope. A handler's return value is therefore not automatically a server verdict and does not necessarily mean a record was appended. Selectors 5 and 8 are join/state branches in the recovered dispatcher and should not be counted as missing independent modules.

For this capture, the shared dispatcher is `0x7FF697B93970`. Its header path validates the decoded body length, reads the selector WORD, rejects values above `34`, and routes through the native case table at `0x7FF697B95C65`. Selector18 enters through `0x7FF697B9CAD3` and its wrapper `0x7FF697AB4C90`. The selector is therefore a client-side dispatch field carried by the encrypted request; the capture does not prove which remote Warden/HQ message name produced a given number.

Each row below separates three questions: what the client branch currently appears to do, what evidence supports that description, and what still prevents a complete reversal. “Partial” means the operation is recognizable but its full request, error, consumer or transport contract is open. “Open” means the branch has not yet earned a behavioral label.

| Selector | What the client branch appears to do | Evidence and remaining work |
|---:|---|---|
| 0 | No complete operation label yet. | Dispatcher target identified; body/request and response meaning open. |
| 1 | Enumerates committed private/image memory regions with `NtQueryVirtualMemory` and retains encoded MBI records in shared cache. | Captured slot 0 is service `0x23`; State/Type/Protect filters, callback-stop rule, 48-byte cache lifecycle, no-record response and error bounds are recovered. RDTSC/LCG gate outcome and stack-dependent alternate branch values are runtime qualifications; remote request/server meaning is outside the dump. |
| 2 | Scans selected virtual-memory regions for QWORD values that point into the first loader-listed module, then emits region/RVA fingerprint records. | Request fields, MBI filters, RVA collection, record header and capacity behavior are recovered. A bounded supplemental candidate scan and global hit counter are present. Stack-dependent protected helper paths and the ultimate network consumer remain unresolved; see Section 10. |
| 3 | Collects CPU-related information. | Sampled inputs and option fields are visible, but serialization and consumer are unresolved. |
| 4 | Hashes selected nonwritable PE image sections and appends a checksum record. | `0x7FF697B86940`; PE header/section selection and rolling hash are recovered, but malformed-image and delivery paths remain open. |
| 5 | Dispatcher join/state behavior rather than a standalone probe. | No independent module body established; preserve the join semantics when analyzing the surrounding state machine. |
| 6 | Reads virtual-memory regions and inspects exception-handler-related state, producing fingerprint/report material. | `NtQueryVirtualMemory` paths and handler inspection are recovered; source-region bounds and response consumer remain open. |
| 7 | No complete operation label yet. | Dispatcher target exists; semantics and output open. |
| 8 | Dispatcher state/branch path rather than a proven standalone module. | Do not count the branch as a second undiscovered body until its state transition is traced. |
| 9 | Uses a callable bank/table of possible internal operations. | The 34-row structure is identified, but live targets, invocation conditions and returned values are not captured. |
| 10 | No complete operation label yet. | Body and response meaning open. |
| 11 | Samples image/page-read timing. | `0x7FF697B4A860`; seven samples and elapsed-value handling are recovered. This is not, by itself, proof of an anti-debug verdict. |
| 12 | No complete operation label yet. | Body and response meaning open. |
| 13 | Captures a named module or section using PE/module parameters. | `0x7FF697B23050`; section/read record construction is readable, but request origin and delivery consumer remain open. |
| 14 | No complete operation label yet. | Body and response meaning open. |
| 15 | No complete operation label yet. | Body and response meaning open. |
| 16 | No complete operation label yet. | Body and response meaning open. |
| 17 | No complete operation label yet. | Body and response meaning open. |
| 18 | Compares three registry key/value chains. It enumerates registry components, queries values, hashes/compares requested content and can append a 37-byte result record. | Main handler `0x7FF697AEF420`; registry APIs, report layout, CBC/status behavior and ownership are documented. Full completion is blocked by downstream `0x7FF6414FBD90`, registered `0x7FF6415DD680`, callback continuation `0x7FF6415E0550`, and unresolved dynamic state provenance. |
| 19 | No complete operation label yet. | Body and response meaning open. |
| 20 | Forwards into another operation rather than exposing a self-contained probe. | Body-124 target, ABI, state and forwarded result handling remain open. |
| 21 | Filters/serializes pool-tag-related information and requested counts. | `0x7FF697B816D0`; formatting and filtering graph are readable, but tag/API source, duplicate behavior, errors and transport consumer remain open. |
| 22 | Collects callback/path/query information, including drive/path and SFC-related data. | `0x7FF697B66920`; callback ownership, drive-table capacity, query serialization and report consumer remain open. |
| 23 | No complete operation label yet. | Body and response meaning open. |
| 24 | Reports process/thread census information. | `0x7FF697B026D0`; counters and serialization are visible, but ownership, reset/concurrency and query-failure semantics remain open. |
| 25 | No complete operation label yet. | Body and response meaning open. |
| 26 | Parses a large multi-case request/record grammar. | `0x7FF697B30D70`; graph is readable, but grammar, helper contracts, bounds and produced objects are not fully established. |
| 27 | No complete operation label yet. | Body and response meaning open. |
| 28 | No complete operation label yet. | Body and response meaning open. |
| 29 | No complete operation label yet. | Body and response meaning open. |
| 30 | No complete operation label yet. | Body and response meaning open. |
| 31 | No complete operation label yet. | Body and response meaning open. |
| 32 | Sets up TCP/RC5-related transport/framing state. | `0x7FF697B1D000`; captured key schedule is known, but framing, key lifetime, buffers and callback delivery remain open. |
| 33 | Waits on or tests an unprotected flag/state path. | `0x7FF697AB3EB0`; wait target and state transitions are not yet tied to an externally observable result. |
| 34 | No complete operation label yet. | Dispatcher target exists; body and response meaning open. |

## 8. Reversal checklist

### Capture and tooling

- [x] Focused dump produces one `dump.bin` containing PE plus appended ADCK records and metadata.
- [x] Warden loader threads are allowed to run during dumping.
- [x] IDA 9.3, IDA MCP, D810-ng and CoBRA are installed and usable.
- [x] `dump_segments.py` imports selected latest loader/image records without mapping every system allocation.
- [ ] Repeat capture on a later supported build and verify relocation procedure.

### Decryption and image recovery

- [x] Eidolon gadget discovery and executable-page transform are implemented in the dump DLL.
- [x] Main image and loader observations retain original and `main_final` provenance.
- [x] Protected candidate bodies and cached module ranges have retained byte/key provenance.
- [ ] Fully decode the captured `.eid` metadata/page-validation format.
- [ ] Recover transient or separately allocated Warden data not present in this snapshot.

### Dispatcher/network path

- [x] Header validation and selector dispatch table 0–34 identified.
- [x] Request cap, response envelope, FNV/checksum ordering and RC5-compatible response core documented.
- [x] Input/output CBC snapshot phases and first-record status matrix documented.
- [ ] Prove malformed-pointer, concurrent mutation and all wrapped-allocation behavior from native paths.
- [ ] Trace server-message origin, callback delivery and server-side interpretation.

### Selector work

- [x] Complete selector 1's captured command-201 flow, including its query API, filters, callback behavior, shared-cache lifecycle, no-record response path and error/bounds behavior.
- [ ] Finish selectors 0–17 according to the inventory above.
- [ ] Finish selector18's three unrecovered downstream dependencies and reset/consumer provenance.
- [ ] Finish selectors 19–34 according to the inventory above.
- [ ] Tie each handler's report fields to its transport consumer and server request meaning.

### Selector18 specific remaining work

- [ ] Recover reliable executable bytes and semantics for `0x7FF6414FBD90` (`.pdata` extent ends `0x7FF6414FEE92`).
- [ ] Resolve the consumer/invocation of registered address `0x7FF6415DD680` (`.pdata` extent ends `0x7FF6415DD6F5`).
- [ ] Recover the callback/report continuation at `0x7FF6415E0550` (`.pdata` extent ends `0x7FF6415E095B`).
- [ ] Identify any dynamic producer/reset for pending byte `0x7FF645708380` and stop flag `0x7FF64585CE52`.
- [ ] Replace the capture-limited status with a complete transport/consumer contract only when evidence supports it.

## 9. Evidence and source index

The detailed journals are beside this guide in `KB\Big Warden Reversal`.

- `reversing-warden.md` — chronological findings, corrections and IDA addresses.
- `warden-selector18-request-layout-20260930.json` — request fields and hashes.
- `warden-selector18-crypto-input-contract-20260930.json` — input/response crypto evidence.
- `warden-selector18-cbc-feedback-20260930.json` — CBC snapshots and phase order.
- `warden-selector18-first-record-feedback-audit-20261001.json` — conservative status/feedback matrix.
- `warden-selector18-ida-types-20261001.json` — reproducible IDA type/prototype changes.
- `warden-selector18-unrecovered-main-snapshots-20260930.json` — complete snapshot/hash/boundary audit for the three unresolved dependencies.
- `warden-selector18-startup-pointer-slots-20260930.json` — encoded-slot initialization provenance.
- `warden-selector18-gate-message-followup-20260930.json` — gate-message follow-up behavior.
- `warden-selector18-response-envelope-20260930.json` — response header/checksum/padding evidence.

When a new result is found, add a concise entry here and put the full native evidence in a separate dated journal. Do not turn this guide into another chronological transcript.

## 10. Selectors in depth

This section is the ordered working reference for selectors 0 through 34. It deliberately distinguishes a recovered client operation from the still-unknown remote message that requested it. A selector's purpose is described only when native control flow, captured API evidence or a preserved analysis journal supports it.

Status markers: ✅ = the captured client-side operation and its reachable static contract are recovered; ⬜ = partial or unresolved. A ✅ does not claim knowledge of the remote request producer or server-side interpretation. Selector 1 now meets this capture-specific standard; selectors with unresolved native behavior, report consumers or downstream dependencies remain ⬜.

### ⬜ Selector 0 — baseline/initialization branch

Selector 0 is the dispatcher's baseline/initialization branch, not an ordinary request-shaped probe. The case edge is `0x7FF697B95C6C`, targeting `wmp1_selector0_baseline_initializer_wrapper` at `0x7FF697AE4570`. The dispatcher passes only the shared output/context pointer in RCX; selector 0 does not consume a decoded request pointer or request length, has no selector-specific request fields, and does not directly append a registry-style record. Its returned EAX is routed through the common status broker: zero continues normal framing, while nonzero enters the handler-failure path.

The wrapper is a state machine that resolves and invokes protected body 133 (`0x7FF697BAC900`). It calls `wmp1_decode_body_if_needed` with the body-133 seed, encoded end/helper and cache byte, then selects one of two constant parameter tuples for the body call. The wrapper returns body 133's result unchanged. The alternate call form performs the common post-call cleanup/decode helper before returning the saved result. These calls use the shared output/context pointer, not a server command structure.

The capture proves selector 0's decode state. The body header at `0x7FF697BAC8E0` contains sentinel `0x1122334455667788`, so the decode helper returns `0` and leaves the body untouched. The body begins with a valid AMD64 prologue, proving it is already materialized rather than ciphertext. The helper's non-sentinel path is nevertheless documented: it builds the 33-entry permutation, inverse-substitutes the encoded body into the cache/body destination and returns `1`.

How this was established: the selector-0 case was located by decompiling the 35-entry dispatcher switch; the wrapper's caller/callee edges and two call forms were verified with native disassembly; the decode helper was traced through its sentinel comparison and inverse-substitution call; and the body header/prefix were read directly in IDA. D-810 was then run with the Eidolon profile. It refused a trustworthy body-133 pseudocode result because native-preanalysis exhausted its poison-restart limit, so the underlying flattened CFG, indirect calls and any body-written output remain open. No bytes or trap regions were patched.

#### Body 133: recovered native semantics and CFG limitation

The trustworthy entry prefix at `0x7FF697BAC900` saves eight nonvolatile registers, reserves `0x4A8` bytes of stack, saves the fourth argument, clears local XMM state, and calls `wmp1_fill_bytes(destination, 0, 0x400)`. This proves a 0x400-byte local scratch/state object, but not the meaning of each field. The current IDA function spans `0x1E90` bytes and reports 573 blocks; a native sweep finds 382 branch/call/jump-like decodes and 18 invalid/alignment locations. Many apparent targets land in `unk_...` or data-looking islands, and Hex-Rays reports `function frame is wrong`. The graph is therefore an anti-disassembly/opaque-predicate transform, not a trustworthy ordinary compiler CFG.

The only unambiguous indirect transfer is `call rax` at `0x7FF697BACDD1`. The surrounding sequence stores callback/context arguments and a zero flag, passes `-1`, `rdi` and `rbp` in the Windows x64 argument registers, saves the returned EAX, and conditionally calls `wmp1_context_free`. This establishes a dynamic callback-like operation with cleanup; it does not identify the callback target or prove that it is a particular anti-cheat check. The callback target, flattened state transitions, body output writes and final result computation still require a runtime execution trace or a cleaner materialized capture.

Selector 0 is therefore fully characterized at the dispatcher, wrapper, decode/cache and status-contract levels, but remains ⬜ overall until body 133's callback and transformed CFG semantics are recovered.

### ✅ Selector 1 — filtered virtual-memory enumeration

For this captured command-201 context, selector 1 does not consume selector-specific payload fields. The dispatcher calls the shared handler `wmp1_filtered_memory_region_scan_handler` at `0x7FF697AB5120` with fixed filter configuration, callback `0x7FF697AB44F0` and the shared output descriptor. The handler's captured body-011 sentinel selects branch A. Its effective Type mask is `0x6D2A8700` (`MEM_PRIVATE | MEM_IMAGE`); the Protect mask is `0xFFFFFFFF`. The related selector-2 wrapper has a distinct payload and configuration and must not be used to infer selector-1 inputs.

The shared enumerator at `0x7FF697AF4CB0` walks virtual addresses starting at zero and queries 48-byte `MEMORY_BASIC_INFORMATION`-shaped records with `NtQueryVirtualMemory`, information class 0, current-process pseudo-handle `-1`. The callable is resolved from adopted table slot 0: the captured table maps that slot to service `0x23` (`NtQueryVirtualMemory`) and has no cached callable pointer, so WMP1 constructs an 11-byte syscall stub. A literal `7` passed by an intermediate wrapper is an unused argument; the builder reloads the actual table index from descriptor offset `+16`, which is zero here. Evidence for the adopted table is retained in `warden-callable-small-functions-20260930.json`.

Successful MBI records are checked against the queried base address, user-address extent/overflow limits, allocation-base ordering and an additional captured integrity predicate. A valid record is encoded and appended to the shared 48-byte cache **before** filter or callback evaluation. Callback eligibility requires `State & 0x1000`, `Type & 0x6D2A8700`, and nonzero `Protect`. The wrapper then calls body 008, whose captured sentinel path returns zero for every callback-qualified record; this stops enumeration at the first eligible region. The callback does not append a selector-specific result record. Its scan result is ignored by the selector-1 dispatcher continuation, which retains the output descriptor's reserved baseline and produces the common no-record filler response.

The shared cache starts with a 60,000–99,904-byte allocation and stores encoded 48-byte records. When full, it requests twice the previous capacity using 32-bit size arithmetic, copies the previous used bytes, frees the old allocation and appends the new record. Allocation failure returns 130. Cache replay uses the bounded indexed body-070 accessor; body 015 initializes the cache and body 073 performs cleanup. The shared cache is internal state and is distinct from the response packet. Query status `STATUS_INVALID_PARAMETER` returns 0; `STATUS_ACCESS_DENIED` writes a diagnostic and halts if the diagnostic descriptor is active, otherwise scanning advances. Other failed queries advance by `0x1000` until the upper scan bound. Malformed MBI data returns 1031 (with the same conditional diagnostic/halt behavior); allocation failure returns 130. A nonzero pre-query gate value returns early. The gate is reached only for a subset of LCG states and can depend on RDTSC/runtime history, so a particular runtime result is not inferable from the static image.

The alternate body-011 decode-success route reaches branch B, but its Type mask and callback context depend on stack-residue values with no recovered writes. The captured header sentinel selects branch A, so branch B is not part of the captured route. This reversal establishes the local client behavior and response contract; it does not identify the remote command name or server-side use of the returned envelope. Full control-flow and error evidence: `reversing-warden.md`, “Selector 1 - captured-flow reversal” and its closure audit.

### Selector 2 — virtual-memory pointer/RVA fingerprint report

Selector 2 is a request-configured memory-region scan with a report format distinct from selector 1. Its normal request has a six-byte payload (the common header plus payload totals ten bytes). Payload byte `+4` is a minimum region size in pages; byte `+5` is an optional maximum in pages, where zero means no maximum. The DWORD at `+6` supplies region Type bits (`0x01060000`, selecting `MEM_PRIVATE`, `MEM_MAPPED` and `MEM_IMAGE`) and page-protection bits (`0xFE`, request-selectable `PAGE_*` bits 1 through 7). The common request validator checks that the declared length plus the four-byte header equals the supplied request extent; it does not independently prove that the pointer refers to readable allocated memory.

The handler calls the shared current-process `NtQueryVirtualMemory` class-0 enumerator, then requires a structurally valid MBI with `State & 0x1000`, a nonzero intersection with the requested protection mask, and a nonzero intersection with the requested Type mask. The page-size bounds are applied by the selector callback. This is independent configuration from selector 1's fixed Type/protection masks, even though both reuse the enumerator and its encoded MBI cache.

For each size-qualified region, body040 examines every byte offset at which a full QWORD remains. A QWORD whose value falls inside the first entry in the loader's `InLoadOrder` list (`[DllBase, DllBase+SizeOfImage)`) contributes its 32-bit module-relative RVA. The handler deduplicates the hits. No hit means no output record. One hit serializes one RVA slot, two hits serialize two slots, and three or more distinct hits serialize sixteen slots; the values are ordered and byte-swapped, with unused slots zero-padded in the sixteen-slot case. A `CDCDCDCD` marker follows the slots.

This behavior produces a compact fingerprint of qualifying regions that contain pointers into the first loader-listed module. That description follows directly from the comparisons and serialized RVAs. The broader reason for collecting these pointers is not established by the captured code; in particular, the output alone does not prove a cheat verdict or identify a server-side detection rule.

The callback then performs a bytewise supplemental scan of the source region, capped at eight candidates and bounded by a `0x864`-byte scratch area. A candidate path can add its module-relative RVA and a bounded source span (normally up to 256 bytes). Some candidate predicates are visible, including a zero-byte pattern, but a protected helper's return depends on unwritten stack state; the exact stable signature and runtime reachability are not established.

Each emitted record has a 37-byte header followed by scratch data. The header contains RegionSize at `+0`, the serialized RVA-slot count at `+8`, BaseAddress at `+0x10`, the first loader module's DllBase at `+0x18`, zeroed bytes at `+0x20..+0x22`, and scratch length at `+0x23`. The first aggregate capacity check requires room for header plus scratch. If it fails, nothing is appended and the callback stops enumeration; separate later checks can leave a header without scratch in exceptional descriptor states. The global hit counter `BBC318` is zero in the captured image's initial state, increments for a hit-bearing region before append validation, and has no reset in the captured request path. Its equality check against 16 stops a later qualifying callback; repeated requests can inherit the counter.

Enumerator allocation failure returns 130; malformed MBI structure returns 1031. Normal address-space completion and callback stop return scan status zero, which can still carry earlier records or a partial header. A fresh-query timing gate and several protected-helper/cross-entry paths depend on runtime state or stack residue, so static analysis does not establish which exceptional path a live request takes. The host delivery callback receives the committed output buffer and length, but its captured continuation is opaque; no socket/send API or server-side interpretation is proven. Selector 2 is therefore behaviorally characterized as a memory-region pointer/RVA fingerprint collector, while its candidate matcher and final transport consumer remain open. Detailed addresses, status paths and evidence are in `reversing-warden.md`, under the Selector 2 entries.

### ⬜ Selector 3 — CPU-related collection

Selector3 collects CPU-related values or capabilities and serializes them into the shared response buffer. The current evidence supports the broad category only: the exact sampled instructions, request options, field widths and downstream interpretation have not been proven. Its security purpose may be environment/fingerprint collection, but no anti-debug or server-verdict meaning should be assigned until the serialized fields and consumer are traced.

### ⬜ Selector 4 — PE image checksum and nonwritable sections

Selector4 is the first well-understood image-integrity path (`0x7FF697B86940`). It reads the PE DOS/NT headers, derives the section table using `e_lfanew` and `SizeOfOptionalHeader`, and selects sections whose raw size is nonzero and whose characteristics do not have the write bit `0x80000000`. It hashes `SizeOfRawData` bytes from the image's virtual address, using the captured rolling/FNV-style stages and a seed derived from the previous checksum (or the default seed when zero), then appends the resulting record.

The reason for the filter is to fingerprint code/read-only image content without treating writable sections as stable integrity evidence. Malformed-PE behavior, inaccessible ranges, complete section-selection edge cases and the final report consumer remain open. Evidence: `warden-selector4-image-checksum-20260930.json` and the selector4 arithmetic journals.

### ⬜ Selector 5 — dispatcher join/state path

Selector5 is currently a state/join branch in the flattened dispatcher rather than a proven independent module body. The branch participates in common state transitions and may decide whether another operation runs or whether output is finalized. It is important because incorrectly counting it as a missing handler body inflates the module inventory; its exact state semantics still need a closed native trace.

### ⬜ Selector 6 — virtual-memory and exception-handler inspection

Selector6 combines memory-region reporting with a deeper handler-inspection path. One recovered call queries `NtQueryVirtualMemory` class0 (`MemoryBasicInformation`, 48 bytes); another path uses class2/filename-related information. The handler walks PEB/Ldr images, identifies `ntdll.dll`, derives an internal exception-handler list anchor from an export-resolved routine and conditionally queries candidate handler regions. It also has a 37-byte record writer with a native `(used + 37) <= capacity` guard.

This explains why selector6 can contribute both region/fingerprint and exception-state observations. The private-list layout, all candidate classification rules, optional 256-byte source extent and transport consumer remain unresolved. Evidence: `warden-selector6-handler-inspection-20260930.json`, selector6 response-trailer journals and the IDA comments at the recovered query sites.

### ⬜ Selector 7 — unresolved handler

Selector7 has a dispatcher target but no defensible behavioral label yet. Do not infer that it is a continuation of selector6; recover its wrapper, request reads, native calls and report writes independently.

### ⬜ Selector 8 — dispatcher state branch

Selector8 is currently represented by a state/branch path in the flattened dispatcher, not a separately attributed probe. Its existence matters for control-flow reconstruction and status propagation, but its operation cannot be named until the surrounding state machine is traced with native stack and output evidence.

### ⬜ Selector 9 — callable bank

Selector9 reaches a callable-bank structure with 34 rows. The table shape is visible, but the live targets were not captured in the offline bank contents. Therefore the selector's purpose could range from dispatching helper checks to invoking environment probes; the table alone does not identify which. Recover the initialization source, each target identity, invocation predicate and returned/output fields before assigning a name.

### ⬜ Selector 10 — unresolved handler

Selector10 has no complete request or response contract in the current evidence. Its wrapper and native callees remain a checklist item.

### ⬜ Selector 11 — image/page-read timing

Selector11 (`0x7FF697B4A860`) samples image/page-read timing, recording seven observations and low-32-bit elapsed values. The handler's timing threshold and response fields are visible, but a timing anomaly is not automatically an anti-debug verdict: scheduling, page availability and the remote consumer still matter. Complete the outer state, failure paths and report interpretation before treating it as a detection.

### ⬜ Selector 12 — unresolved handler

Selector12 has no verified operation label. Preserve its dispatcher edge and recover the request/output contract separately from adjacent selectors.

### ⬜ Selector 13 — named module/section capture

Selector13 (`0x7FF697B23050`) builds a parameterized module/section capture. Its helpers interpret module names and PE/section parameters, read a selected range and serialize the result into the common output descriptor. The native graph explains how a requested section can be captured, but not who supplied the name/section request or which later consumer interprets the bytes.

This is a capture operation, not proof that every returned range is Warden code or that the server requested a particular module. Evidence: `warden-selector13-named-module-section-capture-20260930.json`.

### ⬜ Selector 14 — unresolved handler

Selector14 remains unlabeled. The correct next evidence is its native wrapper and any indirect target resolution, not a name borrowed from selector13.

### ⬜ Selector 15 — unresolved handler

Selector15 remains unlabeled. Request bounds, local API use, output records and status propagation are open.

### ⬜ Selector 16 — unresolved handler

Selector16 remains unlabeled. It may share allocator or transport helpers with neighboring cases, but shared infrastructure is not evidence of shared purpose.

### ⬜ Selector 17 — unresolved handler

Selector17 remains unlabeled. Recover its request fields and report writes before attempting to classify it as an integrity, environment or module operation.

### ⬜ Selector 18 — registry comparison

Selector18 (`0x7FF697AEF420`) compares three registry-derived chains. The request contains three hash/count/value-hash groups at offsets `+4/+40/+44`, `+52/+88/+92` and `+96/+132/+136`, a fixed expected DWORD at `+48`, and a requested UTF-16 prefix beginning at `+144`. The handler opens/enumerates registry components, queries values using the captured adopted NTDLL bank, hashes names/content, compares the requested prefix and builds flags for DWORD equality, string inequality and prefix mismatch/zero-length behavior.

Its optional report is exactly 37 bytes: flags, first DWORD or `FFFFFFFF`, UTF-16 unit count, value hash and reserved tail. It appends only when the output-capacity helper permits; handler status and dispatcher transport status are separate. Registry/query allocation cleanup, output ownership and CBC phase ordering are recovered in the selector18 journals.

The gate-message path is now specified as well. `0x7FF6415E0260` accepts an eight-byte message and rejects any other length or a message whose DWORD at `+4` does not equal FNV-1a over the first four bytes (seed `0x811C9DC5`, prime `0x01000193`). Rejection returns `0` without state changes. A valid message sets stop flag `0x7FF64585CE52`, stores FNV-1a over all eight bytes, invokes the follow-up at `0x7FF6415DFC80`, and returns `1`. The follow-up consumes the pending byte, calls the unresolved `0x7FF6414FBD90`, then performs the encoded-slot registration through `0x7FF6414FEEA0`. The gate callback `0x7FF6415E0ED0` only reads the stop flag; no static reset or message-origin caller is present in this capture. This check is an integrity gate, not cryptographic authentication.

Selector18 is not marked fully complete because the follow-up calls into three main-image dependencies remain unrecovered: `0x7FF6414FBD90`, registered address `0x7FF6415DD680` and callback continuation `0x7FF6415E0550`. The capture contains identical unrecovered bytes for both primary and `main_final`; no plaintext implementation was invented.

### ⬜ Selector 19 — unresolved handler

Selector19 remains unlabeled. Do not infer its purpose from the numeric adjacency to selector18; the selector number is only a dispatch index.

### ⬜ Selector 20 — forwarding path

Selector20 forwards into another body rather than exposing a self-contained operation in the recovered wrapper. Its purpose depends on the body-124 target, forwarded ABI, state passed through the call and handling of the returned status/output. Until those are traced, it should be described as a forwarding mechanism, not assigned a probe category.

### ⬜ Selector 21 — pool-tag filtering and count formatting

Selector21 (`0x7FF697B816D0`) filters and formats pool-tag-related information, including requested counts and duplicate handling. The flattened body and its append/report mechanics are readable, but the request-selected kernel API/class, tag source, complete duplicate policy, skip/capacity behavior and transport consumer are not established. Its apparent system-information role is therefore a client-side operation category, not a proven server command name.

### ⬜ Selector 22 — callback/path/query collection

Selector22 (`0x7FF697B66920`) collects callback, filesystem/path and query information. Its recovered helpers include drive/path walking and SFC-related lookup/building, plus query-record serialization. The important open questions are callback ownership/lifetime, drive-table capacity, path-walk bounds, error/trailer fields and the downstream consumer of the assembled record.

### ⬜ Selector 23 — unresolved handler

Selector23 remains unlabeled. Recover its native request reads, target APIs and report path independently.

### ⬜ Selector 24 — process/thread census

Selector24 (`0x7FF697B026D0`) reports process/thread census information. It is relevant to the Warden thread-spawn question because it can observe thread state and starts, but its counters do not prove which thread created or consumes a Warden module. Counter reset/concurrency, query failures, input ownership, serialized fields and the final transport consumer remain open.

### ⬜ Selector 25 — unresolved handler

Selector25 remains unlabeled. No complete local operation or response contract is currently proven.

### ⬜ Selector 26 — large parser

Selector26 (`0x7FF697B30D70`) is a large 33-case parser/state machine. Its recovered graph makes the branch structure inspectable, but the grammar, helper contracts, length/bounds checks and produced objects are not fully understood. The right purpose statement is therefore “parses a structured Warden request/record,” not a more specific claim about the record's server meaning.

### ⬜ Selector 27 — unresolved handler

Selector27 remains unlabeled. Its handler and response fields are open.

### ⬜ Selector 28 — unresolved handler

Selector28 remains unlabeled. Its handler and response fields are open.

### ⬜ Selector 29 — unresolved handler

Selector29 remains unlabeled. Its handler and response fields are open.

### ⬜ Selector 30 — unresolved handler

Selector30 remains unlabeled. Its handler and response fields are open.

### ⬜ Selector 31 — unresolved handler

Selector31 remains unlabeled. Its handler and response fields are open.

### ⬜ Selector 32 — TCP/RC5 transport setup

Selector32 (`0x7FF697B1D000`) hashes export names to resolve `GetTcpTable`, then filters TCP table rows by a request-derived remote IPv4 address. Its recovered path also contains an RC5-32/12-compatible key-schedule setup and hands its selected output buffer to a host callback. These are local checking and output-handoff facts; static analysis has not connected this selector to a socket send/receive call or proved that its RC5 schedule encrypts the captured TCP/3724 stream. The shared dispatcher's captured RC5 response schedule is a separate finding, and neither schedule alone reconstructs the wire protocol. See the journal's 2026-10-02 manual capture/NetClient correlation for the currently confirmed packet framing and open decryption boundary.

### ⬜ Selector 33 — wait/flags path

Selector33 (`0x7FF697AB3EB0`) is an unprotected wait/flags path. The wait target and state reads are visible, but all transitions and externally observable results are not yet tied to a specific detection or server message. Preserve the distinction between waiting for local state and reporting a verdict.

### ⬜ Selector 34 — unresolved handler

Selector34 remains unlabeled. It has a dispatcher target, but its request, native calls and report/return meaning require a separate recovery pass.

## 11. Architecture overview (how the pieces fit together)

```
Server ──TCP/3724 (encrypted request)──▶ WoW network path
                                              │
                                    Wow_loader.dll  ◀── orchestrator + thread host
                                    (starts the Warden threads; their thread
                                     start addresses are inside the loader)
                                              │
                        jumps into a private 1 MB executable allocation
                                              │
                                  THE DISPATCHER  (NOT in the loader DLL)
                                  reads selector WORD, rejects >34,
                                  routes via the 35-entry case table
                                              │
                        calls the selector handler in another private
                        allocation ("protected body", decrypted on demand)
                                              │
                        handler builds report → dispatcher wraps it in the
                        common response envelope → RC5-encrypted response out
```

- The Warden threads (the ~8 WINKR suspends) are the worker loops. Their start addresses are in `Wow_loader.dll`, but the work they do happens in those private allocations.
- The dispatcher is the protocol-to-handler bridge — it lives in a private allocation (guide: `0x7FF697B93970` in that capture), not in the loader.
- The selectors are just command numbers (0–34) in the decrypted request. The dispatcher picks a branch and calls the matching handler body.

## 12. Reading a WardenDump capture (2026-10-03 live-build method)

This section records how the WardenDump toolchain was made to produce readable
Warden artifacts on the live Retail build (69933), what each artifact is, and
the exact procedure future analysts should follow. It supersedes the older
assumption that the selector dispatcher lives in a private allocation for every
session: Warden's module layout is session-specific, and in the 2026-10-03
captures the only dispatcher-like bound check found resides in the decrypted
`Wow_loader.dll` image itself.

### 12.1 Capture artifacts

Every capture folder contains:

| File | Meaning |
|---|---|
| `dump.bin` | Main PE + appended `ADCK` chunks (`dump_index.json` indexes them) |
| `dump_index.json` | chunk list: name, type, offset, size, base |
| `warden_captures.txt` | Warden allocation census + generations + region maps |
| `process_threads.txt` | per-thread Win32 start addresses and owning module |
| `warden_network_timeline.jsonl` | passive TCP endpoint timeline |
| `warden_network.pcapng` / `.etl` | PktMon full-packet capture (all NICs, 64 MiB circular) |
| `warden_dispatch_trace.jsonl` | dispatcher trace (see 12.5) |
| `modules.txt`, `memory_map.txt` | module and region manifests |
| `wow_loader_*.txt` | loader exports/functions/crypto extraction |

Chunk types: `0` decrypted `Wow_loader.dll` PE, `1` Warden executable
allocation snapshots, `3` thread start-region snapshots, `4` private memory,
`7` metadata.

### 12.2 Warden allocation layout (observed 2026-10-03)

`warden_modules.py <capture-folder>` extracts every type-1 chunk, classifies
it, and writes `warden_modules_analysis.txt` + `load_warden_modules.py` (IDA
loader that maps each chunk at its live VA). Observed classes:

* Stability (verified across the 04:53 and 10:12 captures): `warden_a009`
  is **byte-identical across sessions** (md5 `41b57943689210762c743b9a2475615b`,
  size `0x1190000`) — a session-independent module and the highest-value
  stable reversal target. `warden_a007` differs between sessions (session-
  specific content/layout). The encoded-stub counts are also stable
  (305/701 trampolines in the two 1 MiB allocations), so the stub-chain
  structure is session-independent even though the encoded targets are not.
* `plaintext-code` — immediately reversible in IDA. In the 04:53 capture:
  `warden_a007` (180 KB, base `0x21E59960000`, five push-all-style functions,
  includes a 4-case byte switch at `+0xDB08`:
  `movzx eax,[rsp+0Eh]; lea rdx,[rip+table]; movsxd rax,[rdx+rax*4]; add rax,rdx; jmp rax`)
  and `warden_a009` (17.6 MB, base `0x21FC2170000`, MSVC-style code, huge
  function count — the cached/decoded module cache candidate).
* `encoded-stubs` — Warden's MBA-obfuscated entry trampolines
  (`mov rax,imm64; push; mov rax,gs:[60h]; xor [rsp],rax; pop; ...; jmp rax`).
  The 1 MiB allocations `warden_a002`/`a003` and the 2 MiB `a008` are stub
  chains followed by zero-filled reservation; the protected bodies they
  reference are only decrypted in place while a request runs.
* `encrypted` / `mixed` / `sparse` — see the report; do not treat entropy
  alone as proof.

### 12.3 Where the dispatcher is

* The 2026-09-30 offline recovery (section 5) had the dispatcher at
  `0x7FF697B93970` in a private allocation with the 19-byte prologue
  `41 57 41 56 41 55 41 54 56 57 55 53 48 81 EC F8 07 00 00` and the WORD
  selector `0F B7 84 24 06 01 00 00`. That exact signature does **not** exist
  in the 2026-10-03 captures — the layout is session-specific.
* In the 2026-10-03 captures the only selector-like bound check is in the
  **decrypted loader image**, inside loader function `sub_19D03A0`
  (RVA `0x19D03A0`, 19,519 bytes; live VA `0x7FFA4B1F03A0` in the 04:53
  capture; extracted as `loader_dispatcher_chain_sub_19D03A0.bin`). Offsets
  within the function: `+0x975` `movzx eax, byte [rsp+66h]` (selector byte),
  `+0x97A` `mov rcx,[rsp+430h]` (request pointer), `+0x98A` `cmp eax,34`
  (`83 F8 22`) followed by `je` and a `cmp eax,0x5C` chain — an if/else
  dispatch chain, not a jump table. The loader is fully decrypted in
  `dump.bin` (chunk type 0), so this path is readable in IDA directly. It did
  not execute during the trace windows observed, so treat it as a
  setup/validation path until a runtime trace proves otherwise.
* The per-request dispatcher body was **not resident in any captured
  snapshot** in the 04:53 capture (the 1 MiB allocations held only stub
  chains). To recover it, either capture longer/at different moments so a
  snapshot catches a decrypted body window, or apply the body XOR transform
  below once the session key material is identified.

### 12.4 Protected-body transform (for future decryption)

From the KB journals the body header/decrypt format is:

```
header + 0x00 : (varies)
header + 0x01 : dataSize (DWORD)
header + 0x0B : checksum
header + 0x0F : payload length
header + 0x13 : encrypted flag
header + 0x14 : key material (key_length bytes)
key_length    = dataSize - 15
body_start    = header + key_length + 20

for (p = body_start; p < body_end; ++p)
    *p ^= key[(body_end - p) % key_length + 15];
```

The key material is session-specific and lives in the decoded body header
(and/or the loader's decoder). The 2026-10-03 captures did not contain a
resident encrypted body with its header, so this transform was not validated
against them. When a future capture contains one, feed it to the same routine
and verify by checking that the result decodes as x64 prologues.

### 12.5 Runtime dispatcher trace: what was tried and why

* Hardware breakpoints (DR0–DR3 + VEH) on the selector site: **Warden detects
  armed DRs on its own threads and raises a deliberate security crash**
  (`0xC00000E5`, `ExceptionType: Security Crash`, from inside
  `Wow_loader.dll`). Do not use DRs on Warden threads.
* `PAGE_GUARD` on Warden allocation pages: caused an unhandled
  `0x80000001 GUARD_PAGE` on the dump-worker thread when the game's own
  decryptor read a guarded page from a foreign thread. Never place guards on
  the private Warden allocation pages.
* Guard/trap-flag tracing of loader thread functions and an execute-access-
  violation trigger for encrypted pages: safe (no crash) but recorded zero
  runs — the protected bodies are decoded explicitly by a wrapper rather than
  by page faults, so neither trigger fires.
* The trace that does work safely is the guard-page + trap-flag execution
  tracer on the loader thread functions; it is in place but produced no runs
  for the same explicit-decode reason.

Practical conclusion: for this build, do **not** expect live selector capture.
Capture the dump + `warden_network.pcapng`, then recover bodies offline with
12.2–12.4. The network pcapng contains the encrypted TCP/3724 Warden traffic;
the RC5 response schedule is described in section 4.3 and selector 32 notes.

### 12.7 Decoding Warden's encoded entry stubs (2026-10-03 method)

Warden module allocations (`warden_a002`/`a003`, 1 MiB each) are NOT code
bodies — they are tables of MBA-encoded entry stubs:

    mov rax, imm64            ; encoded constant
    [add/sub/xor/rol/ror/...] ; mixed boolean-arithmetic chain
    push rax
    mov rax, gs:[60h]         ; PEB (thread-independent)
    xor [rsp], rax            ; target = chain(imm) ^ PEB
    pop rax
    jmp rax

Recovery procedure (automated in `tools/decode_warden_stubs.py`):

1. Find the PEB from the captured private memory: every TEB page has
   `TEB+0x30 == Self` and `TEB+0x60 == PEB`. In the 10:12 capture the PEB was
   `0x7F2A1B000` and `PEB+0x18` (ProcessHeap) was `0x7FFB01652880`.
2. Emulate each stub's arithmetic chain over the imm64 constant and XOR the
   result with the PEB; the chain only uses mov/add/sub/xor/rol/ror/inc/dec/
   push/pop and `gs:[60h]`, so a small interpreter decodes every stub.
3. `python tools/decode_warden_stubs.py <capture-folder>` writes
   `stub_targets.json`.

Results for the 10:12 capture (1006 stubs decoded):

* `warden_a002` (305 stubs) — all targets are system DLL imports
  (ntdll/kernelbase). This is the module's obfuscated import table.
* `warden_a003` (701 stubs) — 698 system imports plus **three loader call
  gates**:
  - `0x7FFA538B6A60` (loader RVA `0x4F6A60`)
  - `0x7FFA5425CF40` (loader RVA `0xE9CF40`)
  - `0x7FFA5435C350` (loader RVA `0xF9C350`)
  These are the Warden module's calls into the loader and are the entry
  points to the protected-body decode / call / re-encrypt machinery.
* The three call gates are control-flow-flattened (79 KiB stack frame,
  cmp/je state machines, MBA-encoded global reads). Hex-Rays fails on them
  without the bounded-flag-graph repair workflow documented in the KB
  journals (reversing-warden.md OLD-06/OLD-08). Each one is a multi-session
  manual recovery; do not expect a clean F5 view.

Also note: the allocation bases themselves are NOT stored as raw pointers in
`wow_loader.data` — the loader keeps them encoded, so pointer-scanning the
data segment finds nothing. Stub emulation is the reliable way to recover
module-to-loader edges.

### 12.8 Runtime evidence from Warden thread stacks (2026-10-03)

The dispatcher/handler bodies decrypt in place only while a request runs, so
allocation snapshots usually miss them. The reliable static evidence left in
every dump is the Warden threads' stacks at Stop time.

`tools/mine_warden_stacks.py <capture-folder>` automates this:

1. parse `process_threads.txt` for threads whose Win32 start address lies in
   `wow_loader.text`,
2. find each thread's TEB in the type-4 private-memory chunks
   (`TEB+0x30 == Self`, `+0x48` TID, `+0x08/+0x10` stack base/limit),
3. scan the captured stack for qwords pointing into the loader or any Warden
   allocation,
4. write `warden_stack_evidence.json`.

Findings for the 10:12 capture:

* The Warden work loop is `sub_7FFA5538FA9F` (loader RVA `0x1FCFA9F`). It
  writes `gs:0x2E0`/`gs:0x2D8`, then calls the module through the encoded
  stub table: `call sub_17CE06303DF` (an `a002` stub), which decodes to
  `ntdll!0x7FFB015A3BD0` (a wait primitive). Other stub calls on the stacks
  decode to `kernelbase` wait functions — the Warden threads park in waits
  between requests, exactly as expected.
* Warden threads with loader start `0x7FFA53DDCCF0` (TIDs 7380/22136/26528/
  29240) show deep loader call chains ending at the work loop. Key frames:
  `0x7FFA54AFD322` (`sub_7FFA54ADE073`), `0x7FFA548D6AE0`
  (`sub_7FFA548CF471`), `0x7FFA55027B4C` (`sub_7FFA55027AD9`),
  `0x7FFA553B9B0C` (`sub_7FFA553B9AF0`), `0x7FFA55390EB8`
  (`sub_7FFA55390D9C`). These are the loader functions the request path
  traverses; the body decoder is reachable from them.
* To catch the dispatcher itself: capture while requests are flowing and
  stop mid-activity, then re-run the stack miner. A stack frame inside a
  decrypted allocation (`alloc` class) is the smoking gun; dump that
  allocation range from the same snapshot.

### 12.9 The .eid body store (2026-10-03)

The loader's `.eid` section (5.5 MiB, `wow_loader.eid` in IDA) is high-entropy
ciphertext (entropy ~6.88) and holds the Eidolon-encrypted Warden code pages:
the dispatcher/handler bodies decrypt in place only when executed, so every
static snapshot shows ciphertext.

Evidence in the 10:12 capture:

* Five loader code sites reference `.eid` offsets. Only one decodes as a real
  call: `sub_7FFA549D17D9` (loader RVA `0x16117D9`) executes
  `E8 01 00 00 01` at `+0x85` → `call wow_loader.eid+0x3D1864`. The other
  four are inside misaligned obfuscation junk (decoy bytes).
* `.eid` pages are READABLE at rest (the original loader dump copies them
  raw), so the dumper's `needsProtect` gate never gadget-decrypts them.

Dumper change: `DumpWowLoader` now runs a dedicated `.eid` gadget pass after
the main section loop (exact section-name match; a prefix match would hit the
32-byte `.eidsig` section instead, which produced the 11:37 capture's
`0 pages attempted, 1 skipped/failed` log).

The 11:40 run confirmed `.eid` holds identical ciphertext bytes across
captures (disk-encrypted at rest, entropy ~6.88) and that the pages are
GUARDED at rest: the pass reported `0 attempted, 1408 skipped`. The pass now
mirrors the loader `.text` path exactly — when a page is NOACCESS/0/GUARD it
temporarily sets `PAGE_EXECUTE_READ`, applies the read gadget 512 qwords at a
time, then restores the original protection. A detail log line
(`Eidolon .eid pass detail: ...`) reports the exact failure reason if any
pages are skipped. The 11:48 run settled it: the pass executed all 1408 pages with zero
failures, and the candidate file equals the disk ciphertext byte-for-byte
(entropy 6.882). The game's DR handler does NOT decrypt `.eid` pages on
foreign-thread reads — the read-gadget route is closed for `.eid`.

The tracer therefore no longer tries to decrypt `.eid` itself. `.eid` pages
are guarded by the GAME at rest and are decrypted by the game's own handler
on execute. `RefreshWardenTraceTargets` now adds the whole `.eid` section as
a `gameGuarded` trace target: the VEH observes the game's execute guard
faults (ExceptionInformation[0]==8), starts a single-step run with TF set,
and returns CONTINUE_SEARCH so the game's handler decrypts and resumes. The
first instruction of the decrypted `.eid` code then single-steps into our
handler and the run records RIP offsets relative to the `.eid` base. No DRs,
no guards of our own, no gadget calls — pure observation of faults the game
raises itself. Runs appear in `warden_dispatch_trace.jsonl` as `exec_run`
lines whose step RVAs are `.eid` offsets.

The 11:53 capture (3.5 minutes, login + world entry, 16 census snapshots)
armed 8 targets including `.eid`, survived without a crash, and still
recorded `exec_runs: 0`. Combined with the earlier evidence this pins the
mechanism: the loader uses an EXPLICIT decode wrapper for `.eid` pages — no
execute fault, no guard fault, no DR — so passive fault observation can never
fire. The `.eid` bytes are also byte-identical across every session
(md5 `3ea72b3cc0e177b6` for the 5.5 MiB section), so the cipher uses a fixed
per-build key, not per-session material.

That reduces the remaining static path to exactly one target: the explicit
`.eid` decode wrapper in the loader (start from the request-path frames
`sub_7FFA54ADE073`, `sub_7FFA548CF471`, `sub_7FFA55027AD9` and the three
call gates at RVAs `0x4F6A60`, `0xE9CF40`, `0xF9C350`). It is
control-flow-flattened and requires the KB journals' bounded-flag-graph
repair workflow (OLD-08). With the wrapper recovered, `.eid` can be
decrypted offline because the key is fixed per build. For every committed, non-guarded `.eid` page it
temporarily sets `PAGE_EXECUTE_READ` and applies the loader read gadget
(`48 8B 01 C3`) 512 qwords at a time, writing the result to
`wow_loader_eid_decrypted.bin` in the capture folder. The main `dump.bin`
still holds the exact captured bytes. If the game's DR handler decrypts these
pages on read, the candidate file is plaintext code and can be loaded into
IDA at `wow_loader.eid`'s base. If the handler returns the raw ciphertext,
the candidate equals the captured bytes — in that case the bodies can only
be recovered by reversing the Eidolon key schedule (the KB journals' "OLD-08
permutation-plus-shift decoder" notes) or by execution-triggered capture.

### 12.10 The .eid layout and the decode-wrapper campaign (2026-10-03)

Deep static pass on the 10:12 IDB. Findings that bound the remaining work:

1. **The loader's CFF state machine continues inside `.eid`.** A raw scan of
   `wow_loader.text` for `E8/E9/0F8x` whose target lands in `.eid` finds
   **596 cross-section edges**. The `.eid` code blocks are decrypted in place
   right before the jump (the loader-side block before the edge does byte-MBA
   and then jumps). Real example: the block chain starting at
   `sub_7FFA549E5CDE` (RVA `0x1625CDE`) does byte-level MBA
   (`movzx` + `and/or/not/shl` + `lea reg,[reg*8]`), ends at `0x549E5FEA` with
   `E9 44 20 C2 00` → `jmp .eid+0x8033`.
2. **`.eid` is not uniformly encrypted.** Per-4 KiB entropy profile:
   `0x00000-0x01000` header (plain), `0x01000-0x0D000` mixed,
   `0x0D000-0xB0000` encrypted, `0xB0000-0x1B0000` encrypted,
   `0x1B0000-0x510000` mixed, `0x510000-0x514000` encrypted,
   `0x514000-0x577000` mixed, `0x577000-0x580000` plain tables.
   Encrypted total ≈ 1.72 MiB; mixed ≈ 4.0 MiB.
3. **`.eid` header at offset 0:** 176 bytes of high-entropy material, then at
   `0xB4` a 36-byte field, `00 00 00 00`, then `E9 0A 00 00` (count 0xAE9 =
   2793 records). Plaintext RVA tables begin around `0x8000`
   (`0x22EE4201 + n*0x100` style entries pointing into the main image).
   The 36-byte field at `0xB4` and the 176-byte blob at 0 are the prime key
   candidates for the encrypted regions.
4. **Known-plaintext anchors are now available in bulk:** every one of the
   596 edge targets, when decrypted, must begin with a state-machine block
   (`cmp eax,imm32` = `3D ?? ?? ?? ??`, or `mov eax,imm32` = `B8 ?? ?? ?? ??`).
   That is enough to break a per-page or repeating XOR cipher and to validate
   a permutation+shift candidate.

The 12:32 capture (VEH re-asserted at chain head every census pass,
confirmed in the log) still produced `exec_runs: 0` across 51 census
snapshots of active Warden churn. Conclusion: the `.eid` execute path raises
NO user-mode fault — the decode is fully explicit. VEH ordering, AV-trigger
observation and guard observation are all ruled out. Any runtime capture of
the decrypted `.eid` code must come from below the user-mode exception
machinery: kernel hooks or EPT page-fault interception (Option B).

Write-trap instrument (the replacement for the VirtualProtect hook) is now
implemented: `native/eid_writetrap.h`. The loader has NO hookable import
stubs (verified: zero MBA stubs, zero valid IAT entries, zero import pointers
in `.data`, PE headers wiped to 0xFF at runtime), so VirtualProtect cannot be
intercepted. Instead the instrument flips every committed `.eid` page to
PAGE_READONLY at install; the inline MBA decoder's first store faults, our
VEH makes the page writable, sets TF, and single-steps the decoder until RIP
enters the `.eid` page — the instant the page is fully decrypted — and
snapshots it to `eid_writetrap_snapshots.bin` /
`eid_writetrap_index.json`. One snapshot per page per capture; the game runs
single-stepped for the length of one decode loop (milliseconds). Page
protections are altered, so Warden may notice.

User-mode edge hook (the last pre-kernel option) is now implemented:
`native/eid_hook.h` scans the loader for E8/E9 sites targeting `.eid`, patches
up to 8 of them with 128-byte trampolines that snapshot the freshly decrypted
4 KiB page into `eid_hook_snapshots.bin` (index in `eid_hook_index.json`)
before jumping to the original target. Known-real RVAs from the 10:12 IDB
(`0x1625FEA`, `0x161185E`, ...) are prioritised. A VEH fixup makes
execute-only/guarded `.eid` pages readable when a trampoline read faults.
This patches loader `.text` bytes and may trip Warden integrity checks; it
is an experiment, not a stealthy method.

Attack plan for the cipher (static, no game running):

1. Extract the 1.72 MiB of encrypted regions and the 596 anchors.
2. Hypothesis A: per-page XOR with the 36-byte header field (test: decrypt
   page 0xD000, check anchor `3D` at the block starts).
3. Hypothesis B: per-byte repeating XOR (recover key via anchor bytes).
4. Hypothesis C: permutation-plus-shift (OLD-08); use the 596 anchors to
   recover the permutation for each residue class.

The decode wrapper itself (`sub_7FFA549E5CDE` neighborhood) shows the real
cipher work is split between loader-side MBA blocks and `.eid`-resident
blocks, so the key schedule is in the mixed/encrypted region; the header
blob is the most likely key seed.

### 12.11 Kernel / NPT plan (if the user-mode edge hook fails)

Host is AMD, so EPT = **NPT (nested page tables, SVM)**.

Goal: capture `.eid` pages in their decrypted execution window without any
user-visible artefact (no DRs, no `.text` patches, no VEH).

**Tier 0 — user-mode protection-change hook (do this before any kernel work):**
The explicit decode wrapper must call `VirtualProtect`/`NtProtectVirtualMemory`
to make a decrypted `.eid` page executable before jumping into it. The loader
calls imports through its own encoded stub table (same `mov rax,imm;
gs:[60]; xor [rsp]; pop; jmp rax` form as the Warden modules — our emulator
already decodes it). Plan: decode the LOADER's stub table, find the stubs that
resolve to `VirtualProtect`/`NtProtectVirtualMemory`/`NtProtectVirtualMemory`,
patch those stubs with trampolines that call the real API and, when the range
is inside `.eid` and the new protection is executable, snapshot the page on
return. No `.text` patches (only stub bytes), no faults to handle.

**Tier 1 — kernel driver (no hypervisor):**
Test-signed WDM driver (`bcdedit /set testsigning on`, self-signed cert).
- `KeStackAttachProcess` + poll `.eid` pages: unreliable (execution window is
  microseconds) — skip unless nothing else works.
- Kernel hook on the syscall path for `NtProtectVirtualMemory`: needs a
  hypervisor or an unsupported SSDT hook (PatchGuard) — not recommended on
  modern Windows.
- Better kernel use: snapshot pages on demand from a usermode request when
  the usermode side signals "now" (still racy).

**Tier 2 — NPT/EPT thin hypervisor (recommended, AMD SVM):**
Base: HyperPlatform (supports Intel VT-x and AMD SVM/NPT) or a minimal SVM
driver. Steps:
1. Test-signing on; enable SVM in BIOS (usually already on).
2. Virtualize the system (VMRUN loop), identity-map guests, keep a minimal
   #VMEXIT handler.
3. Locate the target process' CR3; walk its guest page tables to translate
   the `.eid` VA range to guest physical pages (or, simpler, virtualize only
   the target process via an alternate address-space switch — HyperPlatform
   virtualizes the whole system, so use the current CR3 while the game runs).
4. In the NPT for those pages, set the **NX bit (bit 63)** and make the pages
   supervisor/read-only as needed, so the first instruction fetch after the
   game's decrypt faults with #NPF (exitcode 0x400).
5. In the #NPF handler: read the guest physical page (it is decrypted at that
   instant), copy it to a capture buffer, clear NX so execution proceeds,
   and re-arm NX on the next VMEXIT/CR3 write/once the page is re-encrypted
   (re-arm after a short single-step or on the next exit).
6. Expose captured pages through the WardenDump GUI/MCP (`eid_npt_snapshots`).
7. This is invisible to anything running in the guest, including Warden's
   user-mode integrity checks, DR scans, VEH ordering, and `.text` CRCs.

**Tier 3 — patching the protections (the "no crash" thought):**
If a capture crashes with the Warden security error (`0xC00000E5`) after any
of the above, the crash is a deliberate integrity response. Options:
- Locate the integrity check that raises it (the `0xC00000E5` fail-fast path)
  and neutralize it from kernel (write to its decision variable) during the
  capture, restoring afterwards.
- Or run the edge-hook trampolines as one-shot: restore the original bytes on
  the first hit so the patched window is a single instruction fetch.
- Under the NPT hypervisor, none of this matters — the guest cannot see the
  trap, so no integrity response is triggered.

Decision ladder: Tier 0 first (cheap, user-mode). If it fails or crashes,
skip Tier 1's polling and go straight to Tier 2 (NPT). Tier 3 only if a
crash appears in a capture that must be saved.

### 12.6 Minimal workflow for future analysts

1. Run WardenDump with Packet capture enabled; let the target log in and run
   the activity of interest; Stop. The GUI now auto-runs
   `warden_modules.py` on the capture folder after a successful dump (the
   console logs `Warden module extraction launched`); if Python is missing,
   run it manually.
2. `python tools/warden_modules.py <capture-folder>` — extracts and classifies
   every Warden allocation (same step as the auto-run, safe to repeat).
3. Load `dump.bin` in IDA; run `load_warden_modules.py` to map the
   plaintext/stub allocations at their live VAs; the loader is already mapped
   as chunk 0.
4. For selector semantics, start from the 35-entry dispatcher knowledge in
   sections 5–6 and map it onto whatever session-specific form is present
   (jump table in the 09-30 capture; cmp/je chain at loader `0x19D0D2A` in
   the 10-03 captures).
5. Keep the trace checkbox off unless a specific decrypted site is known;
   the trace header records what it armed and what it saw.
