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
      profile_name     = nil
      credentials_path = nil
      access_key       = nil
      secret_key       = nil
      region           = nil

      @parser ||= OptionParser.new do |opts|
        opts.version = VERSION
        opts.on('-p', '--profile PROIFILE_NAME')                                      {|v| profile_name         = v             }
        opts.on('',   '--credentials-path PATH')                                      {|v| credentials_path     = v             }
        opts.on('-k', '--access-key ACCESS_KEY')                                      {|v| access_key           = v             }
        opts.on('-s', '--secret-key SECRET_KEY')                                      {|v| secret_key           = v             }
        opts.on('-r', '--region REGION')                                              {|v| region               = v             }
        opts.on('-h', '--help', 'Show help')                                          {    @help                 = true          }
        opts.on('-v', '--debug', 'Show debug log')                                    {    Applb.logger.level    = Logger::DEBUG }
        opts.on('-a', '--apply', 'apply DSL')                                         {    @apply                = true          }
        opts.on('-e', '--export', 'export to DSL')                                    {    @export               = true          }
        opts.on('-n', '--dry-run', 'dry run')                                         {    @options[:dry_run]    = true          }
        opts.on('-f', '--file FILE', 'use selected DSL file')                         {|v| @filepath             = v             }
        opts.on('',   '--split', 'split export DSL file to 1 per VPC')                {    @options[:split]      = true          }
        opts.on('',   '--split-more', 'split export DSL file to 1 per load balancer') {    @options[:split_more] = true          }
        opts.on('',   '--no-color', 'no color')                                       {    @options[:color]      = false         }
        opts.on('-i', '--include-names NAMES', 'include ELB v2(ALB) names', Array)    {|v| @options[:includes]   = v             }
        opts.on('-x', '--exclude-names NAMES', 'exclude ELB v2(ALB) names by regex', Array) do |v|
          @options[:excludes] = v.map! do |name|
            name =~ /\A\/(.*)\/\z/ ? Regexp.new($1) : Regexp.new("\A#{Regexp.escape(name)}\z")
          end
        end
      end

      aws_opts = {}
      if access_key and secret_key
        aws_opts.update(
          :access_key_id => access_key,
          :secret_access_key => secret_key
        )
      elsif profile_name or credentials_path
        credentials_opts = {}
        credentials_opts[:profile_name] = profile_name if profile_name
        credentials_opts[:path] = credentials_path if credentials_path
        credentials = Aws::SharedCredentials.new(credentials_opts)
        aws_opts[:credentials] = credentials
      elsif (access_key and !secret_key) or (!access_key and secret_key)
        puts opt.help
        exit 1
      end

      aws_opts[:region] = region if region
      Aws.config.update(aws_opts)

      @parser
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
