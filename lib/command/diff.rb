
require_relative "../diff"
require_relative "../pager"
    Target = Struct.new(:path, :oid, :mode, :data) do
    def define_options
      @parser.on("--cached", "--staged") do
        @options[:cached] = true
      end
    end

      setup_pager

      if @options[:cached]
        diff_head_index
      else
        diff_index_workspace
      end

      exit 0
    end

    private def diff_head_index
      @status.index_changes.each do |path, state|
        case state
        when :added then print_diff(from_nothing(path), from_index(path))
        when :modified then print_diff(from_head(path), from_index(path))
        when :deleted then print_diff(from_head(path), from_nothing(path))
        end
      end
    end

    private def diff_index_workspace
    end
    private def from_head(path)
      entry = @status.head_tree.fetch(path)
      from_entry(path, entry)
    private def from_index(path)
      from_entry(path, entry)
    private def from_entry(path, entry)
      blob = repo.database.load(entry.oid)
      Target.new(path, entry.oid, entry.mode.to_s(8), blob.data)
    end

    private def from_file(path)
      Target.new(path, oid, mode.to_s(8), blob.data)
    private def from_nothing(path) = Target.new(path, NULL_OID, nil, "")
    private def print_diff(a, b)
      header("diff --git #{a.path} #{b.path}")
    private def header(string) = (puts fmt(:bold, string))

    private def print_diff_mode(a, b)
      if a.mode.nil?
        header("new file mode #{b.mode}")
      elsif b.mode.nil?
        header("deleted file mode #{a.mode}")
        header("old mode #{a.mode}")
        header("new mode #{b.mode}")
    private def print_diff_content(a, b)
      header(oid_range)
      header("--- #{a.diff_path}")
      header("+++ #{b.diff_path}")

      hunks = ::Diff.diff_hunks(a.data, b.data)
      hunks.each { |hunk| print_diff_hunk(hunk) }
    end

    private def print_diff_hunk(hunk)
      puts fmt(:cyan, hunk.header)
      hunk.edits.each { |edit| print_diff_edit(edit) }
    private def print_diff_edit(edit)
      text = edit.to_s.rstrip

      case edit.type
      when :eql then puts text
      when :ins then puts fmt(:green, text)
      when :del then puts fmt(:red, text)
      end

    private def short(oid) = repo.database.short_oid(oid)