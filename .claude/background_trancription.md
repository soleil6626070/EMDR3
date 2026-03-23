The task is to write a transcription worker that transcribes user responses and saves them to a linked list for later data analysis.

We installed whisper using the scripts/setup_whisper.sh script.
Currently, the program saves WAV files to resources/audio/transcription_queue/ as the session progresses.

We want our transcription worker to:
1: transcribe these files in the order in which they were generated, 
2: append the transcribed text to a linked list and txt file, 
3: delete the transcribed audio file
4: loop (begin transcribing the next file)

The linked list of nodes of transcribed responses should be saved to EMDR3/output_data/
Their format should be:

    Session: _____

    ---

    Response 1: ______

    ---

    Response 2: ______

    ---

    Response 3: ______

Considerations:
- The user's transcription speed will change depending on their cpu/gpu processing speed. 
- The time inbetween the cycles might be very short or very long depending on the programs configuration.
- The session might be cut short by the user (ie only half the cycles are completed).
- The program might crash/be exited accidentally, the transcription should resume from where it left off in the queue once the program is restarted.
- in the even of a session being cut short, the user should be given an option to "Resume previous session?" and transcribed responses should be saved to the appropritate linked list. 
- The transcription worker should continue working if there are still files in the queue once the session is finished, and display an indicator that it is still transcribing in the main menu(eg: Transcribing: n/N)
- A new session might be started whilst there are still files transcribing for a previous session, the background transcription worker should recognise that they are different sessions, and once it has finished appending the linked list of the previous session, begin working on the new linked list. 

The transcription worker should continue to work under these varying circumstances.

We will need to make some changes to the way the program handles sessions also to ensure good crash/error/early exit handling.
Keeping it simple is better, we need a simple transcription worker that runs in the background without interfereing with the user's sessions, that transcribes responses and saves them in a linked list for data analysis whilst handling early session termination.

Suggestions:
I suggest a parameter 1/0, eg: Session_ongoing=1 or 0 and changing it when the session starts and when the final cycle completes. That way in the event of an early exit, when the program is started again and processing is selected, we can quickly ask resume session? y/n to know if we want to append to the previous linked list or start a new one.
Perhaps a session_id variable would work, or make use of the session.startTimestamp = "" variable.
