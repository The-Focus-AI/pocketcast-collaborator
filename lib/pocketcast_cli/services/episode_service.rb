require 'pastel'

module PocketcastCLI
  module Services
    # Centralizes episode-related functionality
    class EpisodeService
      attr_reader :pocketcast
      
      def initialize(pocketcast = nil)
        @pocketcast = pocketcast || PocketcastService.new
        @pastel = Pastel.new
      end
      
      # Find episode by UUID or UUID prefix
      def find_episode(uuid_prefix, output_stream: $stdout)
        # Sync episodes if needed
        if @pocketcast.episodes.empty?
          output_stream.puts @pastel.yellow("Syncing episodes from Pocketcast...")
          @pocketcast.sync_recent_episodes
        end
        
        # Find episode where UUID starts with the given prefix
        episode = @pocketcast.episodes.values.find { |e| e.uuid.start_with?(uuid_prefix) }
        unless episode
          output_stream.puts @pastel.red("Episode not found with UUID starting with: #{uuid_prefix}")
          return nil
        end
        
        episode
      end
      
      # Download an episode
      def download_episode(episode, output_stream: $stdout, &progress_callback)
        unless episode.downloaded?
          output_stream.puts @pastel.yellow("Episode must be downloaded first. Downloading...")
          
          begin
            @pocketcast.download_episode(episode, &progress_callback)
            output_stream.puts @pastel.green("\nDownload complete!")
            return true
          rescue => e
            output_stream.puts @pastel.red("Error downloading episode:")
            output_stream.puts @pastel.red(e.message)
            return false
          end
        end
        
        true # Already downloaded
      end
      
      # Sync episodes from Pocketcast
      def sync_episodes(output_stream: $stdout)
        output_stream.puts "Syncing episodes from Pocketcast..."
        @pocketcast.sync_recent_episodes
        output_stream.puts "Done! #{@pocketcast.episodes.count} episodes synced."
      end
      
      # Get all episodes
      def all_episodes
        @pocketcast.episodes.values
      end
      
      # Get undownloaded episodes
      def undownloaded_episodes
        @pocketcast.episodes.values.reject(&:downloaded?)
      end
    end
  end
end