require_relative "base"
require_relative "shared/print_diff"

module Command
  class Log < Base
    include PrintDiff

    private def define_options
      @options[:patch] = false
      define_print_diff_options

      @options[:abbrev] = :auto
      @options[:format] = "medium"
      @options[:decorate] = "auto"

      @parser.on "--[no-]abbrev-commit" do |value|
        @options[:abbrev] = value
      end

      @parser.on "--pretty=<format>", "--format=<format>" do |format|
        @options[:format] = format
      end

      @parser.on "--oneline" do
        @options[:abbrev] = true if @options[:abbrev] == :auto
        @options[:format] = "oneline"
      end

      @parser.on "--decorate[=<format>]" do |format|
        @options[:decorate] = format || "short"
      end

      @parser.on "--no-decorate" do
        @options[:decorate] = "no"
      end
    end

    def run
      setup_pager

      @reverse_refs = repo.refs.reverse_refs
      @current_ref = repo.refs.current_ref

      each_commit { |commit| show_commit(commit) }

      exit 0
    end

    private def each_commit
      oid = repo.refs.read_head

      while oid
        commit = repo.database.load(oid)
        yield commit
        oid = commit.parent
      end
    end

    private def blank_line
      return if @options[:format] == "oneline"
      puts "" if defined? @blank_line
      @blank_line = true
    end

    private def show_commit(commit)
      case @options[:format]
      when "medium" then show_commit_medium(commit)
      when "oneline" then show_commit_oneline(commit)
      end

      show_patch(commit)
    end

    private def show_commit_medium(commit)
      author = commit.author

      blank_line
      puts fmt(:yellow, "commit #{abbrev(commit)}") + decorate(commit)
      puts "Author: #{author.name} <#{author.email}>"
      puts "Date:   #{author.readable_time}"
      blank_line
      commit.message.each_line { |line| puts "    #{line}" }
    end

    private def show_commit_oneline(commit)
      id = fmt(:yellow, abbrev(commit)) + decorate(commit)
      puts "#{id} #{commit.title_line}"
    end

    private def show_patch(commit)
      return unless @options[:patch]

      blank_line
      print_commit_diff(commit.parent, commit.oid)
    end

    private def abbrev(commit)
      if @options[:abbrev] == true
        repo.database.short_oid(commit.oid)
      else
        commit.oid
      end
    end

    private def decorate(commit)
      case @options[:decorate]
      when "auto" then return "" unless @isatty
      when "no" then return ""
      end

      refs = @reverse_refs[commit.oid]
      return "" if refs.empty?

      head, refs = refs.partition { |ref| ref.head? && !@current_ref.head? }
      names = refs.map { |ref| decoration_name(head.first, ref) }

      fmt(:yellow, " (") + names.join(fmt(:yellow, ", ")) + fmt(:yellow, ")")
    end

    private def decoration_name(head, ref)
      case @options[:decorate]
      when "short", "auto" then name = ref.short_name
      when "full" then name = ref.path
      end

      name = fmt(ref_color(ref), name)

      if head && ref == @current_ref
        name = fmt(ref_color(head), "#{head.path} -> #{name}")
      end

      name
    end

    private def ref_color(ref)
      ref.head? ? [:bold, :cyan] : [:bold, :green]
    end
  end
end