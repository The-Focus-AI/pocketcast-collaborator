require 'tty-cursor'
require 'tty-screen'
require 'tty-reader'
require 'pastel'
require 'fileutils'
require 'reverse_markdown'

module PocketcastCLI
  class PodcastPlayer
    def initialize(episode, player_service = nil, transcription_service = nil, chat_service = nil, episode_service = nil)
      @episode = episode
      @cursor = TTY::Cursor
      @reader = TTY::Reader.new(interrupt: :exit)
      @pastel = Pastel.new
      @current_position = 0
      @duration = episode.duration
      @playing = false
      @error_message = nil
      @debug_message = nil
      @downloading = false
      @download_progress = 0
      
      # Services
      @player_service = player_service || Services::PlayerService.new
      @transcription_service = transcription_service || Services::TranscriptionService.new
      @chat_service = chat_service || Services::ChatService.new
      @episode_service = episode_service || Services::EpisodeService.new
      
      # Transcript support
      @transcript = nil
      @current_transcript_index = 0
      @transcript_scroll_offset = 0
      @last_check_time = nil
      @transcription_progress = 0
      
      # Chat availability flag
      @chat_available = false
      
      # UI layout tracking
      @player_height = 8  # Height for player controls
    end

    def run
      render
      
      # First, ensure the episode is downloaded
      unless @episode.downloaded?
        download_episode
      end
      
      # Setup player (must be called after download is complete)
      setup_player
      
      # Start transcription if needed
      start_transcription if should_transcribe?
      
      loop do
        char = @reader.read_keypress(nonblock: true)
        if char
          handle_keyboard_event(char)
        end
        
        # Update download progress if downloading
        update_download_progress if @downloading
        
        # Update playback status
        update_playback_status
        
        # Check transcription progress
        update_transcription_progress
        
        # Update chat availability based on transcript status
        update_chat_availability
        
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
    
    # Download the episode if not already downloaded
    def download_episode
      @downloading = true
      @download_progress = 0
      
      # Show download status
      render
      
      # Start download in a background thread
      @download_thread = Thread.new do
        @episode_service.download_episode(@episode) do |progress|
          @download_progress = progress
        end
        
        # When download completes
        @downloading = false
      end
      
      # Wait for download to complete
      while @downloading
        update_download_progress
        render
        sleep 0.1
      end
      
      # Re-check download status
      if @episode.downloaded?
        @debug_message = "Episode downloaded successfully"
      else
        @error_message = "Download failed or was interrupted"
      end
    end
    
    # Update the download progress
    def update_download_progress
      if @downloading && @download_thread && !@download_thread.alive?
        @downloading = false
      end
    end
    
    # Update chat availability based on transcript status
    def update_chat_availability
      transcript_status = get_transcript_status
      @chat_available = (transcript_status == :available)
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

    def page_transcript_up
      @transcript_scroll_offset = [@transcript_scroll_offset - 10, 0].max
    end
    
    def page_transcript_down
      max_offset = [@transcript.length - 10, 0].max
      @transcript_scroll_offset = [@transcript_scroll_offset + 10, max_offset].min
    end

    def enter_chat_mode
      # Only enter chat mode if transcript is fully available
      unless @chat_available
        @error_message = "Chat unavailable - waiting for transcription to complete"
        return
      end
      
      # Clear screen for chat
      print @cursor.clear_screen
      print @cursor.show
      
      begin
        # Stop playback while in chat mode
        was_playing = @playing
        stop_playback if @playing
        
        # Start chat session
        @chat_service.start_chat(@episode)
        
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
      
      # Episode ID
      print @cursor.move_to(0, current_row)
      puts "ID: #{@episode.uuid}"
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
      
      # Player title with status information
      print @cursor.move_to(x, current_row)
      
      if @downloading
        # Show download status
        title = "Downloading Episode: #{@download_progress}%"
        puts @pastel.bold.yellow(title).center(width)
      else
        # Get transcript state information from service
        transcript_status = get_transcript_status
        
        title = "Audio Player"
        if transcript_status == :transcribing
          title += " " + @pastel.yellow("(Transcribing...)")
        elsif transcript_status == :available
          title += " " + @pastel.cyan("(Transcript Available)")
        end
        
        # Add chat availability indicator
        if @chat_available
          title += " " + @pastel.green("(Chat Ready)")
        end
        
        puts @pastel.bold(title).center(width)
      end
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
      
      if @downloading
        # Show download progress bar
        print @cursor.move_to(x, current_row)
        bar_width = width - 2
        filled = (bar_width * @download_progress / 100.0).round
        bar = "▓" * filled + "░" * (bar_width - filled)
        puts "[#{bar}]"
        current_row += 1
        
        print @cursor.move_to(x, current_row)
        puts "Downloading... please wait".center(width)
      else
        # Progress bar for playback
        print @cursor.move_to(x, current_row)
        progress = (@current_position.to_f / [@duration, 1].max) # Avoid division by zero
        bar_width = width - 2
        filled = [(bar_width * progress).round, 0].max # Ensure it's not negative
        filled = [filled, bar_width].min # Ensure it's not too big
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
          "c Chat",
          "q Quit"
        ].join(" | ")
        puts controls.center(width)
      end
    end

    def render_transcript(x, y, width, height)
      # If no transcript is available yet, show a message
      if @transcript.nil? || @transcript.empty?
        print @cursor.move_to(x, y)
        if @transcription_service.transcribing?(@episode)
          print @pastel.dim("Transcribing... #{@transcription_progress}%")
        else
          print @pastel.dim("No transcript available")
        end
        return
      end

      # Calculate visible range
      visible_height = height - 1
      start_index = @transcript_scroll_offset
      end_index = [@transcript_scroll_offset + visible_height, @transcript.length].min

      # Display visible transcript segments
      current_y = y
      (@transcript[@transcript_scroll_offset...end_index] || []).each_with_index do |segment, idx|
        real_idx = idx + @transcript_scroll_offset
        
        # Format timestamp
        timestamp = format_duration(segment[:timestamp])
        
        # Format speaker if available
        speaker_text = segment[:speaker] ? " #{@pastel.cyan(segment[:speaker])}" : ""
        
        # Format the line with timestamp and speaker
        line = "#{timestamp}#{speaker_text} #{segment[:text]}"
        
        # Word wrap the text
        wrapped_lines = wrap_text(line, width)
        
        wrapped_lines.each do |wrapped_line|
          print @cursor.move_to(x, current_y)
          
          # Highlight current segment
          if real_idx == @current_transcript_index
            print @pastel.bold.on_blue(wrapped_line.ljust(width))
          else
            # Dim past segments, normal for future segments
            if real_idx < @current_transcript_index
              print @pastel.dim(wrapped_line.ljust(width))
            else
              print wrapped_line.ljust(width)
            end
          end
          
          current_y += 1
          break if current_y >= y + visible_height
        end
      end

      # Show scroll indicators if needed
      if @transcript_scroll_offset > 0
        print @cursor.move_to(width - 2, y)
        print @pastel.bright_black("↑")
      end
      if end_index < @transcript.length
        print @cursor.move_to(width - 2, y + visible_height - 1)
        print @pastel.bright_black("↓")
      end
    end

    def render_status_bar(width, height)
      print @cursor.move_to(0, height - 2)
      puts "─" * width
      
      # Show different controls based on state
      if @downloading
        status = [
          "Downloading episode...",
          "#{@download_progress}% complete",
          "Please wait"
        ].join(" | ")
      else
        # Get transcript status info
        transcript_status = get_transcript_status
        chat_status = @chat_available ? @pastel.green("Available") : @pastel.yellow("Unavailable")
        
        controls = [
          "Enter: Play/Pause",
          "←/→: Seek 30s",
          "↑/↓: Navigate"
        ]
        
        # Only show transcript navigation if transcript exists
        if @transcript
          controls << "PgUp/PgDn: Page"
        end
        
        # Show chat status
        controls << "c: Chat (#{chat_status})"
        controls << "q: Back"
        
        status = controls.join(" | ")
      end
      
      print status.center(width)
    end

    def setup_player
      return unless @episode.downloaded?
      
      @debug_message = "Using ffplay for playback"
      
      # Verify the audio file exists and is readable
      download_path = @episode.download_path
      
      unless File.exist?(download_path)
        @error_message = "Audio file not found: #{download_path}"
        return false
      end
      
      unless File.readable?(download_path)
        @error_message = "Audio file not readable: #{download_path}"
        return false
      end
      
      # Check file size
      file_size = File.size(download_path)
      if file_size == 0
        @error_message = "Audio file is empty (0 bytes). Try downloading again."
        return false
      end
      
      @debug_message = "#{@debug_message}\nAudio file: #{download_path} (#{file_size} bytes)"
      update_playback_status
    end

    def cleanup_player
      @player_service.cleanup
    end
    
    def cleanup_transcription
      @transcription_service.cleanup
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
      result = @player_service.start_playback(@episode, @current_position)
      
      if result
        # Start tracking position
        @player_service.track_position(@duration) do |position|
          @current_position = position
        end
      else
        @error_message = "Failed to start playback"
      end
      
      result
    end

    def stop_playback
      @player_service.stop_playback
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
      @playing = @player_service.playing?
      if @playing
        # Get current position from player
        @current_position = @player_service.current_position
        
        # Update transcript position if we have a transcript
        if @transcript && !@transcript.empty?
          # Find the transcript segment that matches our current position
          new_index = @transcript.rindex { |segment| segment[:timestamp].to_i <= @current_position } || 0
          
          # Only update if changed to avoid unnecessary redraws
          if new_index != @current_transcript_index
            @current_transcript_index = new_index
            
            # Calculate desired scroll position to maintain 1/3 past, 2/3 future ratio
            visible_height = TTY::Screen.height - @player_height - 3  # Adjust for player and margins
            past_context = (visible_height * 0.33).to_i  # Show 1/3 of what was said
            
            # Calculate ideal scroll position
            ideal_scroll = [@current_transcript_index - past_context, 0].max
            
            # Ensure we don't scroll too far (leave room for future content)
            max_scroll = [@transcript.length - visible_height, 0].max
            @transcript_scroll_offset = [ideal_scroll, max_scroll].min
          end
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
      
      # Only render transcript if we're not downloading and transcript exists
      unless @downloading
        render_transcript(0, @player_height + 1, width, transcript_height)
      end
      
      render_status_bar(width, height)
      
      # Flush output
      $stdout.flush
    end

    def should_transcribe?
      unless @episode.downloaded?
        @debug_message = "Cannot transcribe: Episode not downloaded"
        return false
      end
      
      # Quietly check transcript status
      transcript = @transcription_service.get_transcript(@episode, quiet: true)
      
      # If transcript file exists and has content
      if File.exist?(transcript.path) && File.size(transcript.path) > 0
        if transcript.loaded?
          @debug_message = "Transcript already fully loaded"
          return false
        end
        
        if transcript.started?
          @debug_message = "Transcript already started"
          return false
        end
        
        if @transcription_service.transcribing?(@episode)
          @debug_message = "Transcription already in progress"
          return false
        end
      end
      
      @debug_message = "Starting transcription..."
      return true
    end

    def start_transcription
      # Don't redirect standard output, just capture any potential output with a logger
      @debug_message = "Initializing transcription process..."
      
      # Run the transcription process with silent output
      result = @transcription_service.transcribe(@episode, output_to_console: false) do |progress|
        if progress == 100
          @debug_message = "Transcription completed successfully!"
        elsif progress == -1
          @error_message = "Transcription failed"
        end
      end
      
      if result
        @debug_message = "Transcription process started. This may take a few minutes."
      else
        @error_message = "Failed to start transcription process."
      end
      
      @last_check_time = Time.now - 2  # Force immediate check
    end

    def update_transcription_progress
      # Skip if we're downloading
      return if @downloading
      
      transcript_status = get_transcript_status
      
      # Check more frequently (every second) if transcribing
      if transcript_status == :transcribing
        if !@last_check_time || Time.now - @last_check_time >= 1
          @last_check_time = Time.now
          
          # Force reload transcript to get real-time updates, but quietly
          transcript = @transcription_service.get_transcript(@episode, force_reload: true, quiet: true)
          if transcript&.items && !transcript.items.empty?
            @transcript = transcript.items
            # Estimate progress based on audio duration and current transcript coverage
            last_timestamp = @transcript.last[:timestamp].to_i
            progress = (last_timestamp.to_f / @duration.to_f * 100).round
            @transcription_progress = [progress, 99].min # Cap at 99% until complete
            @debug_message = "Transcribing episode... #{@transcription_progress}% (#{@transcript.size} segments)"
          end
        end
      elsif transcript_status == :available
        if !@transcript
          # Load transcript if available but not loaded yet, quietly 
          transcript = @transcription_service.get_transcript(@episode, quiet: true)
          if transcript&.items && !transcript.items.empty?
            @transcript = transcript.items
            @transcription_progress = 100
            @debug_message = "Transcript available (#{@transcript.size} segments)"
          end
        else
          @transcription_progress = 100
        end
      else
        @transcription_progress = 0
        @debug_message = "No transcript available"
      end
      
      # Additional debug info
      if @transcript.nil? || @transcript.empty?
        @debug_message += " - Waiting for first transcript segments..."
      end
    end
    
    def get_transcript_status
      transcript = @transcription_service.get_transcript(@episode, quiet: true)
      
      return :none unless transcript
      
      if transcript.loaded?
        return :available
      elsif @transcription_service.transcribing?(@episode) || (!transcript.loaded? && transcript.started?)
        return :transcribing
      else
        return :none
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
  end
end