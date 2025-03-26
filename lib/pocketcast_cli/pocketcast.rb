require 'fileutils'
require 'json'
require 'net/http'
require 'httparty'
require 'open3'
require 'active_support'
require 'active_support/core_ext/string'

module PocketcastCLI
  class Episode
    attr_reader :uuid, :title, :podcast_title, :published_at, :audio_url, :podcast_uuid, :duration, :notes, :last_played_at
    
    def initialize(data, podcast_title = nil)
      @uuid = data['uuid']
      @title = data['title']
      @podcast_title = podcast_title || data['podcastTitle']
      @published_at = Time.parse(data['published']) rescue Time.at(data['published'].to_i)
      @audio_url = data['url']
      @podcast_uuid = data['podcastUuid']
      @duration = data['duration']
      @data = data
      @notes = nil
      
      # Fix playing status access
      if data['playingStatus'].is_a?(Hash) && data['playingStatus']['playedUpTo']
        @last_played_at = Time.at(data['playingStatus']['playedUpTo'].to_i)
      else
        @last_played_at = nil
      end
    end

    def filename
      "#{published_at.strftime('%Y%m%d')}_#{podcast_title.parameterize}_#{title.parameterize}.mp3"
    end
    
    def download_path
      File.join('mp3s', filename)
    end
    
    def downloaded?
      File.exist?(download_path)
    end

    def starred?
      @data['starred'] == true
    end

    def to_h
      {
        uuid: @uuid,
        title: @title,
        podcast_title: @podcast_title,
        published_at: @published_at.iso8601,
        audio_url: @audio_url,
        podcast_uuid: @podcast_uuid,
        duration: @duration,
        filename: filename,
        downloaded: downloaded?,
        starred: starred?,
        notes: @notes,
        last_played_at: @last_played_at&.iso8601,
        raw_data: @data
      }
    end
  end

  class Pocketcast
    attr_reader :episodes

    def initialize
      # Ensure all data directories exist
      %w[
        data
        data/notes
        data/transcripts
        data/entities
        mp3s
      ].each do |dir|
        FileUtils.mkdir_p(dir)
      end
      load_episode_database
    end

    def sync_recent_episodes
      puts "Fetching recently played episodes..."
      recent_episodes = fetch_recent_episodes
      
      puts "Fetching starred episodes..."
      starred_episodes = fetch_starred_episodes

      all_episodes = (recent_episodes + starred_episodes).uniq(&:uuid)
      
      puts "Found #{all_episodes.length} episodes"
      all_episodes.each do |episode|
        puts "Processing #{episode.title}"
        
        # Add to our database if new
        unless @episodes[episode.uuid]
          fetch_episode_notes(episode)
          @episodes[episode.uuid] = episode
          save_episode_database
        end
      end
    end

    def download_episode(episode, &progress_callback)
      return if episode.downloaded?
      
      uri = URI(episode.audio_url)
      
      # Create a temporary file for downloading
      temp_path = episode.download_path + ".tmp"
      
      begin
        # Follow redirects manually since we need to handle HTTPS properly
        max_redirects = 5
        redirect_count = 0
        
        while redirect_count < max_redirects
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            request = Net::HTTP::Get.new(uri)
            
            http.request(request) do |response|
              case response
              when Net::HTTPRedirection
                # Handle redirect
                redirect_count += 1
                new_location = response['location']
                
                if new_location.start_with?('/')
                  # Relative redirect
                  uri = URI.join("#{uri.scheme}://#{uri.host}", new_location)
                else
                  # Absolute redirect
                  uri = URI(new_location)
                end
                
                # Continue to next redirect
                next
              when Net::HTTPSuccess
                total_size = response.content_length
                downloaded_size = 0
                
                File.open(temp_path, 'wb') do |file|
                  response.read_body do |chunk|
                    file.write(chunk)
                    downloaded_size += chunk.bytesize
                    
                    # Calculate and report progress
                    if total_size && total_size > 0 && progress_callback
                      progress = (downloaded_size.to_f / total_size * 100).round
                      progress_callback.call(progress)  # Pass value directly
                    end
                  end
                end
                
                # Verify the download
                if File.size(temp_path) > 0
                  FileUtils.mv(temp_path, episode.download_path)
                  return true  # Success
                else
                  raise "Downloaded file is empty"
                end
              else
                raise "Download failed: #{response.code} #{response.message}"
              end
            end
          end
        end
        
        raise "Too many redirects"
      rescue => e
        # Clean up temp file if download failed
        FileUtils.rm_f(temp_path)
        raise e
      end
    end

    def fetch_episode_notes(episode)
      return if episode.notes # Skip if already loaded

      response = HTTParty.get("https://cache.pocketcasts.com/episode/show_notes/#{episode.uuid}", {
        headers: {
          "Authorization" => "Bearer #{token}",
          "cache-control" => "no-cache",
          "Content-Type" => "application/json"
        }
      })

      data = JSON.parse(response.body)
      episode.instance_variable_set(:@notes, data['show_notes'])
    rescue => e
      puts "Error fetching notes for #{episode.title}: #{e.message}"
      episode.instance_variable_set(:@notes, "Unable to load show notes")
    end

    private

    def get_keys
      puts "Getting keys from 1Password"
      
      output, status = Open3.capture2('op', 'item', 'get', 'pocketcasts.com', '--format', 'json')
      if status.success?
        data = JSON.parse(output)
        
        user = data['fields'].find { |f| f['label'] == 'username' }['value']
        password = data['fields'].find { |f| f['label'] == 'password' }['value']

        {
          'email' => user,
          'password' => password
        }
      else
        throw "Couldn't get credentials from 1Password"
      end
    end

    def token
      if !@token
        keys = get_keys
        puts "Logging in"
        response = HTTParty.post('https://api.pocketcasts.com/user/login', {
          query: {
            email: keys['email'],
            password: keys['password'],
            scope: 'webplayer'
          },
          headers: {
            "cache-control" => "no-cache"
          }
        } )

        data = JSON.parse(response.body)
        @token = data['token']
        @email = data['email']
        @user_uuid = data['uuid']
      end

      @token
    end

    def fetch_recent_episodes
      response = HTTParty.post('https://api.pocketcasts.com/user/history', {
        body: {
          limit: 100
        }.to_json,
        headers: {
          "Authorization" => "Bearer #{token}",
          "cache-control" => "no-cache",
          "Content-Type" => "application/json"
        }
      })

      data = JSON.parse(response.body)
      data['episodes'].map do |episode_data|
        Episode.new(episode_data)
      end
    end

    def fetch_starred_episodes
      response = HTTParty.post('https://api.pocketcasts.com/user/starred', {
        headers: {
          "Authorization" => "Bearer #{token}",
          "cache-control" => "no-cache",
          "Content-Type" => "application/json"
        }
      })

      data = JSON.parse(response.body)
      data['episodes'].map do |episode_data|
        Episode.new(episode_data)
      end
    end

    def load_episode_database
      @episodes = if File.exist?('data/episodes.json')
        data = JSON.parse(File.read('data/episodes.json'))
        episodes = {}
        data.each do |uuid, episode_data|
          episode = Episode.new(episode_data['raw_data'])
          episode.instance_variable_set(:@notes, episode_data['notes'])
          episodes[uuid] = episode
        end
        episodes
      else
        {}
      end
    end

    def save_episode_database
      data = @episodes.transform_values(&:to_h)
      File.write('data/episodes.json', JSON.pretty_generate(data))
    end
  end
end 