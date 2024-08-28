require "digest/sha1"
require "zlib"

require_relative "numbers"

module Pack
  class Writer
    Entry = Struct.new(:oid, :type)

    def initialize(output, database, options = {})
      @output = output
      @digest = Digest::SHA1.new
      @database = database

      @compression = options.fetch(:compression, Zlib::DEFAULT_COMPRESSION)
    end

    def write_objects(rev_list)
      prepare_pack_list(rev_list)
      write_header
      write_entries
      @output.write(@digest.digest)
    end

    private def prepare_pack_list(rev_list)
      @pack_list = []
      rev_list.each { add_to_pack_list(_1) }
    end

    private def add_to_pack_list(object)
      case object
      when Database::Commit
        @pack_list.push(Entry.new(object.oid, COMMIT))
      when Database::Entry
        type = object.tree? ? TREE : BLOB
        @pack_list.push(Entry.new(object.oid, type))
      end
    end

    private def write_header
      header = [SIGNATURE, VERSION, @pack_list.size].pack(HEADER_FORMAT)
      write(header)
    end

    private def write(data)
      @output.write(data)
      @digest.update(data)
    end

    private def write_entries = @pack_list.each { write_entry(_1) }

    private def write_entry(entry)
      object = @database.load_raw(entry.oid)

      header = Numbers::VarIntLE.write(object.size)
      header[0] |= entry.type << 4

      write(header.pack("C*"))
      write(Zlib::Deflate.deflate(object.data, @compression))
    end
  end
end
