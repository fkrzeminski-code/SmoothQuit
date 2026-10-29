# SmoothQuit 1.6.4 — observation recovery

Reviewed on 2026-10-29 with Ponytail Full. This patch changes observation recovery, adds focused regression coverage and diagnostic messages, and preserves the existing native interface, rules and window animations.

## Evidence and fix

The installed 1.6.3 diagnostics showed WhatsApp returning an empty AX snapshot while one remembered window continued to veto Quit. It also showed transient AX cannotComplete errors. An empty snapshot does not establish that the remembered window is destroyed: it may belong to another Space. Disable / Enable clears all watches, explaining why it can remove this symptom without identifying which reference was stale.

The old ledger could retain a dead reference indefinitely if its destruction notification was missed. The new recovery probes AXRole on a retained reference absent from discovery, accepting only AXError.invalidUIElement as explicit invalidation. A valid response, timeout, cannotComplete or any other error retains the veto. Recovery cancels any existing countdown and never arms Quit. A subsequent confirmed normal-window destruction starts the full configured delay and all ordinary verification checks. During a fresh destruction callback, other references can be recovered before that close is processed; the closing reference itself is excluded from cleanup.

A second persistent state was found in code: after an accepted Quit request, focus/activation reads were suppressed while waiting for process exit. If the app stayed alive and its next normal window lacked a creation notification, that state could suppress subsequent closes. Focus/activation reads now continue, and a complete successful snapshot containing a normal window resumes monitoring. An empty snapshot or auxiliary save dialog cannot do so. No repeated Quit or force-quit fallback was added.

This is targeted recovery, not proof that every historical failure had the same cause. The installed diagnostic ledger does not retain the actual invalidation error of the old reference.

## Validation

- The deterministic regression repeats 100 cycles on the same CloseGate, recovering a stale identity while preserving a different Space's window and the full delay.
- Another regression verifies that recovering a stale identity during a countdown cancels it rather than promoting it to Quit.
- AX classification tests retain references on cannotComplete, API-disabled, no-value, unsupported-attribute and generic errors, and accept only invalidUIElement.
- Full ordinary suite: 76 tests, 67 passed, 9 opt-in interactive tests skipped, zero failures.
- One live production-Monitor test completed three WhatsApp main-window closes on the same Monitor instance, with no Disable / Enable or monitor restart. It verifies three standard Quit requests and three observed process exits.

| Cycle | Quit request after close | Process exit after close |
| --- | --- | --- |
| 1 | 0.559 s | 0.894 s |
| 2 | 0.528 s | 1.708 s |
| 3 | 0.524 s | 16.004 s |

The installed monitor was temporarily disabled to isolate this test, then restored to enabled. The first close used native Command-W. The user performed the second and third closes after UI automation's full WhatsApp accessibility-tree read was rejected because it would include chat content. No conversation was opened or sent. The successful test uses only production window metadata and request/exit diagnostics; there is no recorded chat content in its report.

An initial live attempt timed out while UI automation was launching/observing the application and did not complete its close sequence. It is not counted as a pass. The operator test timeout was extended to 600 seconds; production Quit delay remains 0.5 seconds. The final three-cycle test passed in 118.3 seconds. The third process exit was slow despite a timely Quit request; SmoothQuit did not force termination.

Live testing used the production Monitor compiled into the authorized XCTest host, not the final packaged app. The test verifies repeated operation across application launches; it does not deliberately drop a real AX notification or reproduce hours of operation. Stale-reference recovery is covered deterministically. Calendar, Excel, other Spaces, physical Intel hardware and a new final-bundle Accessibility grant were not exercised in this patch. Prior release results remain historical evidence, not new passes.

## Ponytail review

- Existing serial queue and AX/NSWorkspace events retained; no periodic resets, polling service, dependency or extra permission.
- Public AX error classification is separate from the minimal ledger operation; recovery itself cannot issue Quit.
- Probes use the existing IPC timeout/read budget. Unvisited or ambiguous identities remain vetoes.
- Pending-token, process-identity, settings, event-revision, AX and CoreGraphics checks remain in the final Quit path.
- Diagnostics distinguish recovery, cancelled verification and resumed observation; both English and Polish resources are covered by localization tests.
- Release packaging builds arm64 and x86_64, verifies the ad hoc signature and DMG, and leaves /Applications untouched. Local signing still requires reauthorizing Accessibility after some updates; this patch does not change that limitation.
