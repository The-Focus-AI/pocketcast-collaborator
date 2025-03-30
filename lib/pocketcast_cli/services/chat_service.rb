require 'tty-spinner'
require 'open3'
require 'pastel'
require 'tty-markdown'
require 'tty-screen'

module PocketcastCLI
  module Services
    # Handles all chat functionality using LLM models
    class ChatService
      def initialize(episode_service: nil, transcription_service: nil)
        @episode_service = episode_service || EpisodeService.new
        @transcription_service = transcription_service || TranscriptionService.new
        @pastel = Pastel.new
      end
      
      # Start an interactive chat session about a transcript
      def start_chat(episode, input_stream: $stdin, output_stream: $stdout)
        # Verify transcript exists
        transcript_path = Services::PathService.transcript_path(episode)
        
        unless File.exist?(transcript_path)
          output_stream.puts @pastel.red("No transcript found for: #{episode.title}")
          return false
        end
        
        output_stream.puts @pastel.cyan("Chatting about: #{episode.title}")
        output_stream.puts @pastel.cyan("Type your questions about the transcript. Press Enter with empty input or 'q' to exit.")
        output_stream.puts ""
        
        # Chat loop
        chat_history = []
        
        loop do
          # Get user input
          output_stream.print "> "
          begin
            question = input_stream.gets
            
            # Handle Ctrl-D
            if question.nil?
              output_stream.puts "\n#{@pastel.cyan("Goodbye!")}"
              return true
            end
            
            question = question.chomp
            
            # Exit on empty input or 'q'
            if question.strip.empty? || question.strip.downcase == 'q'
              output_stream.puts @pastel.cyan("Goodbye!")
              return true
            end
            
            # Execute chat query
            answer = execute_chat_query(question, transcript_path, chat_history, output_stream)
            
            # Add successful response to history
            if answer
              chat_history << {
                question: question,
                answer: answer.strip
              }
              
              # Add spacing after response
              output_stream.puts "\n"
            end
          rescue => e
            output_stream.puts "\n#{@pastel.red("Error: #{e.message}")}"
          end
        end
      end
      
      private
      
      # Execute a single chat query
      def execute_chat_query(question, transcript_path, chat_history, output_stream)
        # Prepare command
        cmd = if chat_history.empty?
          # First question - use full transcript
          "cat #{transcript_path} | llm \"#{question}\""
        else
          # Follow-up question - use chat context
          "llm -c \"#{question}\""
        end
        
        response = ""
        spinner = TTY::Spinner.new("[:spinner] Thinking...", format: :dots)
        spinner.auto_spin
        
        begin
          Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
            # Close stdin since we don't need it
            stdin.close
            
            # Set proper encoding for stdout
            stdout.set_encoding('UTF-8')
            
            # Read output as it comes in raw mode
            while chunk = stdout.readpartial(4096)
              spinner.stop if spinner.spinning?
              output_stream.print chunk
              response += chunk
            end
          rescue EOFError
            # Expected when stream ends
          end
          
          spinner.stop if spinner.spinning?

          # Show the raw markdown first
          output_stream.puts "\n\n#{@pastel.cyan("Raw markdown:")}"
          output_stream.puts response.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
          
          # Add a line break before showing formatted version
          output_stream.puts "\n#{@pastel.cyan("Formatted response:")}\n"
          
          # Calculate available width for word wrapping, leaving some margin
          width = TTY::Screen.width - 4
          
          # Format the response with proper encoding
          formatted_response = response.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').strip
          
          # Show formatted markdown version with some padding
          output_stream.puts TTY::Markdown.parse(formatted_response, width: width) + "\n"
          
          return response
        rescue => e
          spinner.stop if spinner.spinning?
          output_stream.puts "\n#{@pastel.red("Error: #{e.message}")}"
          return nil
        end
      end
    end
  end
end