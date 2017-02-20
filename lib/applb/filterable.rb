module Applb
  module Filterable
    def target?(lb_name)
      unless @options[:includes].empty?
        return @options[:includes].include?(lb_name)
      end
      unless @options[:excludes].empty?
        return !@options[:excludes].any? { |regex| lb_name =~ regex }
      end
      true
    end
  end
end
