# Pocketcast Collaborator

A command-line interface for Pocketcast that adds AI-powered features like transcription and search to your podcast listening experience. Built in just half a day as an experiment in AI-assisted development, inspired by [Simon Willison's post about Gemini transcription](https://simonwillison.net/2025/Mar/25/gemini/).



![Transcription Playback](demos/transcription.gif)

## Features

### 🎧 Podcast Episode Management
- Browse and search your Pocketcast episodes with a beautiful terminal UI
- Interactive real-time search with `/` key and live filtering
- Quick filter cycling with `f` key (All → Downloaded → Starred → Archived → Transcribed)
- Multiple sorting options with `s` key:
  - Date (newest first)
  - Duration (longest/shortest first)
  - Podcast name
- Toggle starring with `*` key
- Automatic downloads when playing episodes
- Episode ID display for reference and debugging
- Detailed show notes with HTML formatting stripped
- Status indicators for downloaded (↓), starred (★), and transcribed (T) episodes
- Real-time episode list updates during search and filtering

### 🎵 Audio Playback
- Play/pause with Enter key
- Skip forward/backward 30 seconds with arrow keys
- Real-time progress bar and duration display
- Automatic download handling before playback
- Uses ffmpeg for reliable audio extraction and seeking
- Clean process management for reliable playback
- Status bar with playback controls and current state
- Download progress indicator with percentage

### 📝 AI Transcription & Sync
- Automatic transcription when playing downloaded episodes
- Uses Google's Gemini API with specific model selection
- Real-time progress tracking during transcription
- Live segment updates as transcription progresses
- Highlighted current segment during playback
- Navigate transcript with Up/Down and PgUp/PgDn keys
- Smart scrolling with 1/3 past, 2/3 future context ratio
- Scroll indicators (↑/↓) when more content is available
- Dimmed past segments for better context

### 💬 Chat Functionality
- Interact with episode transcripts through chat interface
- Automatically enables when transcript is complete
- Clear status indicators showing chat availability
- Maintains context about episode content
- Preserves playback state during chat sessions
- Press 'c' to enter chat mode when transcript is ready

### 🔄 Transcript Synchronization
Watch as the transcript automatically follows along with the audio:

![Transcript Sync](demos/sync.gif)

Selecting and episode.

![Episode Selection](demos/demo.gif)

## Requirements

- FFMPEG
- Ruby 3.0+
- [llm-gemini](https://github.com/simonw/llm-gemini) for transcription
- ffmpeg for audio processing and seeking

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/The-Focus-AI/pocketcast-collaborator.git
   cd pocketcast-collaborator
   ```

2. Install dependencies:
   ```bash
   bundle install
   brew install ffmpeg  # Required for audio processing
   pip install llm-gemini
   ```

3. We look for pocketcast credentials in 1password


## Usage

Start the application:
```bash
bin/pocketcast
```

### Episode Management Commands
- `f` Cycle through filter options (All → Downloaded → Starred → Archived → Transcribed)
- `*` Toggle starred status for current episode
- `s` Cycle through sort options (Date → Duration → Duration Asc → Podcast)
- `/` Start interactive real-time search
  - Search by title or podcast name
  - Up/Down arrows to navigate results while searching
  - Enter to select, Escape to cancel
  - Special searches: "longest" (top 10% longest), "shortest" (top 10% shortest)
- `r` Refresh episode list from Pocketcast
- `↑/↓` or `k/j` Navigate through episodes
- `Enter` Select and play episode
- `q` Quit current view

### Playback Commands
- `Enter` Play/Pause
- `←/→` Skip backward/forward 30 seconds
- `↑/↓` Navigate transcript segments
- `PgUp/PgDn` Scroll transcript pages
- `c` Open chat interface (when transcript is available)
- `q` Quit current view/player

## How It Works

1. **Episode Management**: 
   - Connects to your Pocketcast account to access your episodes
   - Maintains a local cache for quick filtering and searching
   - Supports complex filtering combinations
   - Real-time search with instant results
   - Smart sorting with proper handling of missing data

2. **Audio Processing**:
   - Uses ffmpeg to extract audio segments for precise seeking
   - Handles various audio formats and bitrates automatically
   - Provides accurate playback position for transcript sync
   - Enables instant seeking without re-buffering
   - Clean process management for reliable playback

3. **Transcription**: 
   - Automatically transcribes downloaded episodes using Google's Gemini API
   - Displays real-time progress during transcription
   - Saves transcripts for future playback
   - Synchronizes transcript display with audio position
   - Smart scrolling to maintain context while reading

## Project Background

This project was built in just half a day (March 26, 2024) as an experiment in AI-assisted development. Inspired by Simon Willison's exploration of Gemini's transcription capabilities, I wanted to create a tool that would make podcast listening more interactive and searchable.

Using Claude in Cursor, we were able to rapidly:
1. Set up the basic Pocketcast API integration
2. Implement a robust terminal UI
3. Add audio playback with ffmpeg
4. Integrate real-time transcription
5. Create a synchronized transcript display
6. Add intelligent search and filtering
7. Implement smart scrolling and navigation

Check the [WORKLOG.md](WORKLOG.md) for the detailed development timeline and progress.

## Architecture

The codebase follows a clean, modular architecture with clear separation of concerns:

```
lib/pocketcast_cli/
├── commands/          # UI and CLI components (presentation layer)
│   ├── chat.rb        # Chat command interface
│   ├── cli_command.rb # Main CLI command hub
│   ├── episode_selector_command.rb # Episode browsing interface
│   ├── podcast_player.rb # Audio player interface
│   └── transcribe.rb  # Transcription command
├── models/            # Data models (domain layer)
│   ├── episode.rb     # Episode data representation
│   └── transcript.rb  # Transcript data handling
└── services/          # Business logic (service layer)
    ├── chat_service.rb         # Chat interaction business logic
    ├── episode_service.rb      # Episode management services
    ├── path_service.rb         # Centralized file path handling
    ├── player_service.rb       # Audio playback functionality
    ├── pocketcast_service.rb   # API integration with Pocketcast
    └── transcription_service.rb # Transcript generation logic
```

Key architectural principles:
- **Service-Oriented Design**: Core business logic is encapsulated in dedicated service classes
- **Dependency Injection**: Services are passed as dependencies rather than instantiated directly
- **Clean Command Pattern**: UI commands act as thin wrappers around service layer
- **Clear Responsibility Boundaries**: Each component has a single, well-defined responsibility
- **Avoidance of Circular Dependencies**: Services maintain clear unidirectional relationships

Benefits of this architecture:
- Easier addition of new features and commands
- Isolated testing of business logic
- Improved maintainability with proper separation
- Better component reuse across different UI elements
- Enhanced stability through clear boundaries

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Pocketcasts](https://www.pocketcasts.com/) for their amazing podcast platform
- [llm-gemini](https://github.com/simonw/llm-gemini) for transcription capabilities
- [FFmpeg](https://ffmpeg.org/) for audio processing and seeking support
- [Simon Willison](https://simonwillison.net/) for the inspiration and Gemini transcription exploration 