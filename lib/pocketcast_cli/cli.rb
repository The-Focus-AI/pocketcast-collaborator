require_relative 'commands/transcribe'
require_relative 'commands/chat'

module PocketcastCLI
  class CLI < Thor
    def initialize(*args)
      super
      @pc = Pocketcast.new
      @pastel = Pastel.new
    end

    desc "sync", "Sync episodes from Pocketcast"
    def sync
      puts "Syncing episodes from Pocketcast..."
      @pc.sync_recent_episodes
      puts "Done! #{@pc.episodes.count} episodes synced."
    end

    desc "download", "Download undownloaded episodes"
    def download
      undownloaded = @pc.episodes.values.reject(&:downloaded?)
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
          @pc.download_episode(episode)
        end
      end
    end

    desc "select", "Interactively browse and select episodes"
    def select
      selector = EpisodeSelector.new(@pc)
      selector.run
    end

    desc "version", "Show version"
    def version
      puts PocketcastCLI::VERSION
    end

    desc "transcribe EPISODE_ID", "Transcribe an episode"
    def transcribe(episode_id)
      episode = find_episode(episode_id)
      Commands::Transcribe.new(episode).invoke_all
    end

    desc "chat EPISODE_ID", "Chat with an episode's transcript"
    def chat(episode_id)
      episode = find_episode(episode_id)
      Commands::Chat.new([episode_id]).invoke_all
    end

    desc "load EPISODE_ID", "Load a transcript for an episode"
    def load(episode_id)
      episode = find_episode(episode_id)
      return unless episode
      puts Commands::Transcribe.new(episode).current
    end

    desc "play EPISODE_ID", "Play an episode directly"
    def play(episode_id)
      # Sync episodes first if needed
      if @pc.episodes.empty?
        say "Syncing episodes from Pocketcast...", :yellow
        @pc.sync_recent_episodes
      end

      episode = find_episode(episode_id)
      return unless episode
      
      unless episode.downloaded?
        say "Episode must be downloaded first. Downloading...", :yellow
        
        begin
          progress_bar = TTY::ProgressBar.new(
            "[:bar] :percent",
            total: 100,
            width: TTY::Screen.width - 10,
            complete: "▓",
            incomplete: "░"
          )
          
          @pc.download_episode(episode) do |progress|
            progress_bar.current = progress
          end
          
          say "\nDownload complete!", :green
        rescue => e
          say "Error downloading episode:", :red
          say e.message, :red
          return
        end
      end
      
      # Start the player
      player = PodcastPlayer.new(episode)
      player.run
    end

    private

    def find_episode(uuid_prefix)
      # Find episode where UUID starts with the given prefix
      episode = @pc.episodes.values.find { |e| e.uuid.start_with?(uuid_prefix) }
      unless episode
        say "Episode not found with UUID starting with: #{uuid_prefix}", :red
        return nil
      end
      episode
    end
  end
end 