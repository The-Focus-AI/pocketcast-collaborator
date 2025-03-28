require 'active_support/core_ext/string/inflections'
require 'securerandom'

module PocketcastCLI
  module Models
    class Episode
      attr_reader :uuid, :title, :podcast_title, :published_at, :audio_url, :podcast_uuid, :duration, :notes, :last_played_at
      
      def initialize(data, podcast_title = nil)
        data ||= {}  # Ensure data is not nil
        
        @uuid = data['uuid'] || SecureRandom.uuid
        @title = data['title'] || "Unknown Title"
        @podcast_title = podcast_title || data['podcastTitle'] || data['podcast_title'] || "Unknown Podcast"
        
        # Handle different date formats
        if data['published']
          @published_at = Time.parse(data['published']) rescue Time.at(data['published'].to_i)
        elsif data['published_at']
          @published_at = Time.parse(data['published_at']) rescue Time.at(data['published_at'].to_i) 
        else
          @published_at = Time.now
        end
        
        @audio_url = data['url'] || data['audio_url'] || ""
        @podcast_uuid = data['podcastUuid'] || data['podcast_uuid']
        @duration = data['duration'] || 0
        @data = data
        @notes = data['notes'] || data['show_notes']
        
        # Status flags
        @starred = data['starred'] == true
        @played = data['played'] == true
        @archived = data['archived'] == true
        
        # Fix playing status access
        if data['playingStatus'].is_a?(Hash) && data['playingStatus']['playedUpTo']
          @last_played_at = Time.at(data['playingStatus']['playedUpTo'].to_i)
        else
          @last_played_at = nil
        end
      end
      
      def filename
        "#{title.to_s.parameterize}-#{uuid[0..5]}.mp3"
      end
      
      def download_path
        File.join('mp3s', filename)
      end
      
      def transcript_path
        File.join('data/transcripts', "#{filename.sub('.mp3', '.json')}")
      end
      
      def downloaded?
        File.exist?(download_path) && File.size(download_path) > 0
      end
      
      def starred?
        @starred
      end
      
      def played?
        @played
      end
      
      def archived?
        @archived
      end
      
      def to_h
        {
          'uuid' => @uuid,
          'title' => @title,
          'podcast_title' => @podcast_title,
          'published_at' => @published_at ? @published_at.iso8601 : nil,
          'audio_url' => @audio_url,
          'podcast_uuid' => @podcast_uuid,
          'duration' => @duration,
          'starred' => @starred,
          'played' => @played,
          'archived' => @archived,
          'show_notes' => @notes,
          'last_played_at' => @last_played_at&.iso8601,
          'raw_data' => @data
        }
      end
    end
  end
end