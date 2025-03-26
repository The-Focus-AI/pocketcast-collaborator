# Pocketcast Collaborator

A command-line interface for Pocketcast that adds AI-powered features like transcription and search to your podcast listening experience. Built in just half a day as an experiment in AI-assisted development, inspired by [Simon Willison's post about Gemini transcription](https://simonwillison.net/2025/Mar/25/gemini/).

![Transcription Playback](docs/images/transcription-playback.gif)

## Features

### 🎧 Podcast Episode Management
- Browse and search your Pocketcast episodes by title, podcast name, or content
- Filter episodes by status (downloaded, starred, archived)
- Sort episodes by date, duration, or podcast name
- Quick episode selection with UUID shortcuts
- Download episodes for offline listening
- Star/unstar episodes for easy reference
- View detailed episode metadata and show notes

### 🎵 Audio Playback
- Play/pause with spacebar
- Skip forward/backward 30 seconds with arrow keys
- Real-time progress bar and duration display
- Uses ffmpeg for reliable audio extraction and seeking
- Clean process management for reliable playback

### 📝 AI Transcription & Sync
- Real-time transcription of episodes using Google's Gemini API
- Live display of transcription progress
- Synchronized highlighting of current segment during playback
- Navigate transcript with Up/Down and PgUp/PgDn keys
- Automatic scrolling keeps current segment visible

### 🔄 Transcript Synchronization
Watch as the transcript automatically follows along with the audio:

![Transcript Sync](docs/images/sync.gif)

![Episode Selection](docs/images/episode-select.gif)

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

3. Set up your Pocketcast credentials:
   ```bash
   cp config/pocketcast.yml.example config/pocketcast.yml
   # Edit config/pocketcast.yml with your credentials
   ```

## Usage

Start the application:
```bash
bin/pocketcast
```

### Episode Management Commands
- `f` Filter episodes (downloaded, starred, archived)
- `s` Search episodes by title or content
- `o` Change sort order (date, duration, podcast)
- `r` Refresh episode list
- `d` Download selected episode
- `*` Toggle star on selected episode

### Playback Commands
- `↵` Play/Pause
- `←` Skip back 30 seconds
- `→` Skip forward 30 seconds
- `↑/↓` Navigate transcript segments
- `PgUp/PgDn` Scroll transcript pages
- `q` Quit

## How It Works

1. **Episode Management**: 
   - Connects to your Pocketcast account to access your episodes
   - Maintains a local cache for quick filtering and searching
   - Supports complex filtering combinations (e.g., starred and downloaded)
   - Quick episode access via UUID prefixes

2. **Audio Processing**:
   - Uses ffmpeg to extract audio segments for precise seeking
   - Handles various audio formats and bitrates automatically
   - Provides accurate playback position for transcript sync
   - Enables instant seeking without re-buffering

3. **Transcription**: 
   - Automatically transcribes downloaded episodes using Google's Gemini API
   - Displays real-time progress during transcription
   - Saves transcripts for future playback
   - Synchronizes transcript display with audio position

## Project Background

This project was built in just half a day (March 26, 2024) as an experiment in AI-assisted development. Inspired by Simon Willison's exploration of Gemini's transcription capabilities, I wanted to create a tool that would make podcast listening more interactive and searchable.

Using Claude in Cursor, we were able to rapidly:
1. Set up the basic Pocketcast API integration
2. Implement a robust terminal UI
3. Add audio playback with ffmpeg
4. Integrate real-time transcription
5. Create a synchronized transcript display

Check the [WORKLOG.md](WORKLOG.md) for the detailed development timeline and progress.

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