# Code Restructuring Plan

## Current Issues
- Thor commands directly call other Thor commands
- Business logic is mixed with CLI handling
- Inconsistent command structure (some as Thor::Group classes, others as CLI methods)
- Direct dependencies between components (PodcastPlayer referencing Commands::Transcribe)
- Duplicated logic for finding episodes, managing file paths, etc.

## Proposed Architecture

### 1. Service Layer
Create dedicated service classes for all core functionality:

- `TranscriptionService`: Handle all transcription-related operations
- `ChatService`: Handle all chat interaction logic
- `EpisodeService`: Centralize episode finding, filtering, metadata
- `PlayerService`: Manage audio playback functionality
- `PathService`: Centralize all file path handling

### 2. Model Layer
Enhance existing models:

- `Episode`: Keep as is, but inject services rather than containing functionality
- `Transcript`: New model to represent transcript data (currently embedded in Commands::Transcribe)

### 3. Command Layer
Convert all Thor commands to thin wrappers around services:

- All commands should delegate to services for business logic
- Commands should only handle CLI I/O, arguments and feedback
- Consistent interface pattern for all commands

### 4. Dependency Injection
Implement dependency injection:

- Services receive required dependencies when instantiated
- Avoid direct instantiation of dependencies within methods
- Central registry for shared dependencies like Pastel, TTY components

## Implementation Steps

1. Create `services/` directory for all service classes
2. Create `models/` directory for enhanced models
3. Move core functionality from commands to services
4. Update Thor commands to use services
5. Update PodcastPlayer to use services instead of commands
6. Implement centralized path handling
7. Update CLI to use consistent command invocation pattern

## Example: Transcription Flow

**Current:**
```
CLI#transcribe -> Commands::Transcribe.new(episode).invoke_all
PodcastPlayer -> Commands::Transcribe.new(episode)
```

**Proposed:**
```
CLI#transcribe -> TranscriptionService.transcribe(episode)
PodcastPlayer -> @transcription_service.transcribe(episode)
```

## Example: Chat Flow

**Current:**
```
CLI#chat -> Commands::Chat.new([episode_id]).invoke_all
PodcastPlayer -> Commands::Chat.new(@episode.uuid).start_chat
```

**Proposed:**
```
CLI#chat -> ChatService.start_chat(episode)
PodcastPlayer -> @chat_service.start_chat(episode)
```