require "stringio"

require_relative "delta"
require_relative "numbers"

module Pack
  class Expander
    attr_reader :source_size, :target_size

    def self.expand(source, delta) = Expander.new(delta).expand(source)

    def initialize(delta)
      @delta = StringIO.new(delta)

      @source_size = read_size
      @target_size = read_size
    end

    def expand(source)
      check_size(source, @source_size)
      target = ""

      until @delta.eof?
        byte = @delta.readbyte

        if byte < 0x80
          insert = Delta::Insert.parse(@delta, byte)
          target += insert.data
        else
          copy = Delta::Copy.parse(@delta, byte)
          size = (copy.size == 0) ? GIT_MAX_COPY : copy.size
          target += source.byteslice(copy.offset, size)
        end
      end

      check_size(target, @target_size)
      target
    end

    private def read_size = Numbers::VarIntLE.read(@delta, 7)[1]

    private def check_size(buffer, size)
      raise "failed to apply delta" unless buffer.bytesize == size
    end
  end
end
