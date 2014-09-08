module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    # For more information visit {CashFlows Integration Developer Help}[http://cashflows.com/support/developers.php]
    #
    # :order_id must be provided with each transaction.
    #
    # Written by Piers Chambers (Varyonic.com)
    class CashFlowsGateway < Gateway
      self.test_url = 'https://secure.cashflows.com/gateway/remote'
      self.live_url = 'https://secure.cashflows.com/gateway/remote'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.homepage_url = 'http://www.cashflows.com'
      self.display_name = 'CashFlows'

      RESPONSE_CODE, TRANSACTION_ID, CARD_CODE_RESPONSE_CODE, AUTHORIZATION_CODE, RESPONSE_REASON_TEXT = 0, 1, 2, 3, 4

      def initialize(options={})
        requires!(options, :auth_id, :auth_pass)
        super
      end

      def purchase(money, payment, options={})
        requires!(options, :order_id)

        post = {}
        add_invoice(post, options)
        add_amount(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('Sale', post)
      end

      def authorize(money, payment, options={})
        requires!(options, :order_id)

        post = {}
        add_invoice(post, options)
        add_amount(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('hold', post)
      end

      def capture(money, authorization, options={})
        commit('capture', post)
      end

      def refund(money, authorization, options={})
        post = {}
        add_amount(post, money, options)
        post[:tran_orig_id] = options[:order_id]
        commit('refund', post)
      end

      def void(authorization, options={})
        post = {}
        add_amount(post, money, options)
        post[:tran_orig_id] = options[:order_id]
        commit('void', post)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      private

      def add_amount(post, money, options)
        post[:tran_amount] = amount(money)
        post[:tran_currency] = (options[:currency] || currency(money))
      end

      def add_customer_data(post, options)
        post[:cust_email] = options[:email] || 'test@example.com'
        post[:cust_ip] = options[:ip] || '0.0.0.0'
      end

      def add_address(post, creditcard, options)
        if address = options[:billing_address] || options[:address]
          post[:cust_address] = [
            address[:address1].to_s,
            address[:address2].to_s,
            address[:city].to_s,
            address[:state].to_s
          ].compact.join('\n')
          post[:cust_postcode] = address[:zip].to_s
          post[:cust_country] = address[:country].to_s
          post[:cust_tel] = address[:phone].to_s
        end
      end

      def add_invoice(post, options)
        post[:tran_ref] = options[:order_id]
        post[:tran_desc] = options[:description].slice(0,99) if options.has_key? :description
      end

      def add_payment(post, card)
        name  = [card.first_name, card.last_name].join(' ').slice(0, 60)
        year  = sprintf("%.4i", card.year)
        month = sprintf("%.2i", card.month)
        post[:card_num] = card.number
        post[:card_cvv] = card.verification_value
        post[:card_expiry] = "#{month}#{year[2..3]}"
        post[:cust_name] = name
      end

      def parse(body)
        fields = body.split('|')

        params = {
          authorised:     fields[RESPONSE_CODE],
          transaction_id: fields[TRANSACTION_ID],
          cvv_resonse:    fields[CARD_CODE_RESPONSE_CODE],
          authorisation:  fields[AUTHORIZATION_CODE],
          message:        fields[RESPONSE_REASON_TEXT].strip,
        }
        Response.new(
          success_from(params),
          params[:message],
          params,
          authorization: params[:transaction_id],
          test: test?
        )
      end

      def commit(action, parameters)
        url = (test? ? test_url : live_url)
        parse(ssl_post(url, post_data(action, parameters)))
      end

      def success_from(params)
        params[:authorised] == 'A'
      end

      # def message_from(params)
      # end

      # def authorization_from(params)
      #   params[:transaction_id]
      # end

      def post_data(action, parameters = {})
        post = {}

        post[:auth_id]       = @options[:auth_id]
        post[:auth_pass]     = @options[:auth_pass]
        post[:tran_type]     = action
        post[:tran_class]    = 'ecom'
        post[:tran_testmode] = test? ? '1' : '0'

        request = post.merge(parameters).collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join("&")
        request
      end
    end
  end
end
