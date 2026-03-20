Plan: Audio Generation Script + "What did   
 you notice?" Screen                         
                                             
 Context

 The EMDR3 app needs two things:
 1. A standalone script to pre-generate
 multiple variants of TTS audio files via
 the ElevenLabs API (e.g.
 what_noticed_1.mp3, what_noticed_2.mp3,
 what_noticed_3.mp3), saved to
 resources/audio/ — played randomly at
 runtime so it sounds less robotic
 2. A new noticed screen that follows the
 oscillating screen — displays "What did you
  notice?" and plays a randomly selected
 variant of the pre-generated audio

 Step 1: Create testing/conf.lua — headless
 Love2D config

 Disable the window so the generation script
  runs as a CLI tool:

 function love.conf(t)
     t.title = "EMDR3 Audio Generator"
     t.modules.window = false
     t.modules.graphics = false
     t.modules.audio = false
     t.modules.keyboard = false
     t.modules.mouse = false
     t.modules.timer = true
     t.modules.thread = false
     t.modules.joystick = false
     t.modules.physics = false
     t.modules.touch = false
     t.modules.video = false
 end

 Step 2: Replace testing/main.lua — audio
 generation script

 Currently a 3-line placeholder. Replace
 entirely. Run via love testing/.

 Logic (all in love.load(), then
 love.event.quit()):
 1. Compute project root:
 love.filesystem.getSource() returns the
 testing/ path, go one level up
 2. Set package.cpath to find lib/https.so
 from project root
 3. Parse .env from project root using
 io.open() (can't use love.filesystem.read
 since source dir is testing/)
 4. Define entries table with a variants
 count per phrase:
 local entries = {
     { base = "what_noticed", text = "What
 did you notice?", variants = 3 },
     -- future entries here
 }
 5. For each entry, generate variants number
  of files by calling the API multiple
 times. Each call to ElevenLabs with the
 same text produces slightly different audio
  (natural variation in the model). Save as
 {base}_1.mp3, {base}_2.mp3, {base}_3.mp3.
 6. POST to
 {base_url}/text-to-speech/{voice_id} using
 https.request() — replicates
 modules/tts_thread.lua:29-46
 7. Write binary MP3 response to {projectRoo
 t}/resources/audio/{base}_{n}.mp3 via
 io.open(path, "wb")
 8. Print progress per variant, then quit

 Config values: voice_id
 21m00Tcm4TlvDq8ikWAM (Rachel), model
 eleven_multilingual_v2, base_url
 https://api.elevenlabs.io/v1 — matching
 config.lua.

 Step 3: Create screens/noticed.lua — "What
 did you notice?" screen

 Follows the established screen pattern
 (load, update, draw, keypressed).

 - load(): Scan resources/audio/ for files
 matching what_noticed_*.mp3, pick one at
 random via love.math.random(), load as a
 static audio source, load font, reset
 state, play audio
 - update(dt): Check source:isPlaying().
 When audio finishes, wait 0.5s delay then
 auto-advance to menu
 - draw(): Dark background (matching
 oscillating 0.05, 0.05, 0.07), centered
 "What did you notice?" text, hint text at
 bottom
 - keypressed(k): Space/Return → stop audio,
  advance to menu. Escape → stop audio,
 return to menu.

 For scanning files: use love.filesystem.get
 DirectoryItems("resources/audio") and
 filter for names matching
 what_noticed_%d+%.mp3.

 Step 4: Modify main.lua:9 — register the
 new screen

 Add one line to the screens table:
 noticed = require("screens.noticed"),

 Step 5: Modify screens/oscillating.lua —
 auto-transition to noticed

 Add a timer so oscillating auto-advances
 after a set duration:
 - Add elapsed = 0 and DURATION = 5 (seconds
  — short for testing, will become
 configurable later)
 - Reset elapsed in load()
 - Increment elapsed in update(dt), call
 switchScreen("noticed") when expired
 - Escape key still goes to menu (session
 abort)

 Files summary

 ┌──────────────────────┬───────────────┐
 │         File         │    Action     │
 ├──────────────────────┼───────────────┤
 │ testing/conf.lua     │ CREATE        │
 ├──────────────────────┼───────────────┤
 │                      │ REPLACE       │
 │ testing/main.lua     │ (currently a  │
 │                      │ placeholder)  │
 ├──────────────────────┼───────────────┤
 │ screens/noticed.lua  │ CREATE        │
 ├──────────────────────┼───────────────┤
 │                      │ MODIFY — add  │
 │ main.lua:9           │ noticed to    │
 │                      │ screens table │
 ├──────────────────────┼───────────────┤
 │                      │ MODIFY — add  │
 │ screens/oscillating. │ elapsed timer │
 │ lua                  │  + auto-trans │
 │                      │ ition         │
 └──────────────────────┴───────────────┘

 Verification

 1. Run love testing/ — should print
 progress, generate
 resources/audio/what_noticed_{1,2,3}.mp3,
 exit
 2. Confirm 3 distinct MP3 files exist in
 resources/audio/
 3. Run love . — menu → Start Session →
 oscillating runs 5s → noticed screen shows
 text + plays a random audio variant →
 auto-returns to menu
 4. Re-enter session a few times — should
 hear different variants
 5. During noticed screen, press Space to
 skip ahead
 6. During oscillating, press Escape to
 abort back to menu