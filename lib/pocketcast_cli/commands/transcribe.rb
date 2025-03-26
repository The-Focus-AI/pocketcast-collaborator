require 'json'
require 'shellwords'
require 'time'

module PocketcastCLI
  module Commands
    class Transcribe
      def initialize(episode)
        @episode = episode
        @transcript_path = File.join('data/transcripts', "#{episode.filename.sub('.mp3', '.json')}")
        @loading = false
        @loaded = false
        @started = File.exist?(@transcript_path)
      end

      def loaded?
        @loaded
      end

      def loading?
        @loading
      end

      def started?
        @started
      end

      def execute
        return if File.exist?(@transcript_path)
        
        @loading = true
        ensure_transcript_directory
        @start_time = Time.now

        command = "llm -m gemini-2.5-pro-exp-03-25 transcribe -a #{Shellwords.escape(@episode.download_path)} --schema-multi 'timestamp str: mm:ss,text' > #{Shellwords.escape(@transcript_path)}"
        
        puts "Running command: #{command}"
        puts "Audio file exists: #{File.exist?(@episode.download_path)}"
        puts "Audio file size: #{File.size(@episode.download_path)} bytes"
        puts "---"

        system(command)
        
        @end_time = Time.now
        @duration = @end_time - @start_time
        puts "Transcription completed in #{@duration} seconds"
      end

      def current
        return @current if @current

        return nil if !File.exist?(@transcript_path)
        data = File.read(@transcript_path)
        begin
          @current = JSON.parse(data)
          @loaded = true
        rescue JSON::ParserError
          puts "trying to load partial json"
          return try_loading_partial_json(data)
        end

        @current
      end
      
      def try_loading_partial_json(data)
        # Initialize empty items array
        @current = {"items" => []}
        
        # Split data into tokens and try to assemble JSON objects
        tokens = data.scan(/:|".*"|{|}|\]|\[|,/)
        current_item = nil
        
        tokens.each do |token|
          next if token.strip.empty?
          case token
          when '{'
            current_item = {}
          when '}'
            @current["items"] << current_item if current_item && current_item["text"] && current_item["timestamp"]
            current_item = nil
          end


          if token.include?(':') and token.length > 1
            pos = token.index(':')
            key = token[0..pos-1].strip.gsub('"','')
            value = token[pos+1..-1].strip.gsub('"','')
            current_item[key] = value if current_item
          end
        rescue => e
            puts e
          # Stop processing on error
          break
        end

        @partial = true
        @current
      end
      private

      def ensure_transcript_directory
        dir = File.dirname(@transcript_path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
      end
    end
  end
end 