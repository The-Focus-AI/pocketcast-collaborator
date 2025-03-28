require 'shellwords'
require 'json'
require 'time'
require 'fileutils'

module PocketcastCLI
  module Services
    # Handles all transcription-related functionality
    class TranscriptionService
      attr_reader :transcript
      
      def initialize
        @transcript_threads = {}
      end
      
      # Start the transcription process
      def transcribe(episode, output_to_console: true, &progress_callback)
        # Ensure model is loaded
        require_relative '../models/transcript'
        
        # Create transcript object
        @transcript = Models::Transcript.new(episode)
        
        # Skip if transcript already exists
        return @transcript if File.exist?(@transcript.path)
        
        # Ensure directories exist
        Services::PathService.ensure_transcript_directory
        
        # Start transcription in background thread
        thread = Thread.new do
          # Create a logger for non-console output
          log_buffer = []
          log_wrapper = output_to_console ? $stdout : log_buffer
          start_time = Time.now
          
          # Use the exact command format as specified
          command = "llm -m gemini-2.5-pro-exp-03-25 -a #{Shellwords.escape(episode.download_path)} --schema-multi 'timestamp str: mm:ss,text,speaker' transcript > #{Shellwords.escape(@transcript.path)}"
          
          def log(msg, wrapper)
            wrapper.is_a?(Array) ? wrapper << msg : wrapper.puts(msg)
          end
          
          log "Running transcription command...", log_wrapper
          log "Audio file path: #{episode.download_path}", log_wrapper
          log "Audio file exists: #{File.exist?(episode.download_path)}", log_wrapper
          log "Audio file size: #{File.size(episode.download_path)} bytes", log_wrapper
          log "Audio file readable: #{File.readable?(episode.download_path)}", log_wrapper
          log "Transcript path: #{@transcript.path}", log_wrapper
          log "Transcript directory: #{File.dirname(@transcript.path)}", log_wrapper
          log "Transcript directory exists: #{File.exist?(File.dirname(@transcript.path))}", log_wrapper
          log "Current working directory: #{Dir.pwd}", log_wrapper
          log "---", log_wrapper
          
          # Ensure transcript directory exists
          FileUtils.mkdir_p(File.dirname(@transcript.path))
          
          # Execute the command exactly as specified
          log "Executing transcription command: #{command}", log_wrapper
          success = system(command)
          log "Transcription command result: #{success ? "Success" : "Failed"}", log_wrapper
          
          if !success
            log "Command failed, checking for errors...", log_wrapper
            stderr_output = `#{command} 2>&1`
            log "Error output: #{stderr_output}", log_wrapper
          end
          
          # Calculate completion time
          end_time = Time.now
          duration = end_time - start_time
          
          if success
            log "Transcription completed in #{duration} seconds", log_wrapper
            progress_callback&.call(100)
          else
            log "Transcription failed after #{duration} seconds", log_wrapper
            progress_callback&.call(-1)
          end
          
          # Remove thread reference
          @transcript_threads.delete(episode.uuid)
          
          # No need to restore stdout since we're using a wrapper
        end
        
        # Store thread reference for later cleanup
        @transcript_threads[episode.uuid] = thread
        
        @transcript
      end
      
      # Get current transcript state
      def get_transcript(episode, force_reload: false, quiet: false)
        require_relative '../models/transcript'
        transcript = Models::Transcript.new(episode)
        transcript.load(force_reload: force_reload, quiet: quiet)
        transcript
      end
      
      # Check if transcription is in progress
      def transcribing?(episode)
        @transcript_threads.key?(episode.uuid) && @transcript_threads[episode.uuid].alive?
      end
      
      # Stop all transcription processes
      def cleanup
        @transcript_threads.each do |uuid, thread|
          thread.kill if thread.alive?
        end
        @transcript_threads.clear
      end
    end
  end
end