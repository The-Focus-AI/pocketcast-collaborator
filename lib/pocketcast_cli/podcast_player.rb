require 'tty-cursor'
require 'tty-screen'
require 'tty-reader'
require 'pastel'
require 'open3'
require 'timeout'

module PocketcastCLI
  class PodcastPlayer
    def initialize(episode)
      @episode = episode
      @cursor = TTY::Cursor
      @reader = TTY::Reader.new(interrupt: :exit)
      @pastel = Pastel.new
      @current_position = 0
      @duration = episode.duration
      @playing = false
      @player_pid = nil
      @position_thread = nil
      @player_type = nil
      @error_message = nil
      @debug_message = nil
    end

    def run
      render
      setup_player
      
      loop do
        char = @reader.read_keypress(nonblock: true)
        if char
          case char
          when "\r", "\n"  # Enter
            toggle_playback
          when "\e[C"  # Right arrow
            seek(30)
          when "\e[D"  # Left arrow
            seek(-30)
          when "q", "\u0003"  # q or Ctrl-C
            @exit_requested = true
          end
        end
        
        # Update playback status
        update_playback_status
        
        # Render screen
        render
        
        break if @exit_requested
        sleep 0.1  # Prevent CPU spinning
      end
      
      cleanup_player
    end

    private

    def render
      width = TTY::Screen.width
      height = TTY::Screen.height
      
      # Split screen in half
      left_width = width / 2
      right_width = width - left_width - 1
      
      # Clear screen and hide cursor
      print @cursor.hide
      print @cursor.clear_screen
      print @cursor.move_to(0, 0)
      
      # Calculate content areas
      content_height = height - 3  # Leave room for status bar
      player_height = 8  # Height of player controls section
      transcript_height = content_height - player_height
      
      # Render metadata (left side)
      render_metadata(left_width, content_height)
      
      # Draw vertical separator
      content_height.times do |i|
        print @cursor.move_to(left_width, i + 1)
        print "│"
      end
      
      # Render player and transcript (right side)
      render_player(left_width + 1, player_height, right_width)
      render_transcript(left_width + 1, player_height + 1, right_width, transcript_height)
      
      # Render status bar
      render_status_bar(width, height)
      
      # Position cursor at bottom
      print @cursor.move_to(0, height - 1)
    end

    def render_metadata(width, height)
      current_row = 0
      
      # Podcast title
      print @cursor.move_to(0, current_row)
      puts @pastel.bold(@episode.podcast_title.to_s[0, width])
      current_row += 2
      
      # Episode title
      print @cursor.move_to(0, current_row)
      puts @pastel.bold(@episode.title.to_s[0, width])
      current_row += 2
      
      # Published date and duration
      print @cursor.move_to(0, current_row)
      date_str = "Published: #{@episode.published_at.strftime("%Y-%m-%d %H:%M")}"
      duration_str = format_duration(@episode.duration)
      meta_line = "#{date_str} | #{duration_str}"
      puts meta_line[0, width]
      current_row += 1
      
      # Status indicators
      print @cursor.move_to(0, current_row)
      status = []
      status << @pastel.green("Downloaded") if @episode.downloaded?
      status << @pastel.yellow("Not Downloaded") unless @episode.downloaded?
      status << @pastel.yellow("★ Starred") if @episode.starred?
      puts status.join(" | ")[0, width]
      current_row += 2
      
      # Show notes
      print @cursor.move_to(0, current_row)
      puts "Show Notes:"
      puts "─" * width
      current_row += 2
      
      if @episode.notes
        notes = ReverseMarkdown.convert(@episode.notes.to_s, unknown_tags: :bypass)
        notes.each_line do |line|
          break if current_row >= height
          print @cursor.move_to(0, current_row)
          puts line.strip[0, width]
          current_row += 1
        end
      end
    end

    def render_player(x, height, width)
      current_row = 1  # Start after top margin
      
      # Player title
      print @cursor.move_to(x, current_row)
      puts @pastel.bold("Audio Player").center(width)
      current_row += 2
      
      # Show any error messages
      if @error_message
        print @cursor.move_to(x, current_row)
        puts @pastel.red(@error_message[0, width])
        current_row += 2
      end
      
      # Show debug message if present
      if @debug_message
        print @cursor.move_to(x, current_row)
        puts @pastel.dim(@debug_message[0, width])
        current_row += 2
      end
      
      # Progress bar
      print @cursor.move_to(x, current_row)
      progress = @current_position.to_f / @duration
      bar_width = width - 2
      filled = (bar_width * progress).round
      bar = "▓" * filled + "░" * (bar_width - filled)
      puts "[#{bar}]"
      current_row += 1
      
      # Time display
      print @cursor.move_to(x, current_row)
      time_display = "#{format_duration(@current_position)} / #{format_duration(@duration)}"
      puts time_display.center(width)
      current_row += 2
      
      # Controls
      print @cursor.move_to(x, current_row)
      status = @playing ? "▶ Playing" : "⏸ Paused"
      controls = [
        "↵ #{status}",
        "← -30s",
        "→ +30s",
        "q Quit"
      ].join(" | ")
      puts controls.center(width)
    end

    def render_transcript(x, y, width, height)
      print @cursor.move_to(x, y)
      puts "Transcript:"
      puts "─" * width
      
      # TODO: Implement transcript display once we have transcript data
      print @cursor.move_to(x, y + 2)
      puts @pastel.dim("Transcript not available")
    end

    def render_status_bar(width, height)
      print @cursor.move_to(0, height - 2)
      puts "─" * width
      
      status = [
        "Enter: Play/Pause",
        "←/→: Seek 30s",
        "q: Back to Episodes"
      ].join(" | ")
      
      print status.center(width)
    end

    def setup_player
      return unless @episode.downloaded?
      
      @player_cmd = "afplay"
      @player_type = :afplay
      @debug_message = "Using afplay for playback"
      
      # Verify the audio file exists and is readable
      unless File.exist?(@episode.download_path)
        @error_message = "Audio file not found: #{@episode.download_path}"
        return false
      end
      
      unless File.readable?(@episode.download_path)
        @error_message = "Audio file not readable: #{@episode.download_path}"
        return false
      end
      
      # Check file size
      file_size = File.size(@episode.download_path)
      if file_size == 0
        @error_message = "Audio file is empty (0 bytes). Try downloading again."
        return false
      end
      
      @debug_message = "#{@debug_message}\nAudio file: #{@episode.download_path} (#{file_size} bytes)"
      update_playback_status
    end

    def cleanup_player
      @position_thread&.kill
      @position_thread = nil
      
      if @player_pid
        begin
          # Check if process is still running
          if Process.getpgid(@player_pid)
            # Try SIGTERM first
            Process.kill("TERM", @player_pid)
            # Wait for process to end, but only if it's our child
            begin
              Process.wait(@player_pid, Process::WNOHANG)
            rescue Errno::ECHILD
              # Process is not our child or already gone
              nil
            end
          end
        rescue Errno::ESRCH
          # Process already gone
          nil
        ensure
          @player_pid = nil
        end
      end
      
      @player_thread&.kill
      @player_thread = nil
      @debug_message = nil
      @error_message = nil
    end

    def toggle_playback
      return unless @episode.downloaded?
      
      if @playing
        cleanup_player
        @playing = false
      else
        @playing = true  # Set playing state before starting playback
        unless start_playback
          # If playback failed, reset playing state
          @playing = false
        end
      end
    end

    def start_playback
      return false unless @episode.downloaded?
      
      # Make absolutely sure old player is cleaned up
      cleanup_player if @player_pid
      
      # Calculate start time based on current position
      start_time = Time.now
      
      # Build command - afplay doesn't support seeking, so we'll handle that in the UI
      cmd = "#{@player_cmd} '#{@episode.download_path}'"
      
      # Log the command being run
      @debug_message = "Running: #{cmd}"
      
      begin
        # Start the player process
        stdin, stdout, stderr, thread = Open3.popen3(cmd)
        @player_pid = thread.pid
        
        # Monitor process in a single thread
        @player_thread = Thread.new do
          begin
            # Wait for process to complete
            status = thread.value
            
            # Check if process exited successfully
            unless status.success?
              @error_message = "Player exited with status #{status.exitstatus}"
              @playing = false
            end
          ensure
            # Clean up streams
            [stdin, stdout, stderr].each { |s| s.close rescue nil }
            
            # Update state when process ends
            @playing = false
            @player_pid = nil
            @position_thread&.kill
            @position_thread = nil
          end
        end
        
        # Start a thread to track playback position
        @position_thread&.kill
        @position_thread = Thread.new do
          while @playing
            sleep 1
            elapsed = Time.now - start_time
            @current_position = elapsed.to_i if @current_position < @duration
          end
        end
        @position_thread.abort_on_exception = false
        
        return true  # Successfully started
        
      rescue => e
        @error_message = "Failed to start player: #{e.message}"
        @playing = false
        return false
      end
    end

    def seek(seconds)
      return unless @episode.downloaded?
      
      new_position = @current_position + seconds
      new_position = 0 if new_position < 0
      new_position = @duration if new_position > @duration
      
      @current_position = new_position
      
      # Always restart playback if playing
      if @playing
        was_playing = true
        cleanup_player
        start_playback
        @playing = was_playing
      end
    end

    def restart_playback
      return unless @playing
      @playing = false
      cleanup_player
      start_playback
      @playing = true
    end

    def format_duration(seconds)
      return "--:--" unless seconds
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      secs = seconds % 60
      
      if hours > 0
        "%02d:%02d:%02d" % [hours, minutes, secs]
      else
        "%02d:%02d" % [minutes, secs]
      end
    end

    def update_playback_status
      if @playing && @player_pid
        begin
          Process.getpgid(@player_pid)  # Check if process is still running
        rescue Errno::ESRCH
          # Process has ended
          @playing = false
          @player_pid = nil
          @position_thread&.kill
          @position_thread = nil
        end
      end
    end
  end
end 