# jit

This is an implementation of Git in Ruby, following the (excellent!) book
[*Building Git*][bg] by [James Coglan][jc]. I started working on this during my
[batch at the Recurse Center][rcblog] in August 2023, and finished juuuust 17
months later.

[bg]: <https://shop.jcoglan.com/building-git/>
[jc]: <https://jcoglan.com/>
[rcblog]: <https://benjaminwuethrich.dev/2023-08-06-recurse-center.html>

## Deviations from the book

- For short blocks, I used numbered instead of named parameters, and once [Ruby
  3.4.0][r3.4.0] became available, I switched to `it`. I didn't go back and
  change all existing instances, so this isn't completely consistent.
- `SortedSet` was [removed] in Ruby 3.0, so I'm cheating and use the
  [`sorted_set` gem][ssgem] an external depedency. Everything else is just
  standard library.
- I use [Standard Ruby][standard] for code formatting
- I decided to not use `minitest/spec` for my tests (sticking with
  `minitest/test`). I somewhat regretted this later on as the book does lots of
  deep nesting in its tests, and that's painful to do without specs.
- The initial branch defaults to `main` in my implementation instead of
  `master`. Real Git lets you configure this, but still defaults to `master`.

[r3.4.0]: <https://www.ruby-lang.org/en/news/2024/12/25/ruby-3-4-0-released/>
[removed]: <https://github.com/ruby/set/pull/2>
[ssgem]: <https://rubygems.org/gems/sorted_set>
[standard]: <https://github.com/standardrb/standard>
