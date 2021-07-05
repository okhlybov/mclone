# md2html input.md output.html

require 'redcarpet'

File.write(ARGV[1], Redcarpet::Markdown.new(Redcarpet::Render::HTML.new(hard_wrap: false, filter_html: true), fenced_code_blocks: true).render(File.read ARGV[0]))

