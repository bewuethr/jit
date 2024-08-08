require "pathname"
require_relative "../config"

class Config
  class Stack
    GLOBAL_CONFIG = File.expand_path("~/.gitconfig")
    SYSTEM_CONFIG = "/etc/gitconfig"

    def initialize(git_path)
      @configs = {
        local: Config.new(git_path.join("config")),
        global: Config.new(Pathname.new(GLOBAL_CONFIG)),
        system: Config.new(Pathname.new(SYSTEM_CONFIG))
      }
    end

    def open = @configs.each_value(&:open)

    def get(key) = get_all(key).last

    def get_all(key)
      %i[system global local].flat_map do |name|
        @configs[name].open
        @configs[name].get_all(key)
      end
    end

    def file(name)
      if @configs.has_key?(name)
        @configs[name]
      else
        Config.new(Pathname.new(name))
      end
    end
  end
end
