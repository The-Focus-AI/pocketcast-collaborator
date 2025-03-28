module PocketcastCLI
  module Services
    # Centralizes all path-related functionality in the application
    class PathService
      class << self
        # Base directories
        def data_dir
          'data'
        end

        def transcript_dir
          File.join(data_dir, 'transcripts')
        end

        def download_dir
          'mp3s'
        end

        # File paths
        def transcript_path(episode)
          File.join(transcript_dir, "#{episode.filename.sub('.mp3', '.json')}")
        end

        def download_path(episode)
          File.join(download_dir, episode.filename)
        end

        # Directory management
        def ensure_directory_exists(path)
          FileUtils.mkdir_p(path) unless File.directory?(path)
        end

        def ensure_transcript_directory
          ensure_directory_exists(transcript_dir)
        end

        def ensure_download_directory
          ensure_directory_exists(download_dir)
        end
      end
    end
  end
end