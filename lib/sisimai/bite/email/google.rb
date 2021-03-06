module Sisimai::Bite::Email
  # Sisimai::Bite::Email::Google parses a bounce email which created by Gmail.
  # Methods in the module are called from only Sisimai::Message.
  module Google
    class << self
      # Imported from p5-Sisimail/lib/Sisimai/Bite/Email/Google.pm
      require 'sisimai/bite/email'

      Indicators = Sisimai::Bite::Email.INDICATORS
      StartingOf = {
        message: ['Delivery to the following recipient'],
        error:   ['The error that the other server returned was:'],
      }.freeze
      MarkingsOf = {
        start:  %r/Technical details of (?:permanent|temporary) failure:/,
        rfc822: %r{\A(?:
             -----[ ]Original[ ]message[ ]-----
            |[ \t]*-----[ ]Message[ ]header[ ]follows[ ]-----
            )\z
        }x,
      }.freeze

      MessagesOf = {
        expired: [
          'DNS Error: Could not contact DNS servers',
          'Delivery to the following recipient has been delayed',
          'The recipient server did not accept our requests to connect',
        ],
        hostunknown: [
          'DNS Error: Domain name not found',
          'DNS Error: DNS server returned answer with no data',
        ],
      }.freeze
      StateTable = {
        # Technical details of permanent failure:
        # Google tried to deliver your message, but it was rejected by the recipient domain.
        # We recommend contacting the other email provider for further information about the
        # cause of this error. The error that the other server returned was:
        # 500 Remote server does not support TLS (state 6).
        '6'  => { 'command' => 'MAIL', 'reason' => 'systemerror' },

        # http://www.google.td/support/forum/p/gmail/thread?tid=08a60ebf5db24f7b&hl=en
        # Technical details of permanent failure:
        # Google tried to deliver your message, but it was rejected by the recipient domain.
        # We recommend contacting the other email provider for further information about the
        # cause of this error. The error that the other server returned was:
        # 535 SMTP AUTH failed with the remote server. (state 8).
        '8'  => { 'command' => 'AUTH', 'reason' => 'systemerror' },

        # http://www.google.co.nz/support/forum/p/gmail/thread?tid=45208164dbca9d24&hl=en
        # Technical details of temporary failure:
        # Google tried to deliver your message, but it was rejected by the recipient domain.
        # We recommend contacting the other email provider for further information about the
        # cause of this error. The error that the other server returned was:
        # 454 454 TLS missing certificate: error:0200100D:system library:fopen:Permission denied (#4.3.0) (state 9).
        '9'  => { 'command' => 'AUTH', 'reason' => 'systemerror' },

        # http://www.google.com/support/forum/p/gmail/thread?tid=5cfab8c76ec88638&hl=en
        # Technical details of permanent failure:
        # Google tried to deliver your message, but it was rejected by the recipient domain.
        # We recommend contacting the other email provider for further information about the
        # cause of this error. The error that the other server returned was:
        # 500 Remote server does not support SMTP Authenticated Relay (state 12).
        '12' => { 'command' => 'AUTH', 'reason' => 'relayingdenied' },

        # Technical details of permanent failure:
        # Google tried to deliver your message, but it was rejected by the recipient domain.
        # We recommend contacting the other email provider for further information about the
        # cause of this error. The error that the other server returned was:
        # 550 550 5.7.1 <****@gmail.com>... Access denied (state 13).
        '13' => { 'command' => 'EHLO', 'reason' => 'blocked' },

        # Technical details of permanent failure:
        # Google tried to deliver your message, but it was rejected by the recipient domain.
        # We recommend contacting the other email provider for further information about the
        # cause of this error. The error that the other server returned was:
        # 550 550 5.1.1 <******@*********.**>... User Unknown (state 14).
        # 550 550 5.2.2 <*****@****.**>... Mailbox Full (state 14).
        #
        '14' => { 'command' => 'RCPT', 'reason' => 'userunknown' },

        # http://www.google.cz/support/forum/p/gmail/thread?tid=7090cbfd111a24f9&hl=en
        # Technical details of permanent failure:
        # Google tried to deliver your message, but it was rejected by the recipient domain.
        # We recommend contacting the other email provider for further information about the
        # cause of this error. The error that the other server returned was:
        # 550 550 5.7.1 SPF unauthorized mail is prohibited. (state 15).
        # 554 554 Error: no valid recipients (state 15).
        '15' => { 'command' => 'DATA', 'reason' => 'filtered' },

        # http://www.google.com/support/forum/p/Google%20Apps/thread?tid=0aac163bc9c65d8e&hl=en
        # Technical details of permanent failure:
        # Google tried to deliver your message, but it was rejected by the recipient domain.
        # We recommend contacting the other email provider for further information about the
        # cause of this error. The error that the other server returned was:
        # 550 550 <****@***.**> No such user here (state 17).
        # 550 550 #5.1.0 Address rejected ***@***.*** (state 17).
        '17' => { 'command' => 'DATA', 'reason' => 'filtered' },

        # Technical details of permanent failure:
        # Google tried to deliver your message, but it was rejected by the recipient domain.
        # We recommend contacting the other email provider for further information about the
        # cause of this error. The error that the other server returned was:
        # 550 550 Unknown user *****@***.**.*** (state 18).
        '18' => { 'command' => 'DATA', 'reason' => 'filtered' },
      }.freeze

      def description; return 'Google Gmail: https://mail.google.com'; end
      def smtpagent;   return Sisimai::Bite.smtpagent(self); end
      def headerlist;  return ['X-Failed-Recipients']; end

      # Parse bounce messages from Google Gmail
      # @param         [Hash] mhead       Message headers of a bounce email
      # @options mhead [String] from      From header
      # @options mhead [String] date      Date header
      # @options mhead [String] subject   Subject header
      # @options mhead [Array]  received  Received headers
      # @options mhead [String] others    Other required headers
      # @param         [String] mbody     Message body of a bounce email
      # @return        [Hash, Nil]        Bounce data list and message/rfc822
      #                                   part or nil if it failed to parse or
      #                                   the arguments are missing
      def scan(mhead, mbody)
        # Google Mail
        # From: Mail Delivery Subsystem <mailer-daemon@googlemail.com>
        # Received: from vw-in-f109.1e100.net [74.125.113.109] by ...
        #
        # * Check the body part
        #   This is an automatically generated Delivery Status Notification
        #   Delivery to the following recipient failed permanently:
        #
        #        recipient-address-here@example.jp
        #
        #   Technical details of permanent failure:
        #   Google tried to deliver your message, but it was rejected by the
        #   recipient domain. We recommend contacting the other email provider
        #   for further information about the cause of this error. The error
        #   that the other server returned was:
        #   550 550 <recipient-address-heare@example.jp>: User unknown (state 14).
        #
        #   -- OR --
        #   THIS IS A WARNING MESSAGE ONLY.
        #
        #   YOU DO NOT NEED TO RESEND YOUR MESSAGE.
        #
        #   Delivery to the following recipient has been delayed:
        #
        #        mailboxfull@example.jp
        #
        #   Message will be retried for 2 more day(s)
        #
        #   Technical details of temporary failure:
        #   Google tried to deliver your message, but it was rejected by the recipient
        #   domain. We recommend contacting the other email provider for further infor-
        #   mation about the cause of this error. The error that the other server re-
        #   turned was: 450 450 4.2.2 <mailboxfull@example.jp>... Mailbox Full (state 14).
        #
        #   -- OR --
        #
        #   Delivery to the following recipient failed permanently:
        #
        #        userunknown@example.jp
        #
        #   Technical details of permanent failure:=20
        #   Google tried to deliver your message, but it was rejected by the server for=
        #    the recipient domain example.jp by mx.example.jp. [192.0.2.59].
        #
        #   The error that the other server returned was:
        #   550 5.1.1 <userunknown@example.jp>... User Unknown
        #
        return nil unless mhead['from'].end_with?('<mailer-daemon@googlemail.com>')
        return nil unless mhead['subject'].start_with?('Delivery Status Notification')

        dscontents = [Sisimai::Bite.DELIVERYSTATUS]
        hasdivided = mbody.split("\n")
        rfc822list = []     # (Array) Each line in message/rfc822 part string
        blanklines = 0      # (Integer) The number of blank lines
        readcursor = 0      # (Integer) Points the current cursor position
        recipients = 0      # (Integer) The number of 'Final-Recipient' header
        statecode0 = 0      # (Integer) The value of (state *) in the error message
        v = nil

        while e = hasdivided.shift do
          if readcursor == 0
            # Beginning of the bounce message or delivery status part
            readcursor |= Indicators[:deliverystatus] if e.start_with?(StartingOf[:message][0])
          end

          if (readcursor & Indicators[:'message-rfc822']) == 0
            # Beginning of the original message part
            if e =~ MarkingsOf[:rfc822]
              readcursor |= Indicators[:'message-rfc822']
              next
            end
          end

          if readcursor & Indicators[:'message-rfc822'] > 0
            # After "message/rfc822"
            if e.empty?
              blanklines += 1
              break if blanklines > 1
              next
            end
            rfc822list << e
          else
            # Before "message/rfc822"
            next if (readcursor & Indicators[:deliverystatus]) == 0
            next if e.empty?

            # Technical details of permanent failure:=20
            # Google tried to deliver your message, but it was rejected by the recipient =
            # domain. We recommend contacting the other email provider for further inform=
            # ation about the cause of this error. The error that the other server return=
            # ed was: 554 554 5.7.0 Header error (state 18).
            #
            # -- OR --
            #
            # Technical details of permanent failure:=20
            # Google tried to deliver your message, but it was rejected by the server for=
            # the recipient domain example.jp by mx.example.jp. [192.0.2.49].
            #
            # The error that the other server returned was:
            # 550 5.1.1 <userunknown@example.jp>... User Unknown
            #
            v = dscontents[-1]

            if cv = e.match(/\A[ \t]+([^ ]+[@][^ ]+)\z/)
              # kijitora@example.jp: 550 5.2.2 <kijitora@example>... Mailbox Full
              if v['recipient']
                # There are multiple recipient addresses in the message body.
                dscontents << Sisimai::Bite.DELIVERYSTATUS
                v = dscontents[-1]
              end

              addr0 = Sisimai::Address.s3s4(cv[1])
              if Sisimai::RFC5322.is_emailaddress(addr0)
                v['recipient'] = addr0
                recipients += 1
              end
            else
              v['diagnosis'] ||= ''
              v['diagnosis'] << e + ' '
            end
          end
        end
        return nil unless recipients > 0

        dscontents.each do |e|
          e['agent']     = self.smtpagent
          e['diagnosis'] = Sisimai::String.sweep(e['diagnosis'])

          unless e['rhost']
            # Get the value of remote host
            if cv = e['diagnosis'].match(/[ \t]+by[ \t]+([^ ]+)[.][ \t]+\[(\d+[.]\d+[.]\d+[.]\d+)\][.]/)
              # Google tried to deliver your message, but it was rejected by
              # the server for the recipient domain example.jp by mx.example.jp. [192.0.2.153].
              hostname = cv[1]
              ipv4addr = cv[2]
              e['rhost'] = if hostname =~ /[-0-9a-zA-Z]+[.][a-zA-Z]+\z/
                             # Maybe valid hostname
                             hostname.downcase
                           else
                             # Use IP address instead
                             ipv4addr
                           end
            end
          end

          if cv = e['diagnosis'].match(/[(]state[ ](\d+)[)][.]/)
            statecode0 = cv[1]
          end
          if StateTable[statecode0]
            # (state *)
            e['reason']  = StateTable[statecode0]['reason']
            e['command'] = StateTable[statecode0]['command']
          else
            # No state code
            MessagesOf.each_key do |r|
              # Verify each regular expression of session errors
              next unless MessagesOf[r].any? { |a| e['diagnosis'].include?(a) }
              e['reason'] = r.to_s
              break
            end
          end
          next unless e['reason']

          # Set pseudo status code
          e['status'] = Sisimai::SMTP::Status.find(e['diagnosis'])
          e['reason'] = Sisimai::SMTP::Status.name(e['status']) if e['status'] =~ /\A[45][.][1-7][.][1-9]\z/
        end

        rfc822part = Sisimai::RFC5322.weedout(rfc822list)
        return { 'ds' => dscontents, 'rfc822' => rfc822part }
      end

    end
  end
end

