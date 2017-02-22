require 'applb'
require 'optparse'
require 'pathname'

module Applb
  class CLI
    def self.start(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
      @help = argv.empty?
      @filepath = 'ALBfile'
      @options = {
        color: true,
        includes: [],
        excludes: [],
      }
      parser.order!(@argv)
    end

    def run
      if @help
        puts parser.help
      elsif @apply
        Apply.new(@filepath, @options).run
      elsif @export
        Export.new(@filepath, @options).run
      end
    end

    private

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.version = VERSION
        opts.on('-h', '--help', 'Show help') { @help = true }
        opts.on('-v', '--debug', 'Show debug log') { Applb.logger.level = Logger::DEBUG }
        opts.on('-a', '--apply', 'apply DSL') { @apply = true }
        opts.on('-e', '--export', 'export to DSL') { @export = true }
        opts.on('-n', '--dry-run', 'dry run') { @options[:dry_run] = true }
        opts.on('-f', '--file FILE', 'use selected DSL file') { |v| @filepath = v }
        opts.on('-s', '--split', 'split export DSL file to 1 per VPC') { @options[:split] = true }
        opts.on('',   '--split-more', 'split export DSL file to 1 per load balancer') { @options[:split_more] = true }
        opts.on('',   '--no-color', 'no color') { @options[:color] = false }
        opts.on('-i', '--include-names NAMES', 'include ELB v2(ALB) names', Array) { |v| @options[:includes] = v }
        opts.on('-x', '--exclude-names NAMES', 'exclude ELB v2(ALB) names by regex', Array) do |v|
          @options[:excludes] = v.map! do |name|
            name =~ /\A\/(.*)\/\z/ ? Regexp.new($1) : Regexp.new("\A#{Regexp.escape(name)}\z")
          end
        end
      end
    end

    class Apply
      def initialize(filepath, options)
        @filepath = filepath
        @options = options
      end

      def run
        require 'applb/client'
        result = Client.new(@filepath, @options).apply
      end
    end

    class Export
      def initialize(filepath, options)
        @filepath = filepath
        @options = options
      end

      def run
        require 'applb/client'
        result = Client.new(@filepath, @options).export
      end
    end
  end
end
