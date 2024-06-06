module Diff
  class Combined
    include Enumerable

    Row = Struct.new(:edits) do
      def to_s
        symbols = edits.map { |edit| SYMBOLS.fetch(edit&.type, " ") }

        del = edits.find { |edit| edit&.type == :del }
        line = del ? del.a_line : edits.first.b_line

        symbols.join("") + line.text
      end

      def type
        types = edits.compact.map(&:type)
        types.include?(:ins) ? :ins : types.first
      end

      def a_lines
        edits.map { |edit| edit&.a_line }
      end

      def b_line = edits.first&.b_line
    end

    def initialize(diffs)
      @difs = diffs
    end

    def each
      @offsets = @diffs.map { 0 }

      loop do
        @diffs.each_with_index do |diff, i|
          consume_deletions(diff, i) { |row| yield row }
        end

        return if complete?

        edits = offset_diffs.map { |offset, diff| diff[offset] }
        @offset.map! { |offset| offset + 1 }

        yield Row.new(edits)
      end
    end

    private def consume_deletions(diff, i)
      while @offsets[i] < diff.size && diff[@offsets[i]].type == :del
        edits = Array.new(@diffs.size)
        edits[i] = diff[@offsets[i]]
        @offsets[i] += 1

        yield Row.new(edits)
      end
    end

    private def offset_diffs = @offsets.zip(@diffs)

    private def complete?
      offset_diffs.all? { |offset, diff| offset == diff.size }
    end
  end
end
