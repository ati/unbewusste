# encoding: utf-8
require 'logger'
require 'parseconfig'
require 'gmail'
require 'sequel'

BASE_DIR = File.dirname(File.dirname(__FILE__))
CONFIG = ParseConfig.new(BASE_DIR + '/config/mail.config')
#LOGGER = Logger.new(STDOUT)
LOGGER = Logger.new(BASE_DIR + '/logs/mail.log')
LOGGER.level = Logger::DEBUG
DB = Sequel.sqlite(BASE_DIR + '/db/mail.sqlite3')

class Email < Sequel::Model
end



# read new mail
# for each email: 
#   send new message to 2 random recepients, put uniq hash to subject field
#   read replies, determine sender by hash, forward mail to her

def put_to_db(from)
  begin
    from_hash = (0...6).map{ ('a'..'z').to_a[rand(26)] }.join
  end while Email.where(:from_hash => from_hash).count > 0
  m = Email.create(:from_email => from, :from_hash => from_hash, :created_at => Time.now.to_i)
  return m.from_hash
end


def get_from_db(from_hash)
  m = Email.where(:from_hash => from_hash)
  return m.count.eql?(0)? nil : m.first.from_email
end


def email_flip(from, subject)
  if md = subject.match(/\[id:(\w+)\]/) # reply
    to = get_from_db(md[1].downcase)
    return to.nil?? [nil, "Unknown id: #{md[1]}"] : [ to, subject ]

  else
    from_hash = put_to_db(from)
    to = []
    i = 0
    nr = CONFIG['system']['recepients_count'].to_i
    while (i < nr*10) && (to.size < nr)
      i += 1
      t = CONFIG['participants'].values.sample
	  if !(t.eql?(from) || to.include?(t))
      	to.push(t)
	  end
    end

    if to.size.eql?(nr) 
      [ to, "[id:#{from_hash}] #{subject}"]
    else
      [nil, "Can't find #{nr} recepients in my configuration"]
    end
  end
end


def process_mail
  Gmail.new(CONFIG['account']['gmail_login'], CONFIG['account']['gmail_pw']) do |gmail|
    gmail.inbox.emails.each do |email|

	  #sender = email.envelope.from.first
      src_from = email.from.first
      src_subject = email.subject

      LOGGER.info("new mail from #{src_from}: #{src_subject}")

      # check for authorized submission
      if !CONFIG['participants'].values.include?(src_from)
        dst_to = nil
        dst_subject = "This is a closed email list. Please contact #{CONFIG['system']['majordom']} for more info"
      else
        dst_to, dst_subject = email_flip(src_from, src_subject)
      end

	  LOGGER.info("sending mail to '#{dst_to}', subject '#{dst_subject}'")

      new_mail = gmail.generate_message do
		from CONFIG['account']['gmail_login']
        if dst_to.nil?
          to src_from
          subject "#{CONFIG['system']['name']} ERROR: #{dst_subject}"
        else
          to dst_to
          subject dst_subject
        end
        body email.body.to_s
      end

	  new_mail.deliver!
	  #LOGGER.info(new_mail.inspect)
      email.delete!
    end
  end
end



############################################
begin
	LOGGER.info("starting...")
	process_mail()
rescue Exception => e
	LOGGER.error("caught exception processing mail: #{e.message}\n" + e.backtrace.join("\n"))
end
