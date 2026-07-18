# Spec: Hybrid Target-Identification Flow

Synthesized 2026-07-18 from a full design interview. This document records *what* is being
built and *why*; the implementation plan (build order, file layout) lives with the work
itself. When this spec and the code disagree after implementation, trust the code and fix
the spec.

## Problem Statement

Identifying an EMDR target image today means a long free-form conversation with an
ElevenLabs voice agent. That conversation is billed per minute, routinely ran 15–20
minutes (~$2 per target, with retries in practice), had no duration or silence caps, and
misbehaved: it ended after the first body sensation, skipped direct questioning about the
target image, and gave sections no introductions. The result was expensive *and*
clinically unreliable — and the cost model cannot scale to the intended future of a
low-cost nonprofit service.

## Solution

Keep the live agent only for the one genuinely conversational task — negotiating the
target image until the user says "yes, that's exactly it" — and run every other
assessment stage with machinery the app already owns at near-zero marginal cost:
pre-cached TTS questions and interludes, local whisper transcription, small LLM
"adequacy check" calls with bounded follow-ups, rating screens, and an on-screen
sectioned review where the user corrects anything the AI got wrong before the cue-in
script is generated automatically.

The stage order follows the standard Shapiro assessment: image → negative cognition →
positive cognition → VoC (1–7) → emotion naming → SUD (0–10) → body sensations.

Worst-case cost per target drops from ~$2 uncapped to a hard ~$0.70 ceiling (8-minute
agent cap), typically ~$0.35; everything outside the call is cached, local, or costs
fractions of a cent.

## User Stories

1. As a user, I want a calm spoken introduction before the work begins, so that I start
   the identification settled rather than cold.
2. As a user, I want to be guided into the image with "eyes closed or a soft gaze"
   language before the agent conversation starts, so that I'm in the right state to
   visualize.
3. As a user, I want to negotiate my target image with a responsive voice agent, so that
   the description captures *exactly* what I see, not an approximation.
4. As a user, I want the agent to read my final image back to me and get my explicit
   agreement before hanging up, so that I know what was captured.
5. As a user, I want the agent conversation to be gently steered toward convergence and
   hard-capped in length, so that a session can't silently become expensive.
6. As a user, I want a walked-away or stuck call to end itself after a silence timeout,
   so that the meter never runs on an empty room.
7. As a user, I want each assessment stage introduced by a short spoken interlude, so
   that transitions feel guided rather than abrupt.
8. As a user, I want to answer each stage question by speaking and pressing a key when
   done, so that the flow works without typing.
9. As a user, I want vague answers met with at most a few gentle, context-aware
   follow-up questions — offering example cognitions from the EMDR literature when
   relevant — so that I'm helped toward a usable answer without feeling interrogated.
10. As a user, I want the follow-up questions to know what I've already said (image,
    earlier answers), so that the conversation feels continuous, not like separate
    forms.
11. As a user, I want the wait after each answer filled with a grounding breath prompt
    and a breathing-circle animation, so that processing time feels like part of the
    therapy rather than dead air.
12. As a user, I want a visual cue (the background subtly speeding up) while the app is
    thinking, so that I know it's working without reading text.
13. As a user, I want to rate VoC on a 1–7 screen and SUD on a 0–10 screen, so that
    ratings are quick and unambiguous.
14. As a user, I want a final on-screen review of everything captured — image,
    cognitions, emotion, sensations, ratings — section by section, so that I can verify
    it before it becomes my cue-in script.
15. As a user, I want to edit any section's text or re-record my answer for just that
    section, so that mistakes are cheap to fix.
16. As a user, I want sections that the AI is unsure about (unconfirmed image, stages
    that hit the follow-up cap) visibly flagged in the review, so that my attention goes
    where it's needed.
17. As a user, I want confirming the review to automatically generate my cue-in script
    and audio, so that "identification done" means "ready for a session".
18. As a user, I want to be able to press Escape at any point after the agent call and
    resume later from where I left off, so that stopping mid-flow (by choice or crash)
    never loses my answers or costs a second agent call.
19. As a user, I want my agent-call transcript saved to disk the moment the call ends,
    so that even an extraction or network failure afterward can never lose the
    conversation I paid for and emotionally invested in.
20. As the maintainer, I want every piece of spoken/LLM prose (agent prompt, first
    message, check prompts, extraction prompt, cue-in prompt, interlude/question/bridge
    scripts) in editable markdown/text files with clearly sectioned structure, so that I
    can tune tone and pacing without touching code.
21. As the maintainer, I want the agent's ritual-ending behavior in its own labeled
    prompt section, so that I can adjust the confirmation ritual directly.
22. As the maintainer, I want the follow-up cap as a config value, so that strictness is
    a one-line change.
23. As the maintainer, I want the live-agent step behind a clean seam (transcript in →
    confirmed description out), so that the vendor can be swapped later without touching
    the rest of the flow.
