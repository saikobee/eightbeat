#!/usr/bin/ruby
=begin
Copyright 2009 Brian Mock

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end

case RUBY_PLATFORM
when /mswin/
    require 'Win32API'
end

COMMENT_PREFIX   = "## "
TEMPO_PREFIX     = ":: "
NOTE_PREFIX      = ">> "
SECTION_PREFIX   = "@@ "
IMPORTANT_PREFIX = "!! "

DEBUG_PREFIX = "XX "

# Switch to false to disable debug output
$DEBUG = true

def debug(*xs)
    print xs.map{|x| x.to_s}.join(" "), "\n" if $DEBUG
end

$options = {}

def term_or_exit
    case RUBY_PLATFORM
    when /mswin/
        system "pause"
    when /linux/
        case ENV["TERM"]
        when "linux"
            system "setterm", "-blength", 0.to_s
        else
            system "xset", "b", 0.to_s
        end
    end
    exit
end

trap :TERM do
    term_or_exit
end

at_exit do
    term_or_exit
end

# This class is used to retain case while providing case insensitivity in its
# comparison and hashing functions
class Key
    def initialize(sym)
        @sym = sym.to_sym
    end

    def hash
        self.to_s.downcase.hash
    end

    def ==(other)
        self.to_s.downcase == other.to_s.downcase
    end
    alias eql? ==

    def to_s
        @sym.to_s
    end

    def inspect
        "Key[#{@sym}]"
    end
end

