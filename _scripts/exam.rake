#usr/bin/ruby
#encoding: utf-8

require 'yaml'
require 'erb'

task :exam do
  Dir.foreach("_exams") do |exam|
    full_path = YAML.load_file("_exams/" + exam)
    title, footer = full_path["title"], full_path["footer"]

    qa = []

    index = 0
    full_path["q"].each do |q_no|
      qa[index] = File.read("_includes/" + q_no)
      index += 1
    end
    tmp = ERB.new(File.read("_templates/exam.md.erb"))
    tmp.results(binding)
    tmp_md = File.open(tmp.md, "w")
    tmp_md.write(tmp)
    tmp_md.close()
    sh "markdown2pdf tmp.md"
    rm "tmp.md"
  end
end

task :default => :exam
