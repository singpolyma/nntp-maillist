#!/usr/bin/ruby

# This script is to be run as or from MDA, it takes a single email on
# STDIN and posts it to the correct newsgroup
# The first command line argument is the NNTP URI of the server
# If ORIGINAL_RECIPIENT is set in the environment, that takes precedence
# over the To header.  If there's a second command line, it argument takes
# precendence over the environment and the To header.

$: << File.dirname(__FILE__) + '/lib'
require 'simple_protocol'

unless ARGV[0]
	warn 'You must specify an NNTP server!'
	exit 1
end

to = ARGV[1] || ENV['ORIGINAL_RECIPIENT']
mail = STDIN.read

unless to
	# Extract To header, first email address
	to = mail.scan(/^To:.*?<?((?:[^<> ,"']+@)?[^<> ,"']+\.[^<> ,"']*)[> ,]/i)
	to = to[0][0] rescue nil
end

unless to
	warn 'No recipient address found!'
	exit 1
end

newsgroup, _ = to.split(/@/)

def add_to_header(mail, header, *args)
	has = false
	mail.lines.map {|line|
		if line =~ /^#{header}:/i
			has = true
			items = line.chomp.split(/:\s*/, 2).last.split(/\s*,\s*/) + args
			items.length > 0 ? "#{header}: #{items.uniq.join(', ')}\n" : nil
		elsif !has && line.chomp == ''
			has = true
			"#{header}: #{args.join(', ')}\n\n"
		else
			line
		end
	}.compact.join
end

mail = add_to_header(mail, 'Newsgroups', newsgroup)

SimpleProtocol.new(:uri => ARGV[0], :default_port => 119) { |nntp|
	nntp.post
	raise 'Error sending POST command to server.' unless nntp.gets.split(' ')[0] == '340'
	nntp.send_multiline(mail.split(/\r?\n/))
	unless (m = nntp.gets).split(' ')[0] == '240'
		raise 'Error POSTing article: ' + m
	end
}
