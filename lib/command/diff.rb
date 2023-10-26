require_relative "base"
require_relative "../repository"

module Command
  class Diff < Base
    NULL_OID = "0" * 40
    NULL_PATH = "/dev/null"

    Target = Struct.new(:path, :oid, :mode) do
      def diff_path
        mode ? path : NULL_PATH
      end
    end

    def run
      repo.index.load
      @status = repo.status

      @status.workspace_changes.each do |path, state|
        case state
        when :modified then print_diff(from_index(path), from_file(path))
        when :deleted then print_diff(from_index(path), from_nothing(path))
        end
      end

      exit 0
    end

    def from_index(path)
      entry = repo.index.entry_for_path(path)
      Target.new(path, entry.oid, entry.mode.to_s(8))
    end

    def from_file(path)
      blob = Database::Blob.new(repo.workspace.read_file(path))
      oid = repo.database.hash_object(blob)
      mode = Index::Entry.mode_for_stat(@status.stats[path])

      Target.new(path, oid, mode.to_s(8))
    end

    def from_nothing(path)
      Target.new(path, NULL_OID, nil)
    end

    def print_diff(a, b)
      return if a.oid == b.oid && a.mode == b.mode

      a.path = Pathname.new("a").join(a.path)
      b.path = Pathname.new("b").join(b.path)

      puts "diff --git #{a.path} #{b.path}"
      print_diff_mode(a, b)
      print_diff_content(a, b)
    end

    def print_diff_mode(a, b)
      if b.mode.nil?
        puts "deleted file mode #{a.mode}"
      elsif a.mode != b.mode
        puts "old mode #{a.mode}"
        puts "new mode #{b.mode}"
      end
    end

    def print_diff_content(a, b)
      return if a.oid == b.oid

      oid_range = "index #{short a.oid}..#{short b.oid}"
      oid_range.concat(" #{a.mode}") if a.mode == b.mode

      puts oid_range
      puts "--- #{a.diff_path}"
      puts "+++ #{b.diff_path}"
    end

    def short(oid)
      repo.database.short_oid(oid)
    end
  end
end
