require 'open3'
require 'timeout'

module PocketcastCLI
  module Services
    # Handles audio playback functionality
    class PlayerService
      def initialize
        @player_pid = nil
        @position_thread = nil
        @start_time = nil
        @current_position = 0
      end
      
      # Start playback from a specific position
      def start_playback(episode, position = 0)
        return false unless episode.downloaded?
        
        begin
          # Kill any existing player process
          stop_playback
          
          # Start ffplay in its own process group
          cmd = "ffplay -nodisp -autoexit -ss #{position} '#{episode.download_path}' 2>/dev/null"
          @player_pid = Process.spawn(cmd, pgroup: true)
          @start_time = Time.now - position
          @current_position = position
          
          true
        rescue => e
          puts "Playback error: #{e.message}"
          false
        end
      end
      
      # Stop current playback
      def stop_playback
        if @player_pid
          begin
            # Kill the entire process group
            Process.kill('-TERM', @player_pid)
            
            # Wait for process to terminate with timeout
            Timeout.timeout(2) do
              Process.wait(@player_pid)
            end
          rescue Errno::ESRCH, Errno::ECHILD
            # Process already terminated
          rescue Timeout::Error
            # Force kill if timeout
            begin
              Process.kill('-KILL', @player_pid)
            rescue Errno::ESRCH
              # Process already gone
            end
          end
          @player_pid = nil
        end
        
        if @position_thread
          @position_thread.kill
          @position_thread = nil
        end
      end
      
      # Update playback position in real time
      def track_position(duration, &position_callback)
        # Stop existing tracking thread
        @position_thread&.kill
        
        # Start a new tracking thread
        @position_thread = Thread.new do
          while true
            sleep 0.1
            @current_position = (Time.now - @start_time).to_i
            
            # Check if we've reached the end of the file
            if @current_position >= duration
              position_callback.call(duration) if position_callback
              stop_playback
              break
            end
            
            position_callback.call(@current_position) if position_callback
          end
        end
      end
      
      # Get current playback position
      def current_position
        return 0 unless playing?
        @current_position
      end
      
      # Check if playback is active
      def playing?
        if @player_pid
          begin
            Process.getpgid(@player_pid)  # Check if process is still running
            return true
          rescue Errno::ESRCH
            # Process has ended
            @player_pid = nil
            return false
          end
        end
        
        false
      end
      
      # Cleanup all resources
      def cleanup
        stop_playback
      end
    end
  end
end