require 'tty-cursor'
require 'tty-screen'
require 'tty-reader'
require 'pastel'
require 'open3'
require 'timeout'
require 'json'

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
      @start_time = nil
      
      # Transcript support
      @transcript_path = File.join('data/transcripts', "#{@episode.filename.sub('.mp3', '.json')}")
      @transcriber = Commands::Transcribe.new(@episode)
      @transcript = nil
      @current_transcript_index = 0
      @transcript_scroll_offset = 0
      @last_check_time = nil
      
      # Chat support
      @chat_mode = false
      @chat_input = ""
      @chat_history = []
      
      # UI layout tracking
      @player_height = 8  # Height for player controls
    end

    def run
      render
      setup_player
      
      # Start transcription if needed
      start_transcription if should_transcribe?
      
      loop do
        char = @reader.read_keypress(nonblock: true)
        if char
          handle_keyboard_event(char)
        end
        
        # Update playback status
        update_playback_status
        
        # Check transcription progress
        update_transcription_progress
        
        # Render screen
        render
        
        break if @exit_requested
        sleep 0.1  # Prevent CPU spinning
      end
    rescue => e
      # Ensure cleanup happens even on errors
      cleanup_player
      cleanup_transcription
      print @cursor.show  # Show cursor
      raise e  # Re-raise the error after cleanup
    ensure
      # Normal cleanup path
      cleanup_player
      cleanup_transcription
      print @cursor.show  # Show cursor
    end

    def handle_keyboard_event(char)
      case char
      when "\r", "\n"  # Enter
        toggle_playback
      when "\e[C"  # Right arrow
        seek_forward
      when "\e[D"  # Left arrow
        seek_backward
      when "\e[A"  # Up arrow
        move_to_previous_segment if @transcript
      when "\e[B"  # Down arrow
        move_to_next_segment if @transcript
      when "\e[5~"  # Page Up
        page_transcript_up if @transcript
      when "\e[6~"  # Page Down
        page_transcript_down if @transcript
      when "c"  # Chat mode
        enter_chat_mode if @transcript
      when "q", "\u0003"  # q or Ctrl-C
        stop_playback if @playing
        @exit_requested = true
      end
    end

    def enter_chat_mode
      return unless @transcript  # Guard against missing transcript
      
      # Create a new chat command instance with the episode object
      chat = Commands::Chat.new([@episode.uuid]) 
      
      # Clear screen for chat
      print @cursor.clear_screen
      print @cursor.show
      
      begin
        # Ensure transcript exists before starting chat
        chat.check_transcript
        
        # Stop playback while in chat mode
        was_playing = @playing
        stop_playback if @playing
        
        # Start chat session
        chat.start_chat
        
        # Restore playback if it was playing
        if was_playing
          @playing = start_playback
        end
      rescue => e
        # On chat error, ensure we restore the player screen and state
        print @cursor.hide
        render
        raise e  # Re-raise the error after restoring screen
      end
      
      # Restore player screen
      print @cursor.hide
      render
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

    def render_player(x, width)
      current_row = 2  # Start after status bar
      
      # Player title with transcription status
      print @cursor.move_to(x, current_row)
      title = "Audio Player"
      if !@transcriber.loaded? && @transcriber.started?
        title += " " + @pastel.yellow("(Transcribing...)")
      elsif @transcriber.loaded?
        title += " " + @pastel.cyan("(Transcript Available)")
      end
      puts @pastel.bold(title).center(width)
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
      return unless @transcript
      
      # Find current transcript segment based on playback position
      current_index = @transcript.rindex { |t| t[:timestamp] <= @current_position } || 0
      @current_transcript_index = current_index
      
      # Calculate visible range
      visible_lines = height
      preferred_position = visible_lines / 3  # Keep current line in top third
      
      # Adjust scroll offset to keep current line in preferred position
      target_scroll = [current_index - preferred_position, 0].max
      @transcript_scroll_offset = [
        target_scroll,
        @transcript.length - visible_lines
      ].min
      @transcript_scroll_offset = [0, @transcript_scroll_offset].max
      
      # Track how many screen lines we've used
      screen_line = 0
      
      # Display transcript lines
      visible_lines.times do |i|
        break if screen_line >= visible_lines
        
        line_index = @transcript_scroll_offset + i
        break if line_index >= @transcript.length
        
        transcript_line = @transcript[line_index]
        timestamp = Time.at(transcript_line[:timestamp]).utc.strftime("%M:%S")
        
        # Format line with timestamp
        text = transcript_line[:text]
        timestamp_width = 6  # "MM:SS "
        text_width = width - timestamp_width
        
        # Word wrap the text
        wrapped_lines = wrap_text(text, text_width)
        
        wrapped_lines.each_with_index do |wrapped_line, wrap_index|
          break if screen_line >= visible_lines
          
          # Move to correct position and print line
          print @cursor.move_to(x, y + screen_line)
          
          # For first line of wrapped text, include timestamp
          line = if wrap_index == 0
            "#{timestamp} #{wrapped_line}"
          else
            " " * timestamp_width + wrapped_line
          end
          
          if line_index == current_index
            # Highlight current line
            print @pastel.bold.bright_white.on_blue(line.ljust(width))
          elsif line_index < current_index
            # Dim past lines
            print @pastel.dim(line.ljust(width))
          else
            # Normal text for future lines
            print line.ljust(width)
          end
          
          screen_line += 1
        end
      end
      
      # Clear any remaining lines
      while screen_line < visible_lines
        print @cursor.move_to(x, y + screen_line)
        print " " * width
        screen_line += 1
      end
    end

    def render_status_bar(width, height)
      print @cursor.move_to(0, height - 2)
      puts "─" * width
      
      status = [
        "Enter: Play/Pause",
        "←/→: Seek 30s",
        "↑/↓: Navigate",
        "PgUp/PgDn: Page",
        "c: Chat",
        "q: Back"
      ].join(" | ")
      
      print status.center(width)
    end

    def setup_player
      return unless @episode.downloaded?
      
      @player_cmd = "ffplay"
      @player_type = :ffplay
      @debug_message = "Using ffplay for playback"
      
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
      if @playing
        stop_playback
        @playing = false
      else
        @playing = start_playback
      end
    end

    def start_playback
      return false unless @episode.downloaded?

      begin
        # Kill any existing player process
        stop_playback

        # Start ffplay in its own process group
        cmd = "ffplay -nodisp -autoexit -ss #{@current_position} '#{@episode.download_path}' 2>/dev/null"
        @player_pid = Process.spawn(cmd, pgroup: true)
        @start_time = Time.now - @current_position
        
        # Start a thread to update the position
        @position_thread = Thread.new do
          while @playing
            sleep 0.1
            new_position = (Time.now - @start_time).to_i
            
            # Check if we've reached the end of the file
            if new_position >= @duration
              @current_position = @duration
              @playing = false
              stop_playback
              break
            end
            
            @current_position = new_position
          end
        end

        true
      rescue => e
        @error_message = "Playback error: #{e.message}"
        false
      end
    end

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

    def seek_forward
      return unless @playing
      @current_position += 30
      restart_playback
    end

    def seek_backward
      return unless @playing
      @current_position = [@current_position - 30, 0].max
      restart_playback
    end

    def restart_playback
      stop_playback
      @playing = start_playback
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

    def move_to_previous_segment
      return unless @transcript && @current_transcript_index > 0
      @current_transcript_index -= 1
      @current_position = @transcript[@current_transcript_index][:timestamp]
      restart_playback if @playing
    end

    def move_to_next_segment
      return unless @transcript && @current_transcript_index < @transcript.length - 1
      @current_transcript_index += 1
      @current_position = @transcript[@current_transcript_index][:timestamp]
      restart_playback if @playing
    end

    def render
      # Clear screen and hide cursor
      print @cursor.clear_screen
      print @cursor.hide
      
      if @chat_mode
        render_chat
      else
        # Get terminal size
        width = TTY::Screen.width
        height = TTY::Screen.height
        
        # Reserve space for status bar
        status_height = 1
        available_height = height - status_height
        
        # Calculate player and transcript heights
        @player_height = 8  # Fixed height for player controls
        transcript_height = available_height - @player_height - 1  # -1 for spacing
        
        # Render main sections with proper spacing
        render_player(0, width)  # Start at line 1 to leave room for status
        render_transcript(0, @player_height + 1, width, transcript_height)
        render_status_bar(width, height)
      end
      
      # Flush output
      $stdout.flush
    end

    def should_transcribe?
      return false unless @episode.downloaded? # Need audio file
      !@transcriber.loaded? && !@transcriber.started?
    end

    def start_transcription
      # Create a new transcriber
      @transcriber = Commands::Transcribe.new(@episode)
      @last_check_time = Time.now - 2  # Force immediate check
      
      # Run execute in a background thread
      @transcription_thread = Thread.new do
        @transcriber.execute
      end

      @transcriber = Commands::Transcribe.new(@episode)
    end

    def update_transcription_progress
      return if @transcriber.loaded?  # Stop checking if transcript is complete
      return unless @episode.downloaded?

      # Check every second while transcribing
      if !@last_check_time || Time.now - @last_check_time >= 1
        @last_check_time = Time.now
        
        if current = @transcriber.current
          if current["items"]
            @transcript = current["items"].map do |item|
              # Convert timestamp to seconds
              time_parts = item['timestamp'].split(':').map(&:to_i)
              seconds = time_parts[0] * 60 + time_parts[1]
              {
                text: item['text'],
                timestamp: seconds
              }
            end
          end
        end
      end
    end

    def wrap_text(text, width)
      # Split into words
      words = text.split(/\s+/)
      lines = []
      current_line = []
      current_length = 0
      
      words.each do |word|
        # Check if adding this word would exceed width
        word_length = word.length + (current_line.empty? ? 0 : 1)  # +1 for space
        if current_length + word_length <= width
          current_line << word
          current_length += word_length
        else
          # Start new line
          lines << current_line.join(' ') unless current_line.empty?
          current_line = [word]
          current_length = word.length
        end
      end
      
      # Add final line
      lines << current_line.join(' ') unless current_line.empty?
      lines
    end

    def cleanup_transcription
      if @transcription_thread
        @transcription_thread.kill
        @transcription_thread = nil
      end
    end
  end
end 