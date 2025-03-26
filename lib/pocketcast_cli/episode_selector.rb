require 'fileutils'
require 'reverse_markdown'
require 'tty-progressbar'
require_relative 'podcast_player'

module PocketcastCLI
  class EpisodeSelector
    SORT_OPTIONS = {
      date_published: "Date Published",
      list_order: "List Order"
    }

    def initialize(pocketcast)
      @pc = pocketcast
      @pastel = Pastel.new
      @prompt = TTY::Prompt.new
      @reader = TTY::Reader.new
      @cursor = TTY::Cursor
      
      # Create notes directory if it doesn't exist
      FileUtils.mkdir_p('data/notes')
      
      @filter_type = :all  # :all, :starred, :search
      @search_term = ""
      @selected_index = 0
      @scroll_offset = 0
      @filtered_episodes = []
      @sort_by = :date_published
      @original_order = []  # Keep track of original order from API
      @loading_notes = false
      @notes_thread = nil
      
      update_filtered_episodes
    end

    def run
      render
      loop do
        handle_input
        render
      end
    end

    def render
      width = TTY::Screen.width
      height = TTY::Screen.height
      
      # Split screen in half
      list_width = width / 2
      notes_width = width - list_width - 1  # -1 for separator
      
      # Hide cursor during rendering
      print @cursor.hide
      
      # Clear screen and reset cursor position
      print @cursor.clear_screen
      print @cursor.move_to(0, 0)
      
      # Calculate content height (leaving room for status bar)
      content_height = height - 3  # 1 for top bar, 2 for status bar
      
      # Render top bar
      render_top_bar(width)
      
      # Render episodes list
      render_episodes_list(list_width, content_height)
      
      # Draw vertical separator
      content_height.times do |i|
        print @cursor.move_to(list_width, i + 1)
        print "│"
      end
      
      # Render show notes
      render_show_notes(list_width + 1, content_height, notes_width)
      
      # Render status bar at bottom
      render_status_bar(width, height)
      
      # Ensure cursor is at the bottom
      print @cursor.move_to(0, height - 1)
    end

    def render_top_bar(width)
      filter_text = case @filter_type
      when :all then "All Episodes"
      when :starred then "Starred Episodes"
      when :search then "Search: #{@search_term}"
      end
      
      print @cursor.move_to(0, 0)
      puts @pastel.bold("#{filter_text}").ljust(width)
      puts "─" * width
    end

    def render_episodes_list(width, height)
      visible_episodes = @filtered_episodes[@scroll_offset, height]
      visible_episodes&.each_with_index do |episode, idx|
        relative_idx = idx + @scroll_offset
        
        # Move cursor to correct position
        print @cursor.move_to(0, idx + 2)  # +2 for top bar
        
        # Format date and title
        date = episode.published_at&.strftime("%Y-%m-%d") || "--"
        title = episode.title.to_s
        
        # Calculate available width for title
        title_width = width - date.length - 3  # 3 for spacing and cursor
        title = title[0, title_width].ljust(title_width)
        
        # Combine parts
        line = "#{date} #{title}"
        
        if relative_idx == @selected_index
          print @pastel.bold.bright_white.on_blue(line)
        else
          print line
        end
      end
      
      # Fill remaining lines with empty space
      remaining_lines = height - @filtered_episodes.length
      if remaining_lines > 0
        remaining_lines.times do |i|
          print @cursor.move_to(0, @filtered_episodes.length + 2 + i)
          print " " * width
        end
      end
    end

    def render_show_notes(x, height, width)
      return unless current_episode
      
      # Move to start position
      print @cursor.move_to(x, 2)  # After top bar
      
      # Show episode metadata
      current_row = 2  # Start after top bar
      
      # Podcast title
      print @cursor.move_to(x, current_row)
      puts @pastel.bold(current_episode.podcast_title.to_s[0, width])
      current_row += 1
      
      # Episode title
      print @cursor.move_to(x, current_row)
      puts @pastel.bold(current_episode.title.to_s[0, width])
      current_row += 1
      
      # Published date and duration
      print @cursor.move_to(x, current_row)
      date_str = "Published: #{current_episode.published_at.strftime("%Y-%m-%d %H:%M")}"
      duration_str = format_duration(current_episode.duration)
      meta_line = "#{date_str} | #{duration_str}"
      puts meta_line[0, width]
      current_row += 1
      
      # Status indicators
      print @cursor.move_to(x, current_row)
      status = []
      status << @pastel.green("Downloaded") if current_episode.downloaded?
      status << @pastel.yellow("Not Downloaded") unless current_episode.downloaded?
      status << @pastel.yellow("★ Starred") if current_episode.starred?
      puts status.join(" | ")[0, width]
      current_row += 1
      
      # Separator
      print @cursor.move_to(x, current_row)
      puts "─" * width
      current_row += 1
      
      # Add a blank line
      current_row += 1
      
      if @loading_notes
        print @cursor.move_to(x, current_row)
        puts @pastel.yellow("Loading show notes...")
        current_row += 1
      elsif current_episode.notes
        # Convert HTML to Markdown
        begin
          markdown = ReverseMarkdown.convert(current_episode.notes.to_s, unknown_tags: :bypass)
          
          # Clean up the markdown
          markdown = markdown
            .gsub(/\n\s*\n+/, "\n\n")  # Normalize multiple newlines
            .strip
          
          # Word wrap and display notes with proper markdown formatting
          markdown.each_line do |line|
            # Handle markdown headers and lists without wrapping
            if line.start_with?('#', '-', '*', '>', '    ', "\t")
              break if current_row >= height
              print @cursor.move_to(x, current_row)
              puts line.rstrip[0, width]
              current_row += 1
            else
              # Word wrap normal paragraphs
              line.strip.scan(/(.{1,#{width-1}})(?:\s+|$)/).flatten.each do |wrapped_line|
                break if current_row >= height
                print @cursor.move_to(x, current_row)
                puts wrapped_line.rstrip
                current_row += 1
              end
            end
          end
        rescue => e
          print @cursor.move_to(x, current_row)
          puts @pastel.red("Error converting show notes: #{e.message}")
          current_row += 1
        end
      else
        load_notes_async(current_episode)
      end
      
      # Clear remaining lines
      while current_row < height
        print @cursor.move_to(x, current_row)
        print " " * width
        current_row += 1
      end
    end

    def format_duration(seconds)
      return "--" unless seconds
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      
      if hours > 0
        "#{hours}h #{minutes}m"
      else
        "#{minutes}m"
      end
    end

    def render_status_bar(width, height)
      # Move to bottom of screen
      print @cursor.move_to(0, height - 2)
      
      # Draw separator
      puts "-" * width
      
      # Create status line
      sort_text = SORT_OPTIONS[@sort_by]
      filter_text = case @filter_type
        when :all then "All"
        when :starred then "Starred"
        when :search then "Search: #{@search_term}"
      end
      
      commands = [
        "q:Quit",
        "↑/↓:Navigate",
        "Enter:View Podcast",
        "/:Search",
        "s:Toggle Starred",
        "t:Sort(#{sort_text})",
        "d:Download"
      ]
      
      status = [
        @pastel.bold("Filter: ") + filter_text,
        @pastel.bold("Episodes: ") + @filtered_episodes.length.to_s,
        @pastel.bold("Commands: ") + commands.join(" ")
      ].join(" | ")

      print status[0, width]
    end

    def handle_input
      char = @reader.read_keypress
      case char
      when "\e[A" # Up arrow
        move_selection(-1)
      when "\e[B" # Down arrow
        move_selection(1)
      when "\e[5~" # Page up
        move_selection(-10)
      when "\e[6~" # Page down
        move_selection(10)
      when "\r", "\n" # Enter
        view_podcast_info if current_episode
      when "q", "\u0003" # q or Ctrl-C
        exit
      when "s"
        @filter_type = @filter_type == :starred ? :all : :starred
        reset_selection
        update_filtered_episodes
      when "t"
        cycle_sort_order
      when "d"
        download_current if current_episode
      when "/"
        enter_search_mode
      end
    end

    def cycle_sort_order
      current_keys = SORT_OPTIONS.keys
      current_index = current_keys.index(@sort_by)
      @sort_by = current_keys[(current_index + 1) % current_keys.length]
      update_filtered_episodes
    end

    def download_current
      return unless current_episode
      @pc.download_episode(current_episode)
      render  # Refresh display after download
    end

    def enter_search_mode
      height = TTY::Screen.height
      width = TTY::Screen.width
      
      # Show cursor during search
      print @cursor.show
      
      # Clear the bottom line
      print @cursor.move_to(0, height - 1)
      print " " * width
      
      # Show search prompt
      print @cursor.move_to(0, height - 1)
      print "Search: "
      
      search_buffer = ""
      loop do
        # Clear line and show current search
        print @cursor.move_to(8, height - 1)
        print " " * (width - 8)  # Clear rest of line
        print @cursor.move_to(8, height - 1)
        print search_buffer
        
        char = @reader.read_keypress
        case char
        when "\r", "\n"  # Enter
          break
        when "\u007F", "\b"  # Backspace
          if search_buffer.length > 0
            search_buffer.slice!(-1)
            @search_term = search_buffer
            @filter_type = :search
            update_filtered_episodes
            render
          end
        when "\e"  # Escape
          @search_term = ""
          @filter_type = :all
          update_filtered_episodes
          break
        when "\e[A"  # Up arrow
          move_selection(-1)
          render
          # Restore search prompt and cursor
          print @cursor.move_to(0, height - 1)
          print "Search: #{search_buffer}"
          print @cursor.show
        when "\e[B"  # Down arrow
          move_selection(1)
          render
          # Restore search prompt and cursor
          print @cursor.move_to(0, height - 1)
          print "Search: #{search_buffer}"
          print @cursor.show
        when "\e[5~"  # Page up
          move_selection(-10)
          render
          # Restore search prompt and cursor
          print @cursor.move_to(0, height - 1)
          print "Search: #{search_buffer}"
          print @cursor.show
        when "\e[6~"  # Page down
          move_selection(10)
          render
          # Restore search prompt and cursor
          print @cursor.move_to(0, height - 1)
          print "Search: #{search_buffer}"
          print @cursor.show
        else
          if char =~ /[[:print:]]/  # Printable characters
            search_buffer << char
            @search_term = search_buffer
            @filter_type = :search
            update_filtered_episodes
            render
          end
        end
      end

      # Hide cursor and restore screen
      print @cursor.hide
      render
    end

    def move_selection(delta)
      new_index = @selected_index + delta
      return if new_index < 0 || new_index >= @filtered_episodes.length
      
      @selected_index = new_index
      
      # Adjust scroll if selection would be off screen
      visible_height = TTY::Screen.height - 6  # Account for headers and status bar
      if @selected_index < @scroll_offset
        @scroll_offset = @selected_index
      elsif @selected_index >= @scroll_offset + visible_height
        @scroll_offset = @selected_index - visible_height + 1
      end
      
      # Load notes for newly selected episode
      load_notes_async(current_episode) if current_episode
    end

    def reset_selection
      @selected_index = 0
      @scroll_offset = 0
    end

    def update_filtered_episodes
      episodes = case @filter_type
      when :all
        @pc.episodes.values
      when :starred
        @pc.episodes.values.select(&:starred?)
      when :search
        return [] if @search_term.empty?
        @pc.episodes.values.select do |ep|
          ep.title.downcase.include?(@search_term.downcase) ||
            ep.podcast_title.downcase.include?(@search_term.downcase)
        end
      end

      # Keep track of original order if needed
      @original_order = episodes if @sort_by == :list_order

      @filtered_episodes = sort_episodes(episodes)
      reset_selection if @selected_index >= @filtered_episodes.length
    end

    def sort_episodes(episodes)
      case @sort_by
      when :date_published
        episodes.sort_by { |e| e.published_at || Time.at(0) }.reverse
      when :list_order
        @original_order || episodes
      end
    end

    def current_episode
      @filtered_episodes[@selected_index]
    end

    def view_podcast_info
      return unless current_episode
      
      # Start download if needed
      unless current_episode.downloaded?
        # Clear screen and show download interface
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)
        
        width = TTY::Screen.width
        height = TTY::Screen.height
        
        # Show episode info at top
        puts @pastel.bold(current_episode.podcast_title)
        puts @pastel.bold(current_episode.title)
        puts "Duration: #{format_duration(current_episode.duration)}"
        puts
        puts "─" * width
        puts
        
        begin
          progress_bar = TTY::ProgressBar.new(
            "[:bar] :percent",
            total: 100,
            width: width - 10,
            complete: "▓",
            incomplete: "░"
          )
          
          @pc.download_episode(current_episode) do |progress|
            # Progress comes as a percentage (0-100), but TTY::ProgressBar expects absolute value
            progress_bar.current = progress
          end
          
          puts "\nDownload complete!"
          sleep 1  # Brief pause to show completion
        rescue => e
          print @cursor.clear_screen
          print @cursor.move_to(0, 0)
          puts @pastel.red("Error downloading episode:")
          puts @pastel.red(e.message)
          puts
          puts "Press any key to return..."
          @reader.read_keypress
          return
        end
      end
      
      # Start the player
      player = PodcastPlayer.new(current_episode)
      player.run
    end

    private

    def load_notes_async(episode)
      return if @loading_notes || episode.notes
      
      @loading_notes = true
      @notes_thread&.kill
      
      @notes_thread = Thread.new do
        begin
          # Try to load from cache first
          notes_file = File.join('data/notes', "#{episode.uuid}.txt")
          if File.exist?(notes_file)
            notes = File.read(notes_file)
            episode.instance_variable_set(:@notes, notes)
          else
            # Fetch from API and cache
            @pc.fetch_episode_notes(episode)
            if episode.notes
              File.write(notes_file, episode.notes)
            end
          end
        rescue => e
          # Error already handled in fetch_episode_notes
        ensure
          @loading_notes = false
          render  # Update screen after notes are loaded
        end
      end
      @notes_thread.abort_on_exception = false  # Don't crash the main thread on error
    end

    def wrap_text(text, width)
      text.gsub(/(.{1,#{width}})(\s+|$)/, "\\1\n").strip
    end
  end
end 