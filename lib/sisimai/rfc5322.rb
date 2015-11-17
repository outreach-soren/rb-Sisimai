module Sisimai::RFC5322
  # Imported from p5-Sisimail/lib/Sisimai/RFC5322.pm
  class << self
    @@Rx          = BUILD_REGULAR_EXPRESSIONS
    @@HEADERINDEX = BUILD_FLATTEN_RFC822HEADER_LIST
    @@HEADERTABLE = {
      'messageid' => [ 'Message-Id' ],
      'subject'   => [ 'Subject' ],
      'listid'    => [ 'List-Id' ],
      'date'      => [ 'Date', 'Posted-Date', 'Posted', 'Resent-Date', ],
      'addresser' => [ 
        'From', 'Return-Path', 'Reply-To', 'Errors-To', 'Reverse-Path', 
        'X-Postfix-Sender', 'Envelope-From', 'X-Envelope-From',
      ],
      'recipient' => [ 
        'To', 'Delivered-To', 'Forward-Path', 'Envelope-To',
        'X-Envelope-To', 'Resent-To', 'Apparently-To'
      ],
    }

    def BUILD_REGULAR_EXPRESSIONS()
      # See http://www.ietf.org/rfc/rfc5322.txt
      #  or http://www.ex-parrot.com/pdw/Mail-RFC822-Address.html ...
      #   addr-spec       = local-part "@" domain
      #   local-part      = dot-atom / quoted-string / obs-local-part
      #   domain          = dot-atom / domain-literal / obs-domain
      #   domain-literal  = [CFWS] "[" *([FWS] dcontent) [FWS] "]" [CFWS]
      #   dcontent        = dtext / quoted-pair
      #   dtext           = NO-WS-CTL /     ; Non white space controls
      #                     %d33-90 /       ; The rest of the US-ASCII
      #                     %d94-126        ;  characters not including "[",
      #                                     ;  "]", or "\"
      atom           = %r([a-zA-Z0-9_!#\$\%&'*+/=?\^`{}~|\-]+)o
      quoted_string  = %r/"(?:\\[^\r\n]|[^\\"])*"/o
      domain_literal = %r/\[(?:\\[\x01-\x09\x0B-\x0c\x0e-\x7f]|[\x21-\x5a\x5e-\x7e])*\]/o
      dot_atom       = %r/$atom(?:[.]$atom)*/o
      local_part     = %r/(?:#{dot_atom}|#{quoted_string})/o
      domain         = %r/(?:#{dot_atom}|#{domain_literal})/o

      re['rfc5322']  = %r/#{local_part}[@]#{domain}/o
      re['ignored']  = %r/#{local_part}[.]*[@]#{domain}/o
      re['domain']   = %r/#{domain}/o

      return re
    end
    private :BUILD_REGULAR_EXPRESSIONS

    def BUILD_FLATTEN_RFC822HEADER_LIST()
      # Convert HEADER: structured hash table to flatten hash table for being
      # called from Sisimai::MTA::*
      v = {}
      @@HEADERTABLE.each_value |e| do
        e.each |ee| do
          v[ee.downcase] = 1
        end
      end
    end
    private :BUILD_FLATTEN_RFC822HEADER_LIST

    # Grouped RFC822 headers
    # @param    [String] group  RFC822 Header group name
    # @return   [Array,Hash]    RFC822 Header list
    def HEADERFIELDS(group)
      return @@HEADERINDEX unless group.kind_of?(String)
      return @@HEADERTABLE[group] if @@HEADERTABLE.has_key?(group)
      return @@HEADERTABLE
    end

    # Fields that might be long
    # @return   [Hash] Long filed(email header) list
    def LONGFIELDS()
      return { 'to' => 1, 'from' => 1, 'subject' => 1 }
    end

    # Check that the argument is an email address or not
    # @param    [String] email  Email address string
    # @return   [True,False]    true: is a email address
    #                           false: is not an email address
    def is_emailaddress(email)
      return false unless email.kind_of?(String)
      return false if email.match(%r/(?:[\x00-\x1f]|\x1f)/)
      return true  if email.match(Re['ignored'])
      return false
    end

    # Check that the argument is an domain part of email address or not
    # @param    [String] dpart  Domain part of the email address
    # @return   [True,False]    true: Valid domain part
    #                           false: Not a valid domain part
    def is_domainpart(dpart)
      return false unless dpart.kind_of?(String)

      return false if dpart =~ /(?:[\x00-\x1f]|\x1f)/
      return false if dpart =~ /[@]/
      return true  if dpart =~ Re['domain']
      return false
    end

    # Check that the argument is mailer-daemon or not
    # @param    [String] email  Email address
    # @return   [True,False]    true: mailer-daemon
    #                           false: Not mailer-daemon
    def is_mailerdaemon(email)
      return false unless email.kind_of?(String)

      re = %r/(?:
             mailer-daemon[@]
            |[<(]mailer-daemon[)>]
            |\Amailer-daemon\z
            |[ ]?mailer-daemon[ ]
            )
      /xi
      return true if email =~ re
      return false
    end

    # Convert Received headers to a structured data
    # @param    [String] argvs  Received header
    # @return   [Array]         Received header as a structured data
    def received(argvs)
      return [] unless argvs.kind_of?(String)

      hosts = []
      value = { 'from' => '', 'by' => '' }

      # Received: (qmail 10000 invoked by uid 999); 24 Apr 2013 00:00:00 +0900
      return [] if argvs =~ /qmail\s+.+invoked\s+/

      if cr = argvs.match(/\Afrom\s+(.+)\s+by\s+([^ ]+)/) then
        # Received: from localhost (localhost)
        #   by nijo.example.jp (V8/cf) id s1QB5ma0018057;
        #   Wed, 26 Feb 2014 06:05:48 -0500
        value['from'] = cr[1]
        value['by']   = cr[2]

      elsif cr = argvs.match(/\bby\s+([^ ]+)(.+)/) then
        # Received: by 10.70.22.98 with SMTP id c2mr1838265pdf.3; Fri, 18 Jul 2014
        #   00:31:02 -0700 (PDT)
        value['from'] = cr[1] + cr[2]
        value['by']   = cr[1]
      end

      if value['from'] =~ / / then
        # Received: from [10.22.22.222] (smtp-gateway.kyoto.ocn.ne.jp [192.0.2.222])
        #   (authenticated bits=0)
        #   by nijo.example.jp (V8/cf) with ESMTP id s1QB5ka0018055;
        #   Wed, 26 Feb 2014 06:05:47 -0500
        received = value['from'].split(' ')
        namelist = []
        addrlist = []
        hostname = ''
        hostaddr = ''

        received.each |e| do
          # Received: from [10.22.22.222] (smtp-gateway.kyoto.ocn.ne.jp [192.0.2.222])
          if e =~ /\A[(\[]\d+[.]\d+[.]\d+[.]\d+[)\]]\z/ then
            # [192.0.2.1] or (192.0.2.1)
            e.gsub(/[]()/, '')
            addrlist << e

          else
            # hostname
            e.gsub(/()/, '')
            namelist << e
          end
        end

        namelist.each |e| do
          # 1. Hostname takes priority over all other IP addresses
          next unless e =~ /[.]/
          hostname = e
          break
        end

        if hostname.length == 0 then 
          # 2. Use IP address as a remote host name
          addrlist.each |e| do
            # Skip if the address is a private address
            next if e =~ /\A(?:10|127)[.]/
            next if e =~ /\A172[.](?:1[6-9]|2[0-9]|3[0-1])[.]/
            next if e =~ /\A192[.]168[.]/
            hostaddr = e
            break
          end
        end

        value['from'] = hostname || hostaddr || addrlist[-1]
      end

      [ 'from', 'by' ].each |e| do
        # Copy entries into hosts
        next unless value[e].length > 0
        value[e].gsub(/()[];?/, '')
        hosts << value[e]
      end
      return hosts
    end

  end
end

