require_relative 'pocketcast_cli/version'
require_relative 'pocketcast_cli/cli'
require_relative 'pocketcast_cli/episode_selector'
require_relative 'pocketcast_cli/pocketcast'

module PocketcastCLI
  class Error < StandardError; end
end 