-- Manifest of all pre-cached TTS audio for the identification flow.
-- Edit the `text` fields freely, then run `love scripts/audio_generation` from the
-- repo root to (re)generate. Each entry produces
-- resources/audio/<subfolder>/<prefix>_<n>.mp3 for n = 1..variants.
-- Screens pick a random file from each subfolder, so multiple entries may share a
-- subfolder (the bridge phrases below) and `variants > 1` re-renders the same text
-- for natural delivery variety.
-- Speed: 1.0 = normal; the app's notice prompts use 0.9.

return {
    -- Played by ident_prelude before the live agent call.
    { subfolder = "ident/settling", prefix = "settling", variants = 1, speed = 0.92,
      text = "Welcome. Before we begin, take a moment to settle. Sit comfortably, and let your shoulders soften. In this part of the session, we're going to find the image we'll be working with. A single snapshot that stands for the hardest part of a memory. You won't need to relive anything, or tell the whole story. A few words is always enough. In a moment, you'll speak with a guide who will help you find that picture." },

    { subfolder = "ident/image_prelude", prefix = "image_prelude", variants = 1, speed = 0.92,
      text = "With your eyes closed, or a soft gaze, cast your mind back to the memory you want to work with. Let it come to you gently. There's no need to search hard. When the guide speaks, take all the time you need before answering." },

    -- Negative cognition stage (first stage after the call — carries the key
    -- instructions: eyes open, speak aloud, space bar to finish).
    { subfolder = "ident/interlude_nc", prefix = "interlude_nc", variants = 1, speed = 0.92,
      text = "You can open your eyes now. The image is captured. That part is done, and you did it well. For these next questions, answer out loud in your own words, and press the space bar when you've finished speaking. Now, close your eyes for a moment, and let that picture come back." },
    { subfolder = "ident/question_nc", prefix = "question_nc", variants = 1, speed = 0.9,
      text = "What words go best with that picture, that express your negative belief about yourself, now?" },

    -- Positive cognition stage.
    { subfolder = "ident/interlude_pc", prefix = "interlude_pc", variants = 1, speed = 0.92,
      text = "Thank you. Now let's turn that around. Keep the picture there, softly, for one more question." },
    { subfolder = "ident/question_pc", prefix = "question_pc", variants = 1, speed = 0.9,
      text = "When you bring up that picture, what would you prefer to believe about yourself, instead?" },

    -- Emotion stage (follows the VoC rating screen).
    { subfolder = "ident/interlude_emotion", prefix = "interlude_emotion", variants = 1, speed = 0.92,
      text = "Thank you. Close your eyes again for a moment, and bring up the picture, and those negative words." },
    { subfolder = "ident/question_emotion", prefix = "question_emotion", variants = 1, speed = 0.9,
      text = "What emotions do you feel, right now?" },

    -- Body sensations stage (follows the SUD rating screen).
    { subfolder = "ident/interlude_body", prefix = "interlude_body", variants = 1, speed = 0.92,
      text = "Nearly there. Once more, let the picture and the words be present, and turn your attention to your body." },
    { subfolder = "ident/question_body", prefix = "question_body", variants = 1, speed = 0.9,
      text = "Where do you feel it, in your body?" },

    -- Bridge phrases: played the instant a recording stops, covering the
    -- transcription/thinking wait as a grounding breath. Distinct texts sharing one
    -- subfolder; the stage screen picks one at random.
    { subfolder = "ident/bridge", prefix = "bridge_a", variants = 1, speed = 0.9,
      text = "Thank you. Take a slow, deep breath." },
    { subfolder = "ident/bridge", prefix = "bridge_b", variants = 1, speed = 0.9,
      text = "Good. Breathe in... and let it go." },
    { subfolder = "ident/bridge", prefix = "bridge_c", variants = 1, speed = 0.9,
      text = "Thank you. Rest here for a moment, and breathe." },
    { subfolder = "ident/bridge", prefix = "bridge_d", variants = 1, speed = 0.9,
      text = "Well done. A slow breath in... and a long breath out." },
}
