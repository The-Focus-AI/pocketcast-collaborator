require 'tty-prompt'
require 'pastel'
require 'tty-box'
require 'tty-cursor'
require 'tty-screen'
require 'io/console'

module PocketcastCLI
  module Commands
    class EpisodeSelector
      def initialize(pocketcast_service)
        @pocketcast = pocketcast_service
        @prompt = TTY::Prompt.new
        @pastel = Pastel.new
        @cursor = TTY::Cursor
        @episodes = @pocketcast.episodes.values.reject { |e| e.title.to_s.include?("Example Episode") }
        puts "Loaded #{@episodes.size} real episodes"
        @filter = nil
        @sort = :date
        @search = nil
        @search_type = :text
        @selected_index = 0
        @transcription_service = Services::TranscriptionService.new
      end
      
      def run
        filtered_episodes = filter_episodes
        
        # Initial rendering
        render_screen(filtered_episodes)
        
        # Create a TTY::Reader instance for key input
        reader = TTY::Reader.new
        
        # Main loop
        loop do
          input = reader.read_keypress(nonblock: false)
          
          # Skip navigation if no episodes
          if filtered_episodes.empty?
            case input
            when "f" # Filter - cycle through filter options
              cycle_filter
              filtered_episodes = filter_episodes
              @selected_index = 0
              render_screen(filtered_episodes)
            when "s" # Sort - cycle through sort options
              cycle_sort
              filtered_episodes = filter_episodes
              @selected_index = 0
              render_screen(filtered_episodes)
            when "*" # Toggle starred status
              toggle_starred_filter
              filtered_episodes = filter_episodes
              @selected_index = 0
              render_screen(filtered_episodes)
            when "/" # Start interactive search
              start_interactive_search
              filtered_episodes = filter_episodes
              @selected_index = 0
              render_screen(filtered_episodes)
            when "r" # Refresh
              refresh_episodes
              filtered_episodes = filter_episodes
              @selected_index = 0
              render_screen(filtered_episodes)
            when "q", "\u0003" # q or Ctrl-C
              print @cursor.show
              break
            end
            next
          end
          
          case input
          when "k", "\e[A" # k or Up arrow
            @selected_index = (@selected_index - 1) % filtered_episodes.length
            render_screen(filtered_episodes)
          when "j", "\e[B" # j or Down arrow
            @selected_index = (@selected_index + 1) % filtered_episodes.length
            render_screen(filtered_episodes)
          when " ", "\r", "\n" # Space or Enter
            # Enter playback mode
            play_episode(filtered_episodes[@selected_index])
            
            # Refresh in case we need to update transcription status
            filtered_episodes = filter_episodes
            render_screen(filtered_episodes)
          when "f" # Filter - cycle through filter options
            cycle_filter
            filtered_episodes = filter_episodes
            @selected_index = 0
            render_screen(filtered_episodes)
          when "*" # Toggle starred status
            toggle_starred_filter
            filtered_episodes = filter_episodes
            @selected_index = 0
            render_screen(filtered_episodes)
          when "s" # Sort - cycle through sort options
            cycle_sort
            filtered_episodes = filter_episodes
            @selected_index = 0
            render_screen(filtered_episodes)
          when "/" # Start interactive search
            start_interactive_search
            filtered_episodes = filter_episodes
            @selected_index = 0
            render_screen(filtered_episodes)
          when "r" # Refresh
            refresh_episodes
            filtered_episodes = filter_episodes
            @selected_index = 0
            render_screen(filtered_episodes)
          when "q", "\u0003" # q or Ctrl-C
            print @cursor.show
            break
          end
        end
      end
      
      private
      
      def filter_episodes
        # Start with all episodes
        result = @episodes
        
        # Apply filter
        if @filter
          case @filter
          when :downloaded
            result = result.select(&:downloaded?)
          when :starred
            result = result.select(&:starred?)
          when :archived
            result = result.select(&:archived?)
          when :transcribed
            result = result.select { |e| File.exist?(Services::PathService.transcript_path(e)) }
          end
        end
        
        # Apply search
        if @search && !@search.empty?
          if @search_type == :longest
            # Get top 10% longest episodes
            duration_sorted = result.sort_by { |e| -e.duration.to_i }
            result = duration_sorted.take((result.size * 0.1).ceil)
          elsif @search_type == :shortest
            # Get top 10% shortest episodes, excluding those with 0 duration
            valid_episodes = result.reject { |e| e.duration.to_i == 0 }
            duration_sorted = valid_episodes.sort_by { |e| e.duration.to_i }
            result = duration_sorted.take((valid_episodes.size * 0.1).ceil)
          else
            # Regular text search
            search_term = @search.downcase
            result = result.select do |episode|
              episode.title.downcase.include?(search_term) ||
                episode.podcast_title.to_s.downcase.include?(search_term)
            end
          end
        end
        
        # Apply sort
        result = sort_episodes(result)
        
        result
      end
      
      def sort_episodes(episodes)
        case @sort
        when :date
          episodes.sort_by { |e| e.published_at ? -e.published_at.to_i : 0 }
        when :duration
          episodes.sort_by { |e| -e.duration.to_i }
        when :duration_asc
          # Sort by ascending duration, but exclude 0 duration episodes
          valid_episodes = episodes.reject { |e| e.duration.to_i == 0 }
          invalid_episodes = episodes.select { |e| e.duration.to_i == 0 }
          valid_episodes.sort_by { |e| e.duration.to_i } + invalid_episodes
        when :podcast
          episodes.sort_by { |e| [e.podcast_title.to_s, e.published_at ? -e.published_at.to_i : 0] }
        else
          episodes
        end
      end
      
      def render_screen(episodes)
        # Clear screen and hide cursor
        print @cursor.clear_screen
        print @cursor.hide
        
        # Get dimensions
        width = TTY::Screen.width
        height = TTY::Screen.height
        
        # Calculate panel dimensions
        left_panel_width = width / 2
        right_panel_width = width - left_panel_width
        
        # Layout sections
        render_top_bar(width)
        render_episode_list(episodes, 1, 1, left_panel_width - 1, height - 3)
        render_episode_details(episodes[@selected_index], left_panel_width + 1, 1, right_panel_width - 2, height - 3)
        render_bottom_bar(width, height)
      end
      
      def render_top_bar(width)
        # Search bar at the top
        print @cursor.move_to(0, 0)
        
        # Show appropriate search prompt
        if @search && !@search.empty?
          search_display = "Search: #{@search}"
        else
          search_display = "Press / to search, s to toggle ★, t to cycle sort"
        end
        
        title = "Pocketcast Episodes"
        
        bar_content = "#{title} | #{search_display}"
        print @pastel.bold.on_blue(bar_content.ljust(width))
      end
      
      def render_bottom_bar(width, height)
        # Filter info and controls at the bottom
        print @cursor.move_to(0, height - 2)
        
        # Status message or separator line
        if @status_message
          print @pastel.bold.on_blue(@status_message.ljust(width))
        else
          print @pastel.dim("─" * width)
        end
        
        # Footer with commands
        print @cursor.move_to(0, height - 1)
        
        # Status information
        filter_info = "Filter: #{filter_display} | Sort: #{sort_display}"
        
        # Controls
        controls = "↑/↓:Select | Enter:Play | f:Filter | s:Sort | *:Star | /:Search | r:Refresh | q:Quit"
        
        # Print status and controls
        footer = "#{filter_info}#{controls.rjust(width - filter_info.length)}"
        print @pastel.bold.on_blue(footer.ljust(width))
        
        # Clear status message after displaying it
        @status_message = nil
      end
      
      def render_episode_list(episodes, x, y, width, height)
        # Frame for the episode list
        print @cursor.move_to(x, y)
        
        if episodes.empty?
          # Show message when no episodes match filter
          print @cursor.move_to(x, y + 1)
          message = case @filter
                   when :downloaded
                     "No downloaded episodes"
                   when :starred
                     "No starred episodes"
                   when :archived
                     "No archived episodes"
                   when :transcribed
                     "No transcribed episodes"
                   else
                     "No episodes found"
                   end
          print @pastel.dim(message.center(width))
          return
        end
        
        # Calculate visible range
        visible_height = height - 1
        start_index = [0, @selected_index - (visible_height / 2)].max
        end_index = [start_index + visible_height, episodes.length].min
        
        # Display episodes
        (start_index...end_index).each_with_index do |idx, row|
          episode = episodes[idx]
          print @cursor.move_to(x, y + row)
          
          # Format episode info
          title = episode.title.to_s
          duration = format_duration(episode.duration)
          
          # Status indicators
          downloaded = episode.downloaded? ? @pastel.green("↓") : " "
          starred = episode.starred? ? @pastel.yellow("★") : " "
          transcribed = File.exist?(Services::PathService.transcript_path(episode)) ? @pastel.cyan("T") : " "
          
          # Calculate available width for title
          status_width = 4  # Space for status indicators
          duration_width = duration.length
          spacing = 2  # Minimal spacing
          max_title_length = width - status_width - duration_width - spacing
          
          # Truncate title if needed
          title = truncate_text(title, max_title_length)
          
          # Format the line
          line = "#{downloaded}#{starred}#{transcribed} #{title}#{duration.rjust(width - title.length - status_width)}"
          
          # Highlight selected episode
          if idx == @selected_index
            print @pastel.bold.on_blue(line.ljust(width))
          else
            print line.ljust(width)
          end
        end
      end
      
      def render_episode_details(episode, x, y, width, height)
        return unless episode
        
        # Episode details header
        print @cursor.move_to(x, y)
        print @pastel.bold("Episode Details")
        
        # Podcast title
        print @cursor.move_to(x, y + 2)
        podcast_title = episode.podcast_title.to_s
        print @pastel.bold("Podcast: ") + podcast_title[0, width - 10]
        
        # Episode title
        print @cursor.move_to(x, y + 3)
        episode_title = episode.title.to_s
        print @pastel.bold("Title: ") + episode_title[0, width - 8]
        
        # Published date
        print @cursor.move_to(x, y + 4)
        published = episode.published_at ? episode.published_at.strftime("%Y-%m-%d %H:%M") : "Unknown"
        print @pastel.bold("Published: ") + published
        
        # Duration
        print @cursor.move_to(x, y + 5)
        duration = format_duration(episode.duration)
        print @pastel.bold("Duration: ") + duration
        
        # Episode ID
        print @cursor.move_to(x, y + 6)
        print @pastel.bold("ID: ") + episode.uuid
        
        # Status
        print @cursor.move_to(x, y + 7)
        status = []
        status << @pastel.green("Downloaded") if episode.downloaded?
        status << @pastel.yellow("★ Starred") if episode.starred?
        
        # Transcript status
        transcript_path = episode.transcript_path
        if File.exist?(transcript_path)
          status << @pastel.cyan("Transcript Available")
        end
        
        if status.empty?
          print @pastel.bold("Status: ") + "No special status"
        else
          print @pastel.bold("Status: ") + status.join(", ")
        end
        
        # Show notes
        print @cursor.move_to(x, y + 9)
        print @pastel.bold("Show Notes:")
        
        if episode.notes
          # Process notes
          notes = episode.notes.to_s.gsub(/<\/?[^>]*>/, "") # Remove HTML tags
          
          # Calculate available space
          available_lines = height - 11  # Header + metadata + episode ID + show notes title
          
          # Wrap and display notes
          wrapped_notes = word_wrap(notes, width - 2)
          displayed_lines = wrapped_notes.take(available_lines)
          
          displayed_lines.each_with_index do |line, i|
            print @cursor.move_to(x, y + 10 + i)
            print line
          end
          
          # Show continuation indicator if notes are longer
          if wrapped_notes.size > available_lines
            print @cursor.move_to(x, y + 10 + available_lines - 1)
            print @pastel.dim("... more notes available")
          end
        else
          print @cursor.move_to(x, y + 10)
          print "(No show notes available)"
        end
      end
      
      def truncate_text(text, max_length)
        return "" if text.nil?
        
        # Strip ANSI color codes for length calculation
        plain_text = text.to_s.gsub(/\e\[[\d;]+m/, '')
        
        return text if plain_text.length <= max_length
        
        # If text is too long, truncate it and add ellipsis
        # We need to be careful with ANSI codes, so let's use simple truncation
        truncated = ""
        current_length = 0
        chars = text.chars
        
        i = 0
        ansi_sequence = false
        
        while i < chars.length && current_length < max_length - 3
          char = chars[i]
          
          if char == "\e" && chars[i+1] == '['
            # Start of ANSI sequence
            ansi_sequence = true
            truncated << char
          elsif ansi_sequence
            # Within ANSI sequence
            truncated << char
            ansi_sequence = false if char == 'm'
          else
            # Normal character
            truncated << char
            current_length += 1
          end
          
          i += 1
        end
        
        truncated + "..."
      end
      
      def word_wrap(text, width)
        return [] if text.nil? || text.empty?
        
        # Remove ANSI codes for wrapping calculation
        plain_text = text.gsub(/\e\[[\d;]+m/, '')
        
        lines = []
        # Simple word wrap that doesn't try to handle ANSI codes
        plain_text.gsub(/(.{1,#{width}})(\s+|$)/, "\\1\n").split("\n").each do |line|
          lines << line
        end
        
        lines
      end
      
      # Cycle through filter options without showing menu
      def cycle_filter
        # Define the filter options in order
        filter_options = [nil, :downloaded, :starred, :archived, :transcribed]
        
        # Find current filter index and move to next
        current_index = filter_options.index(@filter) || 0
        @filter = filter_options[(current_index + 1) % filter_options.length]
      end
      
      # Classic filter method with full menu
      def change_filter
        # Restore cursor
        print @cursor.show
        
        @filter = @prompt.select("Filter by:", per_page: 5) do |menu|
          menu.choice "All episodes", nil
          menu.choice "Downloaded only", :downloaded
          menu.choice "Starred only", :starred
          menu.choice "Archived only", :archived
          menu.choice "Transcribed only", :transcribed
        end
        
        # Hide cursor again
        print @cursor.hide
      end
      
      # Cycle through sort options without showing menu
      def cycle_sort
        # Define the sort options in order
        sort_options = [:date, :duration, :duration_asc, :podcast]
        
        # Find current sort index and get the next one
        current_index = sort_options.index(@sort) || 0
        next_index = (current_index + 1) % sort_options.length
        @sort = sort_options[next_index]
        
        # Show notification of the new sort
        notify("Sort: #{sort_display}")
      end
      
      # Get current cursor position
      def get_cursor_position
        # This is a hack since TTY doesn't expose current cursor position
        # Just return a safe position for now
        [0, 0]
      end
      
      # Toggle starred filter on/off
      def toggle_starred_filter
        # If currently filtering by starred, turn it off
        # Otherwise, turn on starred filter
        if @filter == :starred
          @filter = nil
          notify("Filter: All episodes")
        else
          @filter = :starred
          notify("Filter: Starred only")
        end
      end
      
      # Cycle through time sorting options
      def cycle_time_sort
        # Define the cycle order: published date -> shortest -> longest -> published date
        time_sorts = [:date, :duration_asc, :duration, :date]
        
        # Find current sort index and get the next one
        current_index = time_sorts.index(@sort) || 0
        next_index = (current_index + 1) % time_sorts.length
        @sort = time_sorts[next_index]
        
        notify("Sort: #{sort_display}")
      end
      
      # Show a notification message in a consistent way
      def notify(message)
        @status_message = message
        render_screen(@filtered_episodes || [])
      end
      
      # Start interactive search mode
      def start_interactive_search
        # Save current cursor position and show it
        print @cursor.show
        
        # Get screen dimensions
        width = TTY::Screen.width
        
        # Clear the top bar area for search input
        print @cursor.move_to(0, 0)
        print " " * width
        
        # Show search prompt
        print @cursor.move_to(0, 0)
        print @pastel.on_blue("Search: ")
        
        # Initialize search buffer
        search_buffer = ""
        search_pos = 8 # Position after "Search: "
        
        # Set up for reading characters
        reader = TTY::Reader.new
        char = nil
        
        # Get initial filtered episodes
        temp_episodes = filter_episodes
        
        # Main search loop
        loop do
          # Move cursor to current input position
          print @cursor.move_to(search_pos, 0)
          
          # Read a key
          char = reader.read_keypress
          
          case char
          when "\r", "\n" # Enter - finish search
            @search = search_buffer.empty? ? nil : search_buffer
            @search_type = :text
            break
          when "\u007F", "\b" # Backspace/Delete
            if search_buffer.length > 0
              # Remove last character
              search_buffer = search_buffer[0..-2]
              search_pos -= 1
              
              # Update display
              print @cursor.move_to(0, 0)
              print @pastel.on_blue("Search: " + search_buffer.ljust(width - 8))
              
              # Apply search in real time
              @search = search_buffer.empty? ? nil : search_buffer
              @search_type = :text
              temp_episodes = filter_episodes
              render_episode_list_in_search(temp_episodes, 1, 1, width / 2 - 1, TTY::Screen.height - 3)
            end
          when "\u0003" # Ctrl-C - cancel search
            @search = nil
            @search_type = nil
            break
          when "\e" # Escape sequence start
            # Read the next two characters for arrow keys
            seq1 = reader.read_keypress
            if seq1 == '['
              seq2 = reader.read_keypress
              case seq2
              when 'A' # Up arrow
                @selected_index = (@selected_index - 1) % temp_episodes.length
                render_episode_list_in_search(temp_episodes, 1, 1, width / 2 - 1, TTY::Screen.height - 3)
                print @cursor.move_to(search_pos, 0)
              when 'B' # Down arrow
                @selected_index = (@selected_index + 1) % temp_episodes.length
                render_episode_list_in_search(temp_episodes, 1, 1, width / 2 - 1, TTY::Screen.height - 3)
                print @cursor.move_to(search_pos, 0)
              end
            else
              # Regular escape - cancel search
              @search = nil
              @search_type = nil
              break
            end
          else
            # Only add printable characters
            if char =~ /[[:print:]]/
              # Add character to buffer
              search_buffer += char
              search_pos += 1
              
              # Update display
              print @cursor.move_to(0, 0)
              print @pastel.on_blue("Search: " + search_buffer.ljust(width - 8))
              
              # Apply search in real time
              @search = search_buffer
              @search_type = :text
              temp_episodes = filter_episodes
              render_episode_list_in_search(temp_episodes, 1, 1, width / 2 - 1, TTY::Screen.height - 3)
            end
          end
        end
        
        # Hide cursor again after search is complete
        print @cursor.hide
      end
      
      # Simplified episode list renderer for real-time search
      def render_episode_list_in_search(episodes, x, y, width, height)
        # Calculate visible range - similar to render_episode_list but simplified
        visible_height = height - 1
        max_to_show = [visible_height, episodes.length].min
        
        # Display episodes - similar to render_episode_list but without title
        episodes.each_with_index do |episode, index|
          # Skip episodes outside visible range
          next if index >= max_to_show
          
          # Calculate position
          line_y = y + 1 + index
          print @cursor.move_to(x, line_y)
          
          # Format line (simplified)
          title = truncate_text(episode.title.to_s, width - 12)
          date = episode.published_at ? episode.published_at.strftime("%m-%d") : "??"
          
          # Build line with date and title
          line = "#{date} #{title}"
          
          # Highlight selected episode
          if index == @selected_index
            print @pastel.bold.on_blue(line.ljust(width))
          else
            print line.ljust(width)
          end
        end
        
        # Clear any remaining lines if fewer results than before
        (max_to_show...visible_height).each do |i|
          print @cursor.move_to(x, y + 1 + i)
          print " " * width
        end
      end
      
      def change_search
        # Restore cursor
        print @cursor.show
        
        # Enhanced search options
        search_type = @prompt.select("Search by:", per_page: 5) do |menu|
          menu.choice "Text Search", :text
          menu.choice "Longest Duration", :longest
          menu.choice "Shortest Duration", :shortest
          menu.choice "Clear Search", :clear
        end
        
        case search_type
        when :text
          @search = @prompt.ask("Search episodes (title or podcast name):") || ""
          @search_type = :text
        when :longest
          @search = "longest"
          @search_type = :longest
        when :shortest
          @search = "shortest"
          @search_type = :shortest
        when :clear
          @search = nil
          @search_type = nil
        end
        
        # Hide cursor again
        print @cursor.hide
      end
      
      def change_sort
        # Restore cursor
        print @cursor.show
        
        @sort = @prompt.select("Sort by:", per_page: 5) do |menu|
          menu.choice "Date (newest first)", :date
          menu.choice "Duration (longest first)", :duration
          menu.choice "Duration (shortest first)", :duration_asc
          menu.choice "Podcast name", :podcast
        end
        
        # Hide cursor again
        print @cursor.hide
      end
      
      def refresh_episodes
        # Restore cursor
        print @cursor.show
        
        puts "Refreshing episodes..."
        @pocketcast.sync_recent_episodes
        @episodes = @pocketcast.episodes.values
        puts "Done! #{@episodes.count} episodes loaded."
        sleep(1) # Give user a chance to see the message
        
        # Hide cursor again
        print @cursor.hide
      end
      
      def play_episode(episode)
        # Restore cursor
        print @cursor.show
        
        # Clear screen before player starts
        print @cursor.clear_screen
        
        puts "Starting playback: #{episode.title}" 
        puts "Episode ID: #{episode.uuid}"
        puts "Downloaded: #{episode.downloaded?}"
        
        # Create a new episode service connected to the same pocketcast
        episode_service = PocketcastCLI::Services::EpisodeService.new(@pocketcast)
        
        # Pass the same pocketcast instance to maintain state
        player = PocketcastCLI::PodcastPlayer.new(
          episode,
          PocketcastCLI::Services::PlayerService.new,
          PocketcastCLI::Services::TranscriptionService.new,
          PocketcastCLI::Services::ChatService.new,
          episode_service
        )
        
        player.run
      end
      
      def filter_display
        case @filter
        when :downloaded
          "Downloaded"
        when :starred
          "Starred"
        when :archived
          "Archived"
        when :transcribed
          "Transcribed"
        else
          "All"
        end
      end
      
      def search_display
        if @search && !@search.empty?
          case @search_type
          when :longest
            "Top 10% Longest Episodes"
          when :shortest
            "Top 10% Shortest Episodes"
          else
            @search
          end
        else
          "None"
        end
      end
      
      def sort_display
        case @sort
        when :date
          "Date (newest first)"
        when :duration
          "Duration (longest first)"
        when :duration_asc
          "Duration (shortest first)"
        when :podcast
          "Podcast name"
        else
          "Default"
        end
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
    end
  end
end