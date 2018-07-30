require 'applb'
require 'optparse'
require 'pathname'

require 'aws-sdk-core'
Aws.use_bundled_cert!

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
      @aws_opts = {}
      parser.order!(@argv)

      aws_config = {}
      if @aws_opts[:access_key] and @aws_opts[:secret_key]
        aws_config.update(
          :access_key_id => @aws_opts[:access_key],
          :secret_access_key => @aws_opts[:secret_key]
        )
      elsif @aws_opts[:profile_name] or @aws_opts[:credentials_path]
        credentials_opts = {}
        credentials_opts[:profile_name] = @aws_opts[:profile_name] if @aws_opts[:profile_name]
        credentials_opts[:path] = @aws_opts[:credentials_path] if @aws_opts[:credentials_path]
        credentials = Aws::SharedCredentials.new(credentials_opts)
        aws_config[:credentials] = credentials
      elsif (@aws_opts[:access_key] and !@aws_opts[:secret_key]) or (!@aws_opts[:access_key] and @aws_opts[:secret_key])
        puts parser.help
        exit 1
      end

      aws_config[:region] = @aws_opts[:region] if @aws_opts[:region]
      @options[:aws_config] = aws_config
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
        opts.on('-p', '--profile PROIFILE_NAME')                                      {|v| @aws_opts[:profile_name]     = v             }
        opts.on('',   '--credentials-path PATH')                                      {|v| @aws_opts[:credentials_path] = v             }
        opts.on('-k', '--access-key ACCESS_KEY')                                      {|v| @aws_opts[:access_key]       = v             }
        opts.on('-s', '--secret-key SECRET_KEY')                                      {|v| @aws_opts[:secret_key]       = v             }
        opts.on('-r', '--region REGION')                                              {|v| @aws_opts[:region]           = v             }
        opts.on('-h', '--help', 'Show help')                                          {    @help                        = true          }
        opts.on('-v', '--debug', 'Show debug log')                                    {    Applb.logger.level           = Logger::DEBUG }
        opts.on('-a', '--apply', 'apply DSL')                                         {    @apply                       = true          }
        opts.on('-e', '--export', 'export to DSL')                                    {    @export                      = true          }
        opts.on('-n', '--dry-run', 'dry run')                                         {    @options[:dry_run]           = true          }
        opts.on('-f', '--file FILE', 'use selected DSL file')                         {|v| @filepath                    = v             }
        opts.on('-s',   '--split', 'split export DSL file to 1 per VPC')              {    @options[:split]             = true          }
        opts.on('',   '--split-more', 'split export DSL file to 1 per load balancer') {    @options[:split_more]        = true          }
        opts.on('',   '--no-color', 'no color')                                       {    @options[:color]             = false         }
        opts.on('-i', '--include-names NAMES', 'include ELB v2(ALB) names', Array)    {|v| @options[:includes]          = v             }
        opts.on('-x', '--exclude-names NAMES', 'exclude ELB v2(ALB) names by regex, or comma-separated ELB names', Array) do |v|
          @options[:excludes] = v.map! do |name|
            name =~ %r{\A/(.*)/\z} ? Regexp.new(Regexp.last_match(1)) : /\A#{Regexp.escape(name)}\z/
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