def name2lso(name)
    fail "'#{name}' is too small" if name.length < 1
    fail "'#{name}' is too big"   if name.length > 3

    letter, sharp, octave = nil, nil, nil

    if name == "R"
        letter = "R"
        sharp  = ""
        octave = ""
    elsif name.length == 3
        letter, sharp, octave = name.split(//)
    elsif name.length == 2
        letter = name[0, 1]
        if "#b".include? name[1, 1]
            sharp  = name[1, 1]
            octave = Synth.octave
        else
            sharp = ""
            octave = name[1, 1]
        end
    else
        letter = name[0, 1]
        sharp  = ""
        octave = Synth.octave
    end

    [letter, sharp, octave]
end

def semitones(name)
    letter, sharp, octave = name2lso(name)
    mod = case sharp
          when "b" then -1
          when "#" then +1
          else           0
          end
    (octave.to_i * 12) + note_to_i(letter) + mod
end

def note_to_i(note)
    [   "C",
        "C#",
        "D",
        "D#",
        "E",
        "F",
        "F#",
        "G",
        "G#",
        "A",
        "A#",
        "B",
    ].index(note)
end

class Synth
    @@tempo    = 120
    @@octave   = 4
    @@duration = 4

    def initialize
        @queue = Hash.new {|h, k|
            h[k] = []
        }
    end

    def queue_show
        @queue.map{|k, v| [k, v.length]}.inspect
    end

    def self.duration
        @@duration
    end

    def self.duration=(duration)
        @@duration = duration
    end

    def duration
        @@duration
    end

    def duration=(duration)
        @@duration = duration
    end

    def queue(section, &block)
        @queue[Key.new(section)] << block
    end

    def self.octave
        @@octave
    end

    def self.octave=(octave)
        fail "Octave #{octave} is out of range" unless octave.between?(0, 8)
        @@octave = octave
    end

    def octave
        @@octave
    end

    def octave=(octave)
        fail "Octave #{octave} is out of range" unless octave.between?(0, 8)
        @@octave = octave
    end

    def tempo
        @@tempo
    end

    def tempo=(tempo)
        # This allows for storing floating tempos but only displaying the
        # integral part
        puts "#{TEMPO_PREFIX}Tempo #{tempo.to_i}"
        @@tempo = tempo
    end

    def play
        play_section "Song"
    end

    def play_section(section)
        sec = @queue.keys.detect{|x| x == Key.new(section)}
        if sec
            puts "#{SECTION_PREFIX}#{sec}"
        else
            puts "#{SECTION_PREFIX}#{section}"
        end
        @queue[Key.new(section)].each do |func|
            func[self]
        end
    end

    def repeat_section(times, section)
        times.times do
            play_section section
        end
    end

    def loop_section(section)
        loop do
            play_section section
        end
    end

    def beep2(freq, len)
        if freq < 5 # Hz
            sleep len # rest note
        else
            case RUBY_PLATFORM
            when /linux/
                if $options[:use_beep]
                    if $options[:needs_sudo]
                        system("sudo", "beep",
                               "-f", freq.to_s,
                               "-l", (len * 1_000).to_s
                               # Convert from seconds to milliseconds
                        )
                    else
                        system("beep",
                               "-f", freq.to_s,
                               "-l", (len * 1_000).to_s
                               # Convert from seconds to milliseconds
                        )
                    end
                else
                    # Determine if the user is in a tty or not
                    scale = 0.45
                    case ENV["TERM"]
                    when "linux"
                        system(
                            "setterm",
                            "-blength", (len * 1_000 * scale).to_s
                        )
                        system(
                            "setterm",
                            "-bfreq", freq.to_s
                        )
                    else
                        system(
                            "xset",
                            "b",
                            100.to_s,
                            freq.to_i.to_s,
                            (len * 1_000 * scale).to_i.to_s
                        )
                    end
                    print "\a"
                    sleep len
                end
            when /mswin/
                beeper = Win32API.new("kernel32", "Beep", ['L'] * 2, 'L')
                beeper.call(freq, len * 1_000)
            else
                fail "Your operating system is currently unsupported"
            end
        end
    end

    def beep(*notes)
        notes.each do |note|
            puts "#{NOTE_PREFIX}#{note}"
            begin
                beep2(note.freq, note.len)
                sleep note.pause
            rescue Interrupt
                puts "\r#{IMPORTANT_PREFIX}Song stopped"
                exit
            end
        end
    end

    # 1  => 4    beats
    # 2  => 2    beats
    # 4  => 1    beat
    # 8  => 0.50 beats
    # 16 => 0.25 beats
    def self.n2l(note)
        (((1/note.to_f) * 4)/@@tempo) * 60
    end

    # 2^(n/12) * 440 = freq
    # where n = semitones above middle A
    def self.n2freq(name)
        name = name.dup
        if name == "R"
            0.0
        else
            middle_a = semitones("A4")
            # Trap for notes using the current octave state
            idx = case name.length
                  when 1
                      semitones(name + Synth.octave.to_s)
                  when 2
                      if name =~ /[b#]$/
                          semitones(name + Synth.octave.to_s)
                      else
                          semitones(name)
                      end
                  when 3
                      semitones(name)
                  end

            semitones_above_middle_a = idx - middle_a

            2**(semitones_above_middle_a/12.0) * 440 # Hz
        end
    end
end

class Note
    def initialize(freq, len=nil)
        @freq = freq
        @len  = len
    end

    def freq
        possible_octaves = (0 .. 8).map{|x| x.to_s}
        Synth.n2freq @freq
    end

    def len
        if @len
            @len.split('+').map{|length| Synth.n2l length}.inject{|x, y| x + y}
        else
            Synth.n2l Synth.duration
        end
    end

    # likely a better name for this... TODO
    def pause
        Note.new("R", "128").len
    end

    def staccato_pause
        Note.new("R", "64").len
    end

    def to_s
        l, s, o = name2lso @freq
        format "%-2s %1s %s", (l + s), o, (@len || Synth.duration)
    end

    def inspect
        "#{@freq}, #{@len}"
    end
end

module N
    C = Note.new("C", 16)
    D = Note.new("D", 16)
    E = Note.new("E", 16)
    F = Note.new("F", 16)
    G = Note.new("G", 16)
    A = Note.new("A", 16)
    B = Note.new("B", 16)

    R = Note.new("R", 16)
end

def trim!(s)
    s.gsub!(/^\s*|\s*$/){""}
end

def main
    synth = Synth.new

    # {{{ Process command line args
    $options[:file] = "/dev/stdin"

    ARGV.each do |option|
        case option
        when "--sudo"
            $options[:needs_sudo] = true
        when "--beep"
            $options[:use_beep] = true
        else
            $options[:file] = option
        end
    end
    # }}}


    section = "Song"

    open($options[:file]) do |f|
        f.each do |line|
            next if line.nil?

            if line =~ /^#/ # print comments to the screen
                synth.queue(section){|s| puts line.sub(/# ?/){COMMENT_PREFIX}}
                next
            end

            line.chomp!

            if line =~ /^\s*$/ # handle blank lines
                #            synth.queue(section){|s| puts}
                next
            end

            if line =~ /^\s*\[([^\[\];]+)\]\s*$/ # beginning of a section
                section = $1
                trim! section
                next
            end

            cmd_strings = line.split(";")
            cmd_strings.each do |cmd_string|
                next if cmd_string =~ /^\s*$/ or cmd_string.nil?

                trim! cmd_string
                case cmd_string
                when /^play\s+([^\[\]]+)$/i # play a section once
                    sec = $1
                    synth.queue(section){|s| s.play_section sec}
                when /^loop\s+([^\[\]]+)$/i # loop a section indefinitely
                    sec = $1
                    synth.queue(section){|s| s.loop_section sec}
                when /^repeat\s+(\d+)\s+([^\[\]]+)$/i # repeat a section n-times
                    times, sec = $1.to_i, $2
                    synth.queue(section){|s| s.repeat_section times, sec}
                when /^tempo\s+(\d+)$/i,
                    /^tempo\s*=\s*(\d+)$/i # queue a tempo change
                    tempo = $1.to_i
                    synth.queue(section){|s| s.tempo = tempo}
                when /^tempo\s*\*\s*(\d+)$/i # queue a tempo multiply
                    scale = $1.to_f
                    synth.queue(section){|s| s.tempo *= scale}
                when /^tempo\s*\/\s*(\d+)$/i # queue a tempo divide
                    scale = $1.to_f
                    synth.queue(section){|s| s.tempo /= scale}
                when /^duration\s+(\d+)$/i,
                    /^duration\s*=\s*(\d+)$/i # queue a tempo change
                    duration = $1.to_i
                    synth.queue(section){|s| s.duration = duration}
                when /^octave\s+(\w+)$/i,
                    /^octave\s*=\s*(\w+)$/i # queue an octave change
                    octave = $1
                    case octave
                    when /up/i
                        synth.queue(section){|s| s.octave += 1}
                    when /down/i
                        synth.queue(section){|s| s.octave -= 1}
                    else
                        oct = octave.to_i
                        synth.queue(section){|s| s.octave = oct}
                    end
                    # when command is just a note to play
                when /^([RA-G][#b]?\d?)(?:(?:\s*,\s*|\s+)(\d+(?:\+\d+)*))?$/
                    name, len = $1, $2
                    synth.queue(section){|s| s.beep Note.new(name, len)}
                when /^[+-][\s+-]*$/
                    plus_or_minuses = cmd_string.gsub!(/\s*/){""}.split(//)
                    net_octave_change = plus_or_minuses.map{|x|
                        case x
                        when "+"; +1
                        when "-"; -1
                        else;      0
                        end
                    }.inject{|a, b| a + b}
                    synth.queue(section){|s| s.octave += net_octave_change}
                else
                    puts "Syntax error on line #{ARGF.lineno} near \"#{cmd_string}\""
                    exit 1
                end
            end
        end
    end

#    puts synth.queue_show
#    synth.play_section "Song"
    synth.play
#    synth.play_section "Intro"
#    synth.play_section "Main"
#    synth.repeat_section 4, "Interlude"
end

main if $0 == __FILE__
