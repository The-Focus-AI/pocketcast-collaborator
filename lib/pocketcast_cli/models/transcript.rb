require 'json'
require 'time'

module PocketcastCLI
  module Models
    # Represents a transcript for a podcast episode
    class Transcript
      attr_reader :items, :episode, :path, :loaded, :partial
      
      def initialize(episode)
        @episode = episode
        @path = Services::PathService.transcript_path(episode)
        @items = []
        @loaded = false
        @partial = false
        @loading = false
        @started = File.exist?(@path)
      end
      
      # Status methods
      def loaded?
        @loaded
      end
      
      def loading?
        @loading
      end
      
      def started?
        @started
      end
      
      # Load transcript data from file
      def load(force_reload: false, quiet: false)
        # Skip if already loaded and not forcing reload
        return @items if @loaded && !force_reload
        
        if !File.exist?(@path)
          puts "Transcript file does not exist: #{@path}" unless quiet
          return nil
        end
        
        puts "Loading transcript from #{@path}" if force_reload && !quiet
        
        data = File.read(@path)
        begin
          json = JSON.parse(data)
          puts "Successfully parsed transcript JSON" if force_reload && !quiet
          
          if json["items"].nil? || json["items"].empty?
            puts "Warning: Transcript file exists but has no items" if force_reload && !quiet
            @loaded = false
            return []
          end
          
          @items = json["items"].map do |item|
            # Convert timestamp to seconds
            time_parts = item['timestamp'].split(':').map(&:to_i)
            seconds = time_parts[0] * 60 + time_parts[1]
            {
              text: item['text'],
              timestamp: seconds,
              speaker: item['speaker']
            }
          end
          
          @loaded = true
          @partial = false
          puts "Loaded #{@items.size} transcript segments" if force_reload && !quiet
        rescue JSON::ParserError => e
          puts "JSON parse error: #{e.message}" unless quiet
          # Try to load partial transcript
          @items = try_loading_partial_json(data, quiet)
          puts "Loaded #{@items.size} partial transcript segments" unless quiet
          @partial = true
          @loaded = false  # Still not fully loaded
        rescue => e
          puts "Unexpected error loading transcript: #{e.class} - #{e.message}" unless quiet
          return nil
        end
        
        @items
      end
      
      private
      
      # Handle partial JSON for in-progress transcriptions
      def try_loading_partial_json(data, quiet = false)
        puts "Trying to parse partial JSON data..." unless quiet
        result = []
        
        # Check if the file has items array structure
        if data.include?('"items":')
          puts "File contains 'items' field - trying to extract complete objects" unless quiet
          # Try to extract any complete JSON objects from the items array
          json_objects = data.scan(/\{[^{}]*"timestamp"[^{}]*"text"[^{}]*\}|\{[^{}]*"text"[^{}]*"timestamp"[^{}]*\}/)
          
          puts "Found #{json_objects.size} potential JSON objects" unless quiet
          
          json_objects.each do |obj_str|
            begin
              # Try to parse each individual object
              obj = JSON.parse(obj_str)
              if obj["text"] && obj["timestamp"]
                # Convert timestamp to seconds
                time_parts = obj["timestamp"].split(':').map(&:to_i)
                seconds = time_parts[0] * 60 + time_parts[1]
                
                result << {
                  text: obj["text"],
                  timestamp: seconds,
                  speaker: obj["speaker"]
                }
              end
            rescue JSON::ParserError => e
              # Skip unparseable objects
              puts "Skipped unparseable object: #{obj_str[0..30]}..." unless quiet
            end
          end
        else
          # Try line-by-line approach for raw output
          puts "No 'items' field - trying line-by-line parsing" unless quiet
          lines = data.split("\n")
          
          lines.each do |line|
            # Look for timestamp pattern mm:ss
            if line =~ /(\d{1,2}):(\d{2})/
              timestamp_match = line.match(/(\d{1,2}):(\d{2})/)
              if timestamp_match
                minutes = timestamp_match[1].to_i
                seconds = timestamp_match[2].to_i
                total_seconds = minutes * 60 + seconds
                
                # Extract text after the timestamp
                text = line.sub(/.*?(\d{1,2}):(\d{2})/, '').strip
                
                if !text.empty?
                  result << {
                    text: text,
                    timestamp: total_seconds,
                    speaker: line.include?('Speaker') ? line.match(/Speaker\s*\d+/i)&.to_s : nil
                  }
                end
              end
            end
          end
        end
        
        puts "Successfully extracted #{result.size} transcript segments" unless quiet
        result
      end
    end
  end
end