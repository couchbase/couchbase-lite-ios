#! /usr/bin/env ruby

if ARGV.length == 0
    puts "Usage: CouchToTD sourcefile ..."
    puts ""
    puts "Modifies input files in-place, converting 'Couch*' identifiers to 'TD*'."
    puts "This takes care of most of the busy-work of converting from TouchDB 1.0."
    puts "You will need to do some more conversion work by hand, but a lot less"
    puts "than you would have without this script."
    puts "NOTE: This directly modifies the named files; please make sure the files"
    puts "are checked into source control or that you at least have backups of them!"
    exit 0
end

ARGV.each do |filename|
    puts "#{filename} ..."
    outfilename = filename + ".temp"
    File.open(outfilename, "w") do |out|
        IO.foreach(filename) do |line|
        	line.gsub!(/\bTouchDB\b/,	 'CouchbaseLite')
        	line.gsub!(/\b(k?)TD([A-Z_])/, '\1CBL\2')
        	out.puts line
        end
    end
    File.rename(outfilename, filename)
end
