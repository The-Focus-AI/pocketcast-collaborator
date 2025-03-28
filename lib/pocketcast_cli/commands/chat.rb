require 'thor'
require_relative '../services/episode_service'
require_relative '../services/chat_service'
require_relative '../services/path_service'

module PocketcastCLI
  module Commands
    class Chat < Thor::Group
      include Thor::Actions
      
      argument :episode_id, type: :string, desc: "Episode ID to chat about"
      
      def initialize(*args)
        super
        @episode_service = Services::EpisodeService.new
        @chat_service = Services::ChatService.new
        
        # If first argument is an Episode object, use it directly
        if args.first.is_a?(Array) && args.first.first.is_a?(PocketcastCLI::Models::Episode)
          @episode = args.first.first
          @episode_id = @episode.uuid
        end
      end
      
      def find_episode
        # Skip if we already have an episode
        return if @episode
        
        # Find episode by UUID
        @episode = @episode_service.find_episode(episode_id)
        exit 1 unless @episode
      end
      
      def check_transcript
        # Find episode if not already set
        find_episode unless @episode
        
        # Check if transcript exists
        transcript_path = Services::PathService.transcript_path(@episode)
        unless File.exist?(transcript_path)
          say "No transcript found for: #{@episode.title}", :red
          exit 1
        end
      end
      
      def start_chat
        # Find episode if not already set
        find_episode unless @episode
        
        # Start the chat service
        @chat_service.start_chat(@episode)
      end
    end
  end
end