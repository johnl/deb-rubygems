require 'rbconfig'
require 'find'
require 'ftools'
require 'fileutils'

include Config

$srcdir = CONFIG["srcdir"]
$version = CONFIG["MAJOR"]+"."+CONFIG["MINOR"]
$libdir = File.join(CONFIG["libdir"], "ruby", $version)
$archdir = File.join($libdir, CONFIG["arch"])
$site_libdir = $:.find {|x| x =~ /site_ruby$/}
if !$site_libdir
  $site_libdir = File.join($libdir, "site_ruby")
elsif $site_libdir !~ Regexp.new(Regexp.quote($version))
  $site_libdir = File.join($site_libdir, $version)
end

def remove_stubs
  is_apparent_stub = lambda { |path|
    File.read(path, 40) =~ /^# This file was generated by RubyGems/ and
      File.readlines(path).size < 20
  }
  puts %{
    As of RubyGems 0.8.0, library stubs are no longer needed.
    Searching $LOAD_PATH for stubs to optionally delete (may take a while)...
  }.gsub(/^ */, '')
  gemfiles = Dir.glob("{#{($LOAD_PATH).join(',')}}/**/*.rb").collect {|file| File.expand_path(file)}.uniq
  puts "...done."
  seen_stub = false
  gemfiles.each do |file|
    unless File.directory?(file)
      if is_apparent_stub[file]
        unless seen_stub
          puts "\nRubyGems has detected stubs that can be removed.  Confirm their removal:"
        end
        seen_stub = true
        print "  * remove #{file}? [y/n] "
        answer = gets
        if answer =~ /y/i then
          File.unlink(file)
          puts "        (removed)"
        else
          puts "        (skipping)"
        end
      end
    end
  end
  if seen_stub
    puts "Finished with library stubs."
  else
    puts "No library stubs found."
  end
  puts
end

def install_rb(srcdir = nil)
  ### Install 'lib' files.

  libdir = "lib"
  libdir = File.join(srcdir, libdir) if srcdir
  paths = []
  dirs = []
  Find.find(libdir) do |f|
    next unless FileTest.file?(f)
    next if (f = f[libdir.length+1..-1]) == nil
    next if (/CVS$/ =~ File.dirname(f))
    next if File.basename(f) =~ /^\./
    next if f =~ /~$/
    paths.push f
    dirs |= [File.dirname(f)]
  end

  # Create the necessary directories.
  for f in dirs
    next if f == "."
    next if f == "CVS"
    File::makedirs(File.join($site_libdir, f))
  end

  # Install the files.
  for f in paths
    File::install(File.join("lib", f), File.join($site_libdir, f), 0644, true)
  end
  gem_dir = File.join(Config::CONFIG['libdir'], 'ruby', 'gems', Config::CONFIG['ruby_version'])
  ["specifications", "cache", "gems"].each do |subdir|
    File::makedirs(File.join(gem_dir, subdir))
  end
  
  # move old gems if they are present into gems subdir (TEMPORARY)
  
  begin
    Dir.glob(File.join(gem_dir, "*")) do |file|
      basename = File.basename(file)
      next unless basename =~ /.*-[0-9]+\..*/
      FileUtils.mv(file, File.join(gem_dir, "gems"))
    end
  rescue
    puts "ERROR: Failed to migrate the old gems located in..."
    puts "  #{gem_dir}"
    puts "  ...to the #{File.join(gem_dir, 'gems')} directory"
    puts "  You should move them manually, or your gems DB will be an invalid state"
    puts "Backtrace follows:"
    puts $!
    puts $!.backtrace.join("\n")
  end
  
  ## Install the 'bin' files.

  bindir = CONFIG['bindir']
  ruby_install_name = CONFIG['ruby_install_name']
  is_windows_platform = CONFIG["arch"] =~ /dos|win32/i
  Find.find('bin') do |f|
    next if f =~ /\bCVS\b/
    next if f =~ /~$/
    next if FileTest.directory?(f)
    next if f =~ /\.rb$/
    next if File.basename(f) =~ /^\./
    source = f
    target = File.join(bindir, File.basename(f))
    File.open(target, "w", 0755) do |script|
      sourcelines = File.read(source)
      sourcelines.gsub!(/\#!\/usr\/bin\/env ruby/, "\#!#{bindir}/#{ruby_install_name}")
      script.write sourcelines 
    end
    if is_windows_platform
      File.open(target+".cmd", "w") do |file|
        file.puts "@ruby #{target} %1 %2 %3 %4 %5 %6 %7 %8 %9"
      end
    end
  end
  
  remove_stubs 

  ## Move old gems if installed

  ## Install the 'sources' package bundled with RubyGems.

  Dir.chdir("pkgs/sources")
    load("sources.gemspec")
    spec = Gem.sources_spec
    Gem::manage_gems
    gem_file = Gem::Builder.new(spec).build
    Gem::Installer.new(gem_file).install(true, Gem.dir, false)
  Dir.chdir("../..")
end

install_rb