24. As the maintainer, I want the old flow preserved in a legacy folder, so that it's
    inspectable without git archaeology.
25. As a researcher, I want the full per-stage Q&A exchanges preserved in the assessment
    record, so that how an answer was reached is reviewable later.

## Implementation Decisions

- **Platform**: stay on ElevenLabs for the live agent (one consistent voice across agent,
  cached audio, and runtime TTS: Addison 2.0). The agent sits behind a seam whose
  contract is platform-agnostic: a transcript goes in, one LLM extraction call returns
  the confirmed image description + target slug.
- **Extraction, not in-call tools**: the agent prompt enforces a ritual ending ("Here is
  your final image: …" + verbal agreement + end call). A post-call LLM text call
  extracts the final description from the transcript. No custom WebSocket tool plumbing.
- **Caps**: server-side max call duration ~480 s and silence timeout ~90 s. A capped-out
  call still salvages the best-draft image, marked unconfirmed for the review screen.
  The app's own safety timeout stays above the server cap so the graceful
  conversation-ended path always wins.
- **Target folder is created right after extraction** (slug comes from the extraction
  call), so all later checkpoints have a home. The transcript is written to the target
  folder *before* extraction runs.
- **Assessment record**: one JSON per target holding image (+confirmed flag), per-stage
  answer/attempts/flagged/exchanges, voc, sud, completed. Main thread is the sole
  writer; every confirmed piece is written the moment it exists (same durability pattern
  as session records).
- **Checks**: one LLM call per answer judging adequacy against the stage's prompt file
  plus (for cognition stages) the textbook NC/PC examples list in `emdr_knowledge/`;
  responses follow a fixed JSON contract (adequate / refined_answer / followup). The
  running context accumulates across stages. Cap: `IDENT_MAX_FOLLOWUPS` (default 3) per
  stage; hitting the cap accepts the best answer and flags the stage. Unparseable LLM
  output fails soft (replay the question). Empty whisper output replays the question
  without an LLM call.
- **Stage answer audio** rides the existing whisper worker via a new raw-job path with
  callback routing, in a separate queue directory so the session crash-recovery filename
  contract is untouched.
- **Resume**: a minimal marker file records that an identification is ongoing and where;
  progress truth lives in the assessment JSON (first incomplete step wins). The menu
  offers "Resume Identification" alongside the existing session resume. The agent call
  itself is not resumable — interrupted calls are redone.
- **Rating screens** come from the existing rating factory, parameterized (range,
  default, anchors, callbacks) with the current pre/post behavior preserved as presets.
- **Review screen** shows sections with badges (unconfirmed image, flagged stages);
  editing uses the established append-style text editing; re-recording a section re-runs
  that stage. Confirm marks completed, clears the marker, and auto-triggers cue-in
  generation, which now consumes the structured assessment and the known slug.
- **Old flow replaced outright**; its screen and agent prompt/workflow files are copied
  to `legacy/`.

## Testing Decisions

- Test external behavior at the seams: assessment JSON contents after each step,
  marker/resume behavior across kills, transcription routing (raw jobs vs session jobs),
  check contract parsing including malformed input.
- Prior art: headless LÖVE test apps in the scratchpad (window disabled) driving modules
  directly, plus `timeout 6 love .` boot checks — the pattern used for the session-record
  and resume work.
- Anything involving microphone, live agent audio, or perceived audio quality is
  user-live-tested at explicit gates (skeleton stage, vague-answer follow-ups, full
  chain, live agent call including a deliberately capped-out call, full end-to-end run
  plus a processing session on the produced target).
- Regression guards: existing pre/post rating screens must look and behave identically;
  session crash-recovery must survive a planted legacy-named WAV; T-key cue-in from an
  old transcript must keep working until the legacy path is removed.

## Out of Scope

- Switching the live agent to another vendor (seam exists; decision deferred until scale
  is real).
- Multi-user/distribution concerns (accounts, key management, packaging).
- Regenerating the wdyn / notice_that soundbites or any processing-session audio.
- Changes to the processing-session flow, its records, or its resume.
- The EMDR-fidelity review skill (separate TODO item; this spec's prompts are inputs to
  it later).
- Whisper hallucination filtering on silent recordings (separate open item).

## Further Notes

- Cost model at time of writing: ElevenLabs agents ~$0.08–0.10/min (+LLM); the cached
  TTS is a one-time per-file cost; whisper is local; check calls are fractions of a
  cent. OpenAI Realtime (mini) measured ~$0.02–0.04/min in third-party tests if a swap
  is ever wanted — at the cost of a protocol rewrite and losing the single-voice
  experience.
- The audio-generation script's hardcoded voice did not match the app voice (Sarah vs
  Addison); fixed as part of this work so all cached audio is generated in the app
  voice.
- The 90 s silence timeout interacts with contemplative pauses; the agent prompt's
  pacing section invites the user to take their time, and the number is expected to be
  tuned after live testing.
