require 'thor'
require_relative '../services/transcription_service'

module PocketcastCLI
  module Commands
    class Transcribe < Thor::Group
      include Thor::Actions
      
      attr_reader :episode
      
      def initialize(episode = nil)
        super()
        @episode = episode
        @transcription_service = Services::TranscriptionService.new
      end
      
      def execute
        # Start transcription
        @transcription_service.transcribe(@episode) do |progress|
          if progress == 100
            say "Transcription completed!", :green
          elsif progress == -1
            say "Transcription failed", :red
          end
        end
      end
      
      def current
        # Get current transcript
        transcript = @transcription_service.get_transcript(@episode)
        transcript&.items
      end
      
      # These methods are kept for backwards compatibility
      def loaded?
        transcript = @transcription_service.get_transcript(@episode)
        transcript&.loaded?
      end
      
      def loading?
        @transcription_service.transcribing?(@episode)
      end
      
      def started?
        transcript = @transcription_service.get_transcript(@episode)
        transcript&.started?
      end
    end
  end
end