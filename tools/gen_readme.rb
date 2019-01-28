require 'erb'

ROOT = __dir__ + "/.."

def stdout(*args)
  cmd = "bundle", "exec", "ruby", "main.rb", *args
  Dir.chdir ROOT do
    IO.popen(cmd, 'r', &:read).tap do
      $?.success? or raise "command failed: %p" % cmd
    end
  end
end

def read_exe(path)
  File.read(path).sub(%r%(/services/)(.+)%) do
    $1 + ("A".."Z").take($2.count("/")+1).map { |s| s * 3 }.join("/")
  end
end

print ERB.new(File.read("README.md.erb")).result(binding)
