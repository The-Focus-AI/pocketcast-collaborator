require_relative '../pocketcast'
require 'tty-spinner'
require 'open3'

module PocketcastCLI
  module Commands
    class Chat < Thor::Group
      include Thor::Actions

      argument :episode_id, type: :string, desc: "Episode ID to chat about"
      
      def initialize(*args)
        super
        @pc = Pocketcast.new
        @pastel = Pastel.new
        
        # If first argument is an Episode object, use it directly
        if args.first.is_a?(Array) && args.first.first.is_a?(PocketcastCLI::Episode)
          @episode = args.first.first
          @episode_id = @episode.uuid
          @transcript_path = File.join('data/transcripts', "#{@episode.filename.sub('.mp3', '.json')}")
        end
      end

      def find_episode
        # Skip if we already have an episode
        return if @episode
        
        # Sync episodes first if needed
        if @pc.episodes.empty?
          say "Syncing episodes from Pocketcast...", :yellow
          @pc.sync_recent_episodes
        end

        # Find episode where UUID starts with the given prefix
        @episode = @pc.episodes.values.find { |e| e.uuid.start_with?(episode_id) }
        unless @episode
          say "Episode not found with UUID starting with: #{episode_id}", :red
          exit 1
        end

        # Set the transcript path after finding the episode
        @transcript_path = File.join('data/transcripts', "#{@episode.filename.sub('.mp3', '.json')}")
      end

      def check_transcript
        # Find episode if not already set
        find_episode unless @episode
        
        # Check if transcript exists
        unless File.exist?(@transcript_path)
          say "No transcript found for: #{@episode.title}", :red
          exit 1
        end
      end

      def start_chat
        # Find episode if not already set
        find_episode unless @episode
        
        say "Chatting about: #{@episode.title}", :cyan
        say "Type your questions about the transcript. Press Enter with empty input or 'q' to exit.", :cyan
        say ""

        # Chat loop
        chat_history = []
        
        loop do
          # Get user input
          print "> "
          begin
            question = $stdin.gets
            # Handle Ctrl-D
            if question.nil?
              say "\nGoodbye!", :cyan
              return
            end
            
            question = question.chomp
            
            # Exit on empty input or 'q'
            if question.strip.empty? || question.strip.downcase == 'q'
              say "Goodbye!", :cyan
              return
            end
            
            # Prepare command
            cmd = if chat_history.empty?
              # First question - use full transcript
              "cat #{@transcript_path} | llm \"#{question}\""
            else
              # Follow-up question - use chat context
              "llm -c \"#{question}\""
            end

            puts "Executing command: #{cmd}"
            
            # Execute command with streaming output
            begin
              response = ""
              spinner = TTY::Spinner.new("[:spinner] Thinking...", format: :dots)
              spinner.auto_spin

              Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
                # Close stdin since we don't need it
                stdin.close

                # Read output as it comes in raw mode
                while chunk = stdout.readpartial(4096)
                  spinner.stop
                  print chunk
                  response += chunk
                end
              rescue EOFError
                # Expected when stream ends
              end

              spinner.stop
              
              # Add successful response to history
              chat_history << {
                question: question,
                answer: response.strip
              }
              
              # Add spacing after response
              say "\n"
            rescue => e
              spinner&.stop
              say "\nError: #{e.message}", :red
            end
          rescue => e
            say "\nError: #{e.message}", :red
          end
        end
      end
    end
  end
end 