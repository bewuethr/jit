require_relative "shared/print_diff"
    include PrintDiff
      @options[:patch] = true
      define_print_diff_options

      elsif @args.size == 2
        diff_commits
      return unless @options[:patch]

      return unless @options[:patch]

    private def diff_commits
      return unless @options[:patch]

      a, b = @args.map { |rev| Revision.new(repo, rev).resolve }
      print_commit_diff(a, b)
    end
