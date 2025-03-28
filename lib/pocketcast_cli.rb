require_relative 'pocketcast_cli/version'

# Load models
require_relative 'pocketcast_cli/models/episode'
require_relative 'pocketcast_cli/models/transcript'

# Load services
require_relative 'pocketcast_cli/services/path_service'
require_relative 'pocketcast_cli/services/pocketcast_service' 
require_relative 'pocketcast_cli/services/episode_service'
require_relative 'pocketcast_cli/services/transcription_service'
require_relative 'pocketcast_cli/services/chat_service'
require_relative 'pocketcast_cli/services/player_service'

# Load commands
require_relative 'pocketcast_cli/commands/transcribe'
require_relative 'pocketcast_cli/commands/chat'
require_relative 'pocketcast_cli/commands/episode_selector_command'
require_relative 'pocketcast_cli/commands/podcast_player'
require_relative 'pocketcast_cli/commands/cli_command'

module PocketcastCLI
  class Error < StandardError; end
end