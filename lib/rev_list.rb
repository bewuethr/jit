require "pathname"

require_relative "path_filter"
require_relative "revision"

class RevList
  include Enumerable

  RANGE = /^(.*)\.\.(.*)$/
  EXCLUDE = /^\^(.+)$/

  def initialize(repo, revs, options = {})
    @repo = repo
    @commits = {}
    @flags = Hash.new { |hash, oid| hash[oid] = Set.new }
    @queue = []
    @limited = false
    @output = []
    @pending = []
    @prune = []
    @diffs = {}
    @paths = {}

    @objects = options.fetch(:objects, false)
    @missing = options.fetch(:missing, false)
    @walk = options.fetch(:walk, true)

    include_refs(repo.refs.list_all_refs) if options[:all]
    include_refs(repo.refs.list_branches) if options[:branches]
    include_refs(repo.refs.list_remotes) if options[:remotes]

    revs.each { handle_revision(it) }
    handle_revision(Revision::HEAD) if @queue.empty?

    @filter = PathFilter.build(@prune)
  end

  def each
    limit_list if @limited
    mark_edges_uninteresting if @objects
    traverse_commits { yield _1 }
    traverse_pending { yield _1, @paths[_1.oid] }
  end

  def tree_diff(old_oid, new_oid)
    key = [old_oid, new_oid]
    @diffs[key] ||= @repo.database.tree_diff(old_oid, new_oid, @filter)
  end

  private def include_refs(refs)
    oids = refs.map(&:read_oid).compact
    oids.each { handle_revision(_1) }
  end

  private def handle_revision(rev)
    if @repo.workspace.stat_file(rev)
      @prune.push(Pathname.new(rev))
    elsif (match = RANGE.match(rev))
      set_start_point(match[1], false)
      set_start_point(match[2], true)
      @walk = true
    elsif (match = EXCLUDE.match(rev))
      set_start_point(match[1], false)
      @walk = true
    else
      set_start_point(rev, true)
    end
  end

  private def set_start_point(rev, interesting)
    rev = Revision::HEAD if rev == ""
    oid = Revision.new(@repo, rev).resolve(Revision::COMMIT)

    commit = load_commit(oid)
    enqueue_commit(commit)

    unless interesting
      @limited = true
      mark(oid, :uninteresting)
      mark_parents_uninteresting(commit)
    end
  rescue Revision::InvalidObject => error
    raise error unless @missing
  end

  private def load_commit(oid)
    return nil unless oid
    @commits[oid] ||= @repo.database.load(oid)
  end

  private def enqueue_commit(commit)
    return unless mark(commit.oid, :seen)

    if @walk
      index = @queue.find_index { _1.date < commit.date }
      @queue.insert(index || @queue.size, commit)
    else
      @queue.push(commit)
    end
  end

  private def mark(oid, flag) = @flags[oid].add?(flag)

  private def mark_parents_uninteresting(commit)
    queue = commit.parents.clone

    until queue.empty?
      oid = queue.shift
      next unless mark(oid, :uninteresting)

      commit = @commits[oid]
      queue.concat(commit.parents) if commit
    end
  end

  private def mark_edges_uninteresting
    @queue.each do |commit|
      if marked?(commit.oid, :uninteresting)
        mark_tree_uninteresting(commit.tree)
      end

      commit.parents.each do |oid|
        next unless marked?(oid, :uninteresting)

        parent = load_commit(oid)
        mark_tree_uninteresting(parent.tree)
      end
    end
  end

  private def mark_tree_uninteresting(tree_oid)
    entry = @repo.database.tree_entry(tree_oid)
    traverse_tree(entry) { mark(_1.oid, :uninteresting) }
  end

  private def traverse_tree(entry, path = Pathname.new(""))
    @paths[entry.oid] ||= path

    return unless yield entry
    return unless entry.tree?

    tree = @repo.database.load(entry.oid)

    tree.entries.each do |name, item|
      traverse_tree(item, path.join(name)) { yield _1 }
    end
  end

  private def limit_list
    while still_interesting?
      commit = @queue.shift
      add_parents(commit)

      unless marked?(commit.oid, :uninteresting)
        @output.push(commit)
      end
    end

    @queue = @output
  end

  private def still_interesting?
    return false if @queue.empty?

    oldest_out = @output.last
    newest_in = @queue.first

    return true if oldest_out && oldest_out.date <= newest_in.date

    if @queue.any? { |commit| !marked?(commit.oid, :uninteresting) }
      return true
    end

    false
  end

  private def marked?(oid, flag) = @flags[oid].include?(flag)

  private def traverse_commits
    until @queue.empty?
      commit = @queue.shift
      add_parents(commit) unless @limited

      next if marked?(commit.oid, :uninteresting)
      next if marked?(commit.oid, :treesame)

      @pending.push(@repo.database.tree_entry(commit.tree))
      yield commit
    end
  end

  private def traverse_pending
    return unless @objects

    @pending.each do |entry|
      traverse_tree(entry) do |object|
        next if marked?(object.oid, :uninteresting)
        next unless mark(object.oid, :seen)

        yield object
        true
      end
    end
  end

  private def add_parents(commit)
    return unless @walk && mark(commit.oid, :added)

    if marked?(commit.oid, :uninteresting)
      parents = commit.parents.map { |oid| load_commit(oid) }
      parents.each { |parent| mark_parents_uninteresting(parent) }
    else
      parents = simplify_commit(commit).map { |oid| load_commit(oid) }
    end

    parents.each { |parent| enqueue_commit(parent) }
  end

  private def simplify_commit(commit)
    return commit.parents if @prune.empty?

    parents = commit.parents
    parents = [nil] if parents.empty?

    parents.each do |oid|
      next unless tree_diff(oid, commit.oid).empty?
      mark(commit.oid, :treesame)
      return [*oid]
    end

    commit.parents
  end
end
