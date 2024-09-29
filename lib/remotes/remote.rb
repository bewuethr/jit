class Remotes
  class Remote
    def initialize(config, name)
      @config = config
      @name = name

      @config.open
    end

    def fetch_url = @config.get(["remote", @name, "url"])

    def push_url = @config.get(["remote", @name, "pushurl"]) || fetch_url

    def fetch_specs = @config.get_all(["remote", @name, "fetch"])

    def uploader = @config.get(["remote", @name, "uploadpack"])

    def push_specs = @config.get_all(["remote", @name, "push"])

    def receiver = @config.get(["remote", @name, "receivepack"])
  end
end
