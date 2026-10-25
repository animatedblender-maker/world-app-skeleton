# WhisperKit models (bundled)

`openai_whisper-small` is fetched at build time by
`apps/mobile/ios/WorldApp/scripts/fetch_whisperkit_model.sh`
and copied into the app bundle. It is gitignored (~464MB).

Do not commit the model folder. Run the fetch script (or an Xcode build)
before testing CC captions.
