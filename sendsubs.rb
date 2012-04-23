#!/usr/bin/ruby

# The first argument must be an NNTP URI including the newsgroup
# /etc/nntp-maillist or <install-dir>/etc will be searched for files
# containing the list of subscribers and the last message number seen
#
# The second argument must be the FQDN where mail is received for this
# list

$: << File.dirname(__FILE__) + '/lib'
require 'simple_protocol'
require 'fileutils'
require 'mail'
require 'uri'

group = begin
	URI::parse(ARGV[0].to_s).path.to_s.sub(/^\/*/,'')
rescue Exception
	''
end

if group == ''
	warn 'Please specify an NNTP URI (including group)'
	exit 64
end

unless ARGV[1]
	warn 'Please specify a mail FQDN'
	exit 64
end

if File.writable?('/etc/nntp-maillist/')
	ETC = '/etc/nntp-maillist'
else
	ETC = File.dirname(__FILE__) + '/etc'
end
FileUtils.mkdir_p (ETC + '/saw/')

saw = open(ETC + '/saw/' + group).read.to_i rescue 0

mails = []

SimpleProtocol.new(:uri => ARGV[0], :default_port => 119) { |nntp|
	nntp.listgroup(group, (saw+1).to_s + '-')
	unless nntp.gets.split(/ /).first == '211'
		warn 'NNTP listgroup failed'
		exit 76
	end
	nums = nntp.gets_multiline
	saw = nums.last.to_i
	nums.each do |num|
		nntp.article(num)
		unless nntp.gets.split(/ /).first == '220'
			warn 'NNTP artcle fetch failed'
			exit 76
		end
		mails << Mail::Message.new(nntp.gets_multiline.join("\r\n"))
	end
}

$subs = open(ETC + '/' + group).read.split(/\r?\n/)
mails.each do |mail|
	mail[:list_post] = "<#{ARGV[0]}>, <mailto:#{group}@#{ARGV[1]}>"
	mail[:list_archive] = "<#{ARGV[0]}>"
	mail[:list_subscribe] = "<mailto:#{group}---subscribe@#{ARGV[1]}>"
	mail[:list_unsubscribe] = "<mailto:#{group}---unsubscribe@#{ARGV[1]}>"
	mail[:to] = "#{group}@#{ARGV[1]}" unless mail[:to]
	mail[:sender] = "#{group}@#{ARGV[1]}"
	mail[:return_path] = "#{group}@#{ARGV[1]}"
	def mail.destinations
		# Override normal destinations for this mail
		$subs
	end

	mail.delivery_method :sendmail
	mail.deliver!
end

open(ETC + '/saw/' + group, 'w') {|fh|
	fh.puts saw.to_s
}
