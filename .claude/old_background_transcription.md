# Background Transcription System

## Architecture

Single **worker thread** with a `queue.Queue` (thread-safe FIFO) that processes audio recordings asynchronously while the UI continues.

## Key Files
- `services/transcription_worker.py` — worker thread + queue
- `data/response_list.py` — linked list for ordered responses
- `data/session_manager.py` — session/file management
- `services/audio_recorder.py` — Whisper model loading

## Flow

1. **Startup**: App loads Whisper model (medium, auto-detects CUDA), starts worker thread waiting on the queue.

2. **During processing cycles**: User records a response → `add_audio(file, cycle, session_path, response_list)` puts a dict on the queue → UI **immediately** moves to FeedbackScreen (no blocking).

3. **Worker loop** (`_process_queue`):
   - Blocks on `queue.get(timeout=1.0)` in a loop
   - For each item:
     - **Load**: Reads WAV via `scipy.io.wavfile`, converts to float32, mono, resamples to 16kHz
     - **Transcribe**: Runs Whisper (`fp16=True` on GPU, `False` on CPU, `language="en"`)
     - **Store**: Appends result to `ProcessingResponseList` (linked list with `head`/`tail`/`count`), saves to `responses.json` (encrypted)
     - **Cleanup**: Marks audio as transcribed in session metadata, deletes the WAV file

4. **Shutdown**: Worker drains remaining queue items before exiting (`while self.running or not self.audio_queue.empty()`)

## ProcessingResponseList (Linked List)

`ResponseNode` holds `cycle_number`, `response_text`, `timestamp`, `next`. List appends to tail in O(1). Serializes to JSON then encrypts.

## Session Management

Each session gets a timestamped directory with:
- `metadata.json.enc` — tracks each audio file's status (`pending` → `transcribed`)
- `responses.json.enc` — all transcriptions
- Temporary WAV files (deleted post-transcription)

## Resume Support

`get_pending_sessions()` scans all session dirs for files with `status=pending`, re-queues them via `add_pending_audio()`.

## Key Details

| Aspect | Detail |
|---|---|
| Queue | `queue.Queue()`, FIFO, thread-safe |
| Engine | Local OpenAI Whisper (not API) |
| Model | Medium (769M params) |
| GPU | Auto-detect CUDA, fp16 |
| Audio | WAV → float32 mono → 16kHz resample |
| Threading | Single daemon-like worker thread |
| Storage | Linked list → JSON → encrypted |
