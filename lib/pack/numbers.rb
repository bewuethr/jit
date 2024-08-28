module Pack
  module Numbers
    module VarIntLE
      def self.write(value)
        bytes = []
        mask = 0xf
        shift = 4

        until value <= mask
          bytes << (0x80 | value & mask)
          value >>= shift

          mask, shift = 0x7f, 7
        end

        bytes + [value]
      end
    end
  end
end
