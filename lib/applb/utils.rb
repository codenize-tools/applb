require 'diffy'

module Applb
  class Utils
    class << self
      def normalize_hash(hash)
        hash.dup.each do |k, v|
          if v.kind_of?(Array)
            if v.first.kind_of?(Hash)
              hash[k] = v.map { |o| normalize_hash(o) }
            elsif v.first.respond_to?(:to_h)
              hash[k] = v.map { |o| normalize_hash(o.to_h) }
            end
          elsif v.respond_to?(:to_h)
            hash[k] = normalize_hash(v.to_h)
          end
        end
        sort_keys(hash)
      end

      def sort_keys(hash)
        hash = Hash[hash.sort]
        hash.each do |k, v|
          if v.kind_of?(Array)
            if v.first.kind_of?(Hash)
              hash[k] = v.map { |h| sort_keys(h) }
            end
          elsif v.kind_of?(Hash)
            hash[k] = sort_keys(v)
          end
        end
        hash
      end

      def diff(obj1, obj2, options = {})
        diffy = Diffy::Diff.new(
          obj1.pretty_inspect,
          obj2.pretty_inspect,
          :diff => '-u'
        )

        out = diffy.to_s(options[:color] ? :color : :text).gsub(/\s+\z/m, '')
        out.gsub!(/^/, options[:indent]) if options[:indent]
        out
      end
    end
  end
end
