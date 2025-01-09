require "forwardable"

require_relative "loose"
require_relative "packed"

class Database
  class Backends
    extend Forwardable
    def_delegators :@loose, :write_object

    def initialize(pathname)
      @pathname = pathname
      @loose = Loose.new(pathname)

      reload
    end

    def reload = @stores = [@loose] + packed

    def pack_path = @pathname.join("pack")

    def has?(oid) = @stores.any? { it.has?(oid) }

    def load_info(oid)
      @stores.reduce(nil) { |info, store| info || store.load_info(oid) }
    end

    def load_raw(oid)
      @stores.reduce(nil) { |raw, store| raw || store.load_raw(oid) }
    end

    def prefix_match(name)
      oids = @stores.reduce([]) do |list, store|
        list + store.prefix_match(name)
      end

      oids.uniq
    end

    private def packed
      packs = Dir.entries(pack_path).grep(/\.pack$/)
        .map { pack_path.join(it) }
        .sort_by { File.mtime(it) }
        .reverse

      packs.map { Packed.new(it) }
    rescue Errno::ENOENT
      []
    end
  end
end
