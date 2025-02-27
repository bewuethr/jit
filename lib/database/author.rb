require "time"

class Database
  TIME_FORMAT = "%s %z"

  Author = Struct.new(:name, :email, :time) do
    def self.parse(string)
      name, email, time = string.split(/<|>/).map(&:strip)
      time = Time.strptime(time, TIME_FORMAT)

      Author.new(name, email, time)
    end

    def short_date = time.strftime("%F")

    def to_s
      timestamp = time.strftime(TIME_FORMAT)
      "#{name} <#{email}> #{timestamp}"
    end

    def readable_time
      time.strftime("%a %b %-d %H:%M:%S %Y %z")
    end
  end
end
