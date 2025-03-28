# PocketCast Collaborator Developer Guide

## Build/Run Commands
- `bundle install` - Install Ruby dependencies
- `bin/pocketcast` - Run the application
- `bin/pocketcast sync` - Sync episodes from PocketCast
- `bin/pocketcast play <UUID>` - Play a specific episode
- `bin/pocketcast transcribe <UUID>` - Generate transcript for episode
- `bin/pocketcast chat <UUID>` - Chat with a transcript
- `ruby -r ./lib/pocketcast_cli -e "require 'test/unit'; Test::Unit::AutoRunner.run"` - Run all tests

## Code Style Guidelines
- **Language**: Ruby 3.0+
- **Naming**: snake_case for methods/variables, CamelCase for classes
- **Imports**: Group standard library, external gems, then local modules
- **Error Handling**: Use exception handling with specific rescue blocks
- **CLI Structure**: Use Thor for command-line interface components
- **Player UI**: Terminal UI handling via TTY gems, maintain consistent layout
- **Transcripts**: JSON with timestamp/text pairs, stored in data/transcripts
- **Command Pattern**: CLI commands in lib/pocketcast_cli/commands/
- **External APIs**: Use `llm` CLI for AI operations (Gemini API)
- **Media**: Handle audio files with ffmpeg (no direct audio processing)