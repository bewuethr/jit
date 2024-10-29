require_relative "numbers"

module Pack
  class Delta
    Copy = Struct.new(:offset, :size) do
      def to_s
        bytes = Numbers::PackedInt56LE.write((size << 32) | offset)
        bytes[0] |= 0x80
        bytes.pack("C*")
      end
    end

    Insert = Struct.new(:data) do
      def to_s = [data.bytesize, data].pack("Ca*")
    end
  end
end
