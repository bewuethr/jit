require_relative "author"

class Database
  class Commit
    attr_accessor :oid
    attr_reader :parents, :tree, :author, :message

    def self.parse(scanner)
      headers = Hash.new { |hash, key| hash[key] = [] }

      loop do
        line = scanner.scan_until(/\n/).strip
        break if line.empty?

        key, value = line.split(/ +/, 2)
        headers[key].push(value)
      end

      Commit.new(
        headers["parent"],
        headers["tree"].first,
        Author.parse(headers["author"].first),
        scanner.rest
      )
    end

    def initialize(parents, tree, author, message)
      @parents = parents
      @tree = tree
      @author = author
      @message = message
    end

    def parent = @parents.first

    def type = "commit"

    def to_s
      lines = []

      lines.push("tree #{@tree}")
      lines.concat(@parents.map { |oid| "parent #{oid}" })
      lines.push("author #{@author}")
      lines.push("committer #{@author}")
      lines.push("")
      lines.push(@message)

      lines.join("\n")
    end

    def title_line = @message.lines.first

    def date = @author.time
  end
end
