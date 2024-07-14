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
    @prune = []
    @diffs = {}
    @walk = options.fetch(:walk, true)

    revs.each { handle_revision(_1) }
    handle_revision(Revision::HEAD) if @queue.empty?

    @filter = PathFilter.build(@prune)
  end

  def each
    limit_list if @limited
    traverse_commits { |commit| yield commit }
  end

  def tree_diff(old_oid, new_oid)
    key = [old_oid, new_oid]
    @diffs[key] ||= @repo.database.tree_diff(old_oid, new_oid, @filter)
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

      yield commit
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
