$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'applb'
require 'hashie'
require 'yaml'
require 'pry'

aws_config_path = Pathname.new(File.expand_path('../', __FILE__)).join('aws_config.yml')
AWS_CONFIG = Hashie::Mash.new(YAML.load_file(aws_config_path))
