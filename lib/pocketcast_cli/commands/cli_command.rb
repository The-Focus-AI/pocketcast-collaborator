require 'thor'
require 'pastel'
require 'tty-progressbar'
require 'tty-prompt'
require 'tty-screen'

require_relative 'transcribe'
require_relative 'chat'
require_relative 'podcast_player'
require_relative 'episode_selector_command'
require_relative '../services/episode_service'
require_relative '../services/transcription_service'
require_relative '../services/player_service'
require_relative '../services/chat_service'
require_relative '../services/path_service'

module PocketcastCLI
  module Commands
    class CLI < Thor
      def initialize(*args)
        super
        @pastel = Pastel.new
        
        # Initialize services
        @episode_service = Services::EpisodeService.new
        @transcription_service = Services::TranscriptionService.new
        @player_service = Services::PlayerService.new
        @chat_service = Services::ChatService.new
      end

      desc "sync", "Sync episodes from Pocketcast"
      def sync
        @episode_service.sync_episodes
      end

      desc "download", "Download undownloaded episodes"
      def download
        undownloaded = @episode_service.undownloaded_episodes
        
        if undownloaded.empty?
          puts "No new episodes to download."
          return
        end

        puts "Found #{undownloaded.count} episodes to download:"
        undownloaded.each do |episode|
          puts "- #{episode.title}"
        end

        prompt = TTY::Prompt.new
        if prompt.yes?("Download these episodes?")
          undownloaded.each do |episode|
            progress_bar = TTY::ProgressBar.new(
              "[:bar] :percent",
              total: 100,
              width: TTY::Screen.width - 10,
              complete: "▓",
              incomplete: "░"
            )
            
            @episode_service.download_episode(episode) do |progress|
              progress_bar.current = progress
            end
          end
        end
      end

      desc "select", "Interactively browse and select episodes"
      def select
        selector = PocketcastCLI::Commands::EpisodeSelector.new(@episode_service.pocketcast)
        selector.run
      end

      desc "version", "Show version"
      def version
        puts PocketcastCLI::VERSION
      end

      desc "transcribe EPISODE_ID", "Transcribe an episode and display the transcript"
      def transcribe(episode_id)
        episode = @episode_service.find_episode(episode_id)
        return unless episode
        
        puts "Episode: #{episode.title}"
        puts "UUID: #{episode.uuid}"
        puts "Downloaded: #{episode.downloaded? ? 'Yes' : 'No'}"
        
        # Check if already transcribed
        transcript_path = Services::PathService.transcript_path(episode)
        if File.exist?(transcript_path)
          puts "Transcript already exists at #{transcript_path}"
          # Load and display existing transcript
          load(episode_id)
          return
        end
        
        # Check if episode is downloaded
        unless episode.downloaded?
          puts "Episode must be downloaded first. Downloading..."
          @episode_service.download_episode(episode) do |progress|
            print "\rDownloading: #{progress}%"
          end
          puts "\nDownload complete!"
        end
        
        # Create progress bar
        require 'tty-progressbar'
        require 'tty-screen'
        
        progress_bar = TTY::ProgressBar.new(
          "Transcribing [:bar] :percent",
          total: 100,
          width: TTY::Screen.width - 20,
          complete: "▓",
          incomplete: "░"
        )
        
        # Track transcription start time
        start_time = Time.now
        
        # Start transcription via the service
        puts "Starting transcription of '#{episode.title}'..."
        
        # Initialize the transcript to track progress
        @transcription_service.get_transcript(episode)
        
        # Start the transcription process
        transcript = @transcription_service.transcribe(episode) do |progress|
          if progress == 100
            progress_bar.finish
            say "\nTranscription completed!", :green
          elsif progress == -1
            progress_bar.finish
            say "\nTranscription failed", :red
          end
        end
        
        # Now check for transcript periodically and show progress
        transcript_started = false
        last_segment_count = 0
        
        until transcript_started || (Time.now - start_time) > 60
          sleep 1
          
          # Check if transcript file exists
          if File.exist?(transcript_path)
            transcript_started = true
            puts "Transcript file created - now processing segments..."
            break
          end
        end
        
        if transcript_started
          # Now monitor transcript progress
          loop do
            transcript = @transcription_service.get_transcript(episode, force_reload: true)
            
            if transcript&.loaded?
              puts "\nTranscription completed!"
              break
            end
            
            segments = transcript&.items&.size || 0
            
            if segments > last_segment_count
              progress_bar.current = [segments, 100].min
              last_segment_count = segments
            end
            
            if @transcription_service.transcribing?(episode)
              # Still transcribing
              sleep 1
            else
              # Transcription process ended
              break
            end
          end
          
          # Load and display transcript
          load(episode_id)
        else
          puts "Transcription process started but no output detected within timeout period."
          puts "The process may still be running in the background."
          puts "Run `pocketcast load #{episode_id}` later to check the transcript."
        end
      end

      desc "chat EPISODE_ID", "Chat with an episode's transcript"
      def chat(episode_id)
        episode = @episode_service.find_episode(episode_id)
        return unless episode
        
        # Check transcript exists
        transcript_path = Services::PathService.transcript_path(episode)
        unless File.exist?(transcript_path)
          say "No transcript found for: #{episode.title}", :red
          return
        end
        
        # Start chat via the service
        @chat_service.start_chat(episode)
      end

      desc "load EPISODE_ID", "Load and display a transcript for an episode"
      def load(episode_id)
        episode = @episode_service.find_episode(episode_id)
        return unless episode
        
        puts "Episode: #{episode.title}"
        
        # Check transcript path
        transcript_path = Services::PathService.transcript_path(episode)
        puts "Transcript path: #{transcript_path}"
        puts "Transcript exists: #{File.exist?(transcript_path) ? 'Yes' : 'No'}"
        
        if File.exist?(transcript_path)
          puts "Transcript file size: #{File.size(transcript_path)} bytes"
        end
        
        # Try to load transcript
        transcript = @transcription_service.get_transcript(episode, force_reload: true)
        
        if transcript&.items && !transcript.items.empty?
          puts "Loaded #{transcript.items.size} transcript segments"
          puts "-" * 80
          
          total_words = 0
          transcript.items.each do |item|
            # Calculate word count for each segment
            words = item[:text].split(/\s+/).count
            total_words += words
            
            # Display timestamp and text
            puts "#{format_duration(item[:timestamp])}: #{item[:text]}"
          end
          
          puts "-" * 80
          puts "Total transcript: #{total_words} words in #{transcript.items.size} segments"
          puts "Transcript load complete!"
        else
          puts "No transcript available or transcript is empty"
          if File.exist?(transcript_path)
            puts "Transcript file exists but couldn't be parsed. Contents:"
            puts File.read(transcript_path)[0..1000] # Show the first 1000 chars
            puts "..."
            
            # Check if transcription might still be in progress
            if @transcription_service.transcribing?(episode)
              puts "Transcription is still in progress. Check back later or try the play command."
            else
              puts "Transcription is not active. The file might be corrupted."
              puts "Consider running `pocketcast transcribe #{episode_id}` to start a new transcription."
            end
          else
            puts "No transcript file found. Run `pocketcast transcribe #{episode_id}` to create one."
          end
        end
      end

      desc "play EPISODE_ID", "Play an episode directly"
      def play(episode_id)
        episode = @episode_service.find_episode(episode_id)
        return unless episode
        
        # Ensure episode is downloaded
        unless @episode_service.download_episode(episode) do |progress|
            progress_bar = TTY::ProgressBar.new(
              "[:bar] :percent",
              total: 100,
              width: TTY::Screen.width - 10,
              complete: "▓",
              incomplete: "░"
            )
            progress_bar.current = progress
          end
          return
        end
        
        # Start the player
        player = PodcastPlayer.new(episode, 
                                  @player_service, 
                                  @transcription_service,
                                  @chat_service,
                                  @episode_service)
        player.run
      end

      private

      def format_duration(seconds)
        return "--:--" unless seconds
        hours = seconds / 3600
        minutes = (seconds % 3600) / 60
        secs = seconds % 60
        
        if hours > 0
          "%02d:%02d:%02d" % [hours, minutes, secs]
        else
          "%02d:%02d" % [minutes, secs]
        end
      end
    end
  end
end