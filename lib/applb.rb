require 'logger'
require 'applb/version'

module Applb
  def self.logger
    @logger ||=
      begin
        $stdout.sync = true
        Logger.new($stdout).tap do |l|
          l.level = Logger::INFO
        end
      end
  end
end
