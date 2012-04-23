#!/usr/bin/ruby

# XXX: If this script can be run in parallel with itself, then the file
# handling below needs to be protected with, say, POSIX advisory locks

# This script is to be run as or from MDA, it takes a single email on
# STDIN and posts it to the correct newsgroup
#
# The first command line argument is the NNTP URI of the server
#
# The secodn command line argument is the FQDN we get mail on
#
# If ORIGINAL_RECIPIENT is set in the environment, that takes precedence
# over the To header.  If there's a third argument, it argument takes
# precendence over the environment and the To header.
#
# newsgroup@domain.tld is the format of the recipient
# newsgroup---subscribe@domain.tld to subscribe the From address
# newsgroup---unsubscribe@domain.tld to unsubscribe the From address

$: << File.dirname(__FILE__) + '/lib'
require 'simple_protocol'
require 'digest/md5'
require 'fileutils'
require 'mail'

def md5(s)
	Digest::MD5.hexdigest(s)
end

def confirm(command, frm, mail)
	sf = ETC + '/' + command + md5(frm) + md5(mail[:newsgroups].decoded)
	token = File.exists?(sf) ? (open(sf).read rescue nil) : nil
	if token && mail.to_s.include?(token.chomp)
		FileUtils.rm sf
		true
	else
		token = md5(rand.to_s + Time.now.to_s + frm)
		open(sf) {|fh|
			fh.puts token
		}

		mail[:newsgroups].decoded.split(/,\s*/).each do |group|
			confirmail = Mail.new do
				from (group + '---' + command + '@' + ARGV[1])
				to frm
				subject "Confirm #{command} to #{group} (#{token})"
				body "This is an email to confirm that you want to #{command} to the #{group} group.\n\nIf you did not request this, you can safely ignore this email.  Otherwise, simply reply to this email and ensure that the following token is in the body of your reply:\n\n#{token}\n\n"
			end
			confirmail.delivery_method :sendmail
			confirmail.deliver!
		end

		false
	end
end

unless ARGV[0]
	warn 'You must specify an NNTP server!'
	exit 1
end

unless ARGV[1]
	warn 'You must specify an FQDN!'
	exit 1
end

if File.writable?('/etc/nntp-maillist/')
	ETC = '/etc/nntp-maillist'
else
	ETC = File.dirname(__FILE__) + '/etc'
end
FileUtils.mkdir_p ETC

to = ARGV[2] || ENV['ORIGINAL_RECIPIENT']
mail = Mail::Message.new(STDIN.read)

unless to
	# Extract To header, first email address
	to = mail[:to].addresses.first.to_s
end

unless to
	warn 'No recipient address found!'
	exit 1
end

newsgroup, _ = to.split(/@/)
newsgroup, command = newsgroup.split(/---/,2)

newsgroups = mail[:newsgroups] ? mail[:newsgroups].decoded.split(/,\s*/) : []
newsgroups << newsgroup
mail[:newsgroups] = newsgroups.sort.uniq.join(', ')

case command
	when 'subscribe'
		from = mail[:from].addresses.first.to_s
		if confirm('subscribe', from, mail)
			mail[:newsgroups].decoded.split(/,\s*/).each do |group|
				open(ETC + '/' + group, 'a') {|fh|
					fh.puts from
				}
			end
		end
	when 'unsubscribe'
		from = mail[:from].addresses.first.to_s
		if confirm('unsubscribe', from, mail)
			mail[:newsgroups].decoded.split(/,\s*/).each do |group|
				subs = open(ETC + '/' + group).read.split(/\r?\n/).sort.uniq
				subs.delete(from)
				open(ETC + '/' + group, 'w') {|fh|
					subs.each do |sub|
						fh.puts sub
					end
				}
			end
		end
	when nil
		SimpleProtocol.new(:uri => ARGV[0], :default_port => 119) { |nntp|
			nntp.post
			raise 'Error sending POST command to server.' unless nntp.gets.split(' ')[0] == '340'
			nntp.send_multiline(mail.to_s)
			unless (m = nntp.gets).split(' ')[0] == '240'
				raise 'Error POSTing article: ' + m
			end
		}
	else
		warn 'unknown command'
		exit 1
end
