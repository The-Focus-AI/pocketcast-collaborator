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
  end
end 