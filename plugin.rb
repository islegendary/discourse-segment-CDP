# frozen_string_literal: true
# name: discourse-segment-CDP
# display_name: Segment CDP Plugin
# about: Smartly send Discourse customer activity data to your Segment CDP workspace
# version: 2.0.0
# authors: Updated by Donnie W from the original plugin by Kyle Welsby
# enabled_site_setting :segment_CDP_enabled

gem 'analytics-ruby', '2.2.8'

after_initialize do
  require 'segment/analytics'

  module ::DiscourseSegmentIdStrategy
    # Returns a normalized version of the email used for tracking
    def self.normalize_email(email)
      email.to_s.strip.downcase
    end

    # Thread-safe fallback ID for guests with no session
    def self.fallback_guest_id
      Thread.current[:segment_fallback_guest_id] ||= "g#{SecureRandom.alphanumeric(35).downcase}"
    end

    # Generates a 36-char anonymous ID using user.id and hash
    def self.generate_user_custom_anonymous_id(user)
      return nil unless user&.id

      prefix = "#{user.id}-dc-" # fixed prefix with user.id
      input = "discourse_custom_anon_v1:#{user.id}:#{Rails.application.secret_key_base}" # salt input with app secret
      
      # OpenSSL::Digest is preloaded in Discourse/Rails environments, no extra 'require' needed
      full_hash = OpenSSL::Digest::SHA256.hexdigest(input) # hashed string stays stable per user

      remaining_len = 36 - prefix.length
      # Trim hash so final ID = 36 chars
      hash_segment = remaining_len > 0 ? full_hash[0...remaining_len] : ""

      "#{prefix}#{hash_segment}"
    end

    # Adds email to context.traits if available (centralized for all tracking calls)
    def self.add_email_to_context(payload, user)
      return payload unless user
      
      email = normalize_email(user.email)
      if email.present?
        payload[:context] ||= {}
        payload[:context][:traits] ||= {}
        payload[:context][:traits][:email] = email
      end
      
      payload
    end

    # Generate context object for track calls following Segment spec
    def self.build_context(request: nil, page_path: nil, page_title: nil, page_url: nil)
      context = {}
      
      # Add page context
      context[:page] = {
        path: page_path,
        referrer: request&.referrer,
        search: request&.query_string&.presence,
        title: page_title,
        url: page_url
      }
      
      # Add request context if available
      context[:userAgent] = request&.user_agent
      context[:ip] = request&.ip
      
      context
    end

    # Returns the appropriate identifier (user_id or anonymous_id)
    def self.get_segment_identifiers(user, session = nil)
      unless user
        if session
          # For guests with session: generate once, reuse
          session[:segment_guest_id] ||= "g#{SecureRandom.alphanumeric(35).downcase}"
          return { anonymous_id: session[:segment_guest_id] }
        else
          # No user or session: fallback to thread-safe shared guest ID
          return { anonymous_id: fallback_guest_id }
        end
      end

      # Use the configured strategy for identifying logged-in users
      setting = SiteSetting.segment_CDP_user_id_source

      case setting
      when 'email'
        # Use email as user_id if present
        normalized = normalize_email(user.email)
        if normalized.present?
          return { user_id: normalized }
        else
          Rails.logger.warn "[Segment CDP Plugin] 'email' selected but missing for user #{user.id}"
        end
      when 'sso_external_id'
        # Use SSO external ID if available
        begin
          sso = user.single_sign_on_record&.external_id || user.external_id
          if sso.present?
            return { user_id: sso }
          else
            Rails.logger.warn "[Segment CDP Plugin] 'sso_external_id' selected but missing for user #{user.id}, falling back to email"
            # Fallback to email if SSO external ID is not available
            normalized = normalize_email(user.email)
            if normalized.present?
              return { user_id: normalized }
            else
              Rails.logger.warn "[Segment CDP Plugin] Email also missing for user #{user.id}, using anonymous fallback"
            end
          end
        rescue NoMethodError => e
          Rails.logger.error "[Segment CDP Plugin] SSO external_id method error for user #{user.id}: #{e.message}, falling back to email"
          # Fallback to email if SSO method doesn't exist
          normalized = normalize_email(user.email)
          if normalized.present?
            return { user_id: normalized }
          else
            Rails.logger.warn "[Segment CDP Plugin] Email also missing for user #{user.id}, using anonymous fallback"
          end
        end
      when 'use_anon'
        # Force anonymous_id for all users
        anon_id = generate_user_custom_anonymous_id(user)
        return { anonymous_id: anon_id } if anon_id # Should always return an ID if user is present
      when 'discourse_id'
        # Use Discourse user.id as string
        return { user_id: user.id.to_s }
      else
        # Unknown config value
        Rails.logger.warn "[Segment CDP Plugin] Unknown user_id_source: '#{setting}' for user #{user.id}"
      end

      # Fallback: try to generate anon ID, else return safe random
      # This is reached if the chosen strategy for an authenticated user didn't return an ID (e.g., email missing).
      fallback = generate_user_custom_anonymous_id(user) || begin
        Rails.logger.error "[Segment CDP Plugin] Failed to generate custom anonymous_id for user #{user&.id}, using emergency fallback."
        "err_ua_#{SecureRandom.alphanumeric(29).downcase}" # Ensures a 36-char ID
      end
      { anonymous_id: fallback }
    end

    # Trait hash sent with identify() call
    def self.get_user_traits(user)
      return {} unless user
      {
        discourse_username: user.username,
        email: (e = normalize_email(user.email); e.presence),
      }.compact
    end
  end

  class ::Analytics
    @client_mutex = Mutex.new

    # Singleton Segment client (thread-safe)
    def self.client
      return nil unless SiteSetting.segment_CDP_enabled? && SiteSetting.segment_CDP_writeKey.present?
      @client_mutex.synchronize do
        @client ||= Segment::Analytics.new(
          write_key: SiteSetting.segment_CDP_writeKey,
          on_error: proc { |status, msg| Rails.logger.error "[Segment CDP Plugin] Segment error #{status}: #{msg}" }
        )
      end
    end

    # Delegate tracking methods to the Segment client
    def self.method_missing(method, *args, &block)
      if (segment_client = client) && segment_client.respond_to?(method)
        segment_client.public_send(method, *args, &block)
      else
        Rails.logger.warn "[Segment CDP Plugin] Analytics client does not respond to unknown method: #{method}"
        super
      end
    end

    def self.respond_to_missing?(method, include_private = false)
      client&.respond_to?(method, include_private) || super
    end
  end

  module ::Jobs
    class EmitSegmentUserIdentify < ::Jobs::Base
      # Job enqueued after user signup to trigger identify
      def execute(args)
        return unless SiteSetting.segment_CDP_enabled?
        user = User.find_by_id(args[:user_id])
        user&.perform_segment_user_identify
      end
    end
  end

  # Hook into user login events - Send identify immediately on login
  DiscourseEvent.on(:user_logged_in) do |user|
    Rails.logger.info "[Segment CDP Plugin] User logged in: #{user.id} - #{user.email}"
    next unless SiteSetting.segment_CDP_enabled?
    
    # Send identify immediately on login
    Rails.logger.info "[Segment CDP Plugin] Sending identify for user #{user.id}"
    user.perform_segment_user_identify
  end

  class ::User
    def perform_segment_user_identify(session = nil)
      return unless SiteSetting.segment_CDP_enabled?
      return if system_user?  # Skip tracking for system users

      Rails.logger.info "[Segment CDP Plugin] Performing identify for user #{self.id}"
      identifiers = ::DiscourseSegmentIdStrategy.get_segment_identifiers(self)
      return if identifiers.empty?

      # Compose payload with traits (IP not available in background job context)
      payload = identifiers.merge(traits: ::DiscourseSegmentIdStrategy.get_user_traits(self))
      
      # Add discourse name and ID to context.traits if available
      payload[:context] ||= {}
      payload[:context][:traits] ||= {}
      context_traits = {}
      context_traits[:discourse_user_id] = id.to_s if id
      context_traits[:discourse_name] = name if name.present?
      payload[:context][:traits].merge!(context_traits) if context_traits.any?

      # Include anonymousId from session if available
      if session && (anonymous_id = session[:segment_guest_id])
        payload[:anonymousId] = anonymous_id
        Rails.logger.info "[Segment CDP Plugin] Including anonymousId from session: #{anonymous_id}"
      end
      
      Rails.logger.info "[Segment CDP Plugin] Sending identify with payload: #{payload.inspect}"
      ::Analytics.identify(payload)
    end

    def emit_segment_signed_up
      return unless SiteSetting.segment_CDP_enabled?
      # Only send on first successful login
      return unless last_seen_at == created_at
      
      identifiers = ::DiscourseSegmentIdStrategy.get_segment_identifiers(self)
      return if identifiers.empty?

      payload = identifiers.merge(
        event: 'Signed Up',
        properties: {
          created_at: created_at.iso8601,
          internal: internal_user?,
          discourse_user_id: id.to_s,
          discourse_name: name
        }.compact,
        context: ::DiscourseSegmentIdStrategy.build_context(
          page_path: "/users/#{username}",
          page_title: "#{name || username} - User Profile",
          page_url: "#{Discourse.base_url}/u/#{username}"
        )
      )
      
      # Add email to context.traits if available
      payload = ::DiscourseSegmentIdStrategy.add_email_to_context(payload, self)

      ::Analytics.track(payload)
    end

    def internal_user?
      # Used for marking internal users by email domain
      return false if SiteSetting.segment_CDP_internal_domain.blank?
      normalized = ::DiscourseSegmentIdStrategy.normalize_email(email)
      domain = SiteSetting.segment_CDP_internal_domain.to_s.strip.downcase
      normalized.present? && normalized.end_with?(domain)
    end

    private
    
    def system_user?
      # Add logic to determine if the user is a system user
      # For example, check if the username is "discobot" or if the email matches a pattern
      username == "discobot" || email.include?("discobot")
    end

  end

  class ::ApplicationController
    before_action :emit_segment_user_tracker

    SEGMENT_CDP_EXCLUDES = {
      'stylesheets' => :all,
      'user_avatars' => :all,
      'about' => ['live_post_counts'],
      'topics' => ['timings'],
      'session' => ['csrf', 'get_honeypot_value', 'passkey_challenge', 'destroy'],
      'users' => ['check_username'],
      'metadata' => ['opensearch', 'manifest'],
      'static' => ['service_worker_asset'],
      'presence' => ['get', 'update'],
      'tags' => ['search'],
      'reports' => ['bulk'],
      'extra_locales' => ['show'],
      'svg_sprite' => ['show']
    }.freeze

# Map controller/action combinations to friendly page names
    SEGMENT_PAGE_NAMES = {
      'static' => {
        'enter' => 'Site Welcome',
        'show' => {
          'faq.html' => 'FAQ',
          'guidelines.html' => 'Guidelines',
          'tos.html' => 'Terms of Service',
          'privacy.html' => 'Privacy Policy',
          'signup' => 'Sign Up'
        }
      },
      'list' => {
        'latest' => 'Topics Latest',
        'top' => 'Topics Top',
        'new' => 'Topics New',
        'unread' => 'Topics Unread',
        'categories' => 'Categories List'
      },
      'badges' => {
        'index' => 'Badges List'
      },
      'topics' => {
        'show' => 'Topic View',
        'by_external_id' => 'Topic External ID'
      },
      'categories' => {
        'show' => 'Category View',
        'index' => 'Categories List',
        'categories_and_latest' => 'Categories Latest'
      },
      'users' => {
        'show' => 'User Profile',
        'preferences' => 'User Preferences',
        'account_created' => 'User Created'
      },
      'session' => {
        'sso' => 'Session SSO',
        'sso_provider' => 'Session Provider',
        'create' => 'Logged In'
      },
      'search' => {
        'show' => 'Search Results'
      },
      'tags' => {
        'show' => 'Tag View',
        'index' => 'Tags List'
      },
      'groups' => {
        'show' => 'Group View',
        'index' => 'Groups List'
      },
      'admin' => {
        'index' => 'Admin Dashboard',
        'plugins' => 'Admin Plugins',
        'site_settings' => 'Admin Settings'
      }
    }.freeze

    def emit_segment_user_tracker
      return unless SiteSetting.segment_CDP_enabled?
      return if segment_common_controller_actions?

      identifiers = ::DiscourseSegmentIdStrategy.get_segment_identifiers(current_user, session)
      return if identifiers.empty?

 # Get friendly page name or fallback to controller#action
      page_name = segment_page_title
      page_name ||= "#{controller_name.titleize} #{action_name.titleize}"

      # Track full-page view for guests and users
      payload = identifiers.merge(
        name: page_name,
        properties: {
          url: request.original_url,
          path: request.path,
          referrer: request.referrer,
          title: segment_page_title,
          controller: controller_name,
          action: action_name
        },
        context: {
          ip: request.ip,
          userAgent: request.user_agent
        }
      )
      
      # Add email to context.traits if available
      payload = ::DiscourseSegmentIdStrategy.add_email_to_context(payload, current_user)
      
      ::Analytics.page(payload)
    end

    private

    # Ignore noisy or useless page routes
    def segment_common_controller_actions?
      SEGMENT_CDP_EXCLUDES[controller_name] == :all ||
        SEGMENT_CDP_EXCLUDES[controller_name]&.include?(action_name)
    end
  end

  class ::Post
    after_create :emit_segment_post_created

    def emit_segment_post_created
      return unless SiteSetting.segment_CDP_enabled?
      author = user
      return unless author

      identifiers = ::DiscourseSegmentIdStrategy.get_segment_identifiers(author)
      return if identifiers.empty?

      payload = identifiers.merge(
        event: 'Post Created',
        properties: {
          created_at: created_at.iso8601,
          internal: author.internal_user?,
          post_id: id,
          post_number: post_number,
          reply_to_post_number: reply_to_post_number,
          since_topic_created: topic ? (created_at - topic.created_at).to_i : nil,
          topic_id: topic_id,
          url: topic.url
        }.compact,
        context: ::DiscourseSegmentIdStrategy.build_context(
          page_path: topic.relative_url,
          page_title: topic.title,
          page_url: topic.url
        )
      )
      
      # Add email to context.traits if available
      payload = ::DiscourseSegmentIdStrategy.add_email_to_context(payload, author)

      ::Analytics.track(payload)
    end
  end

  class ::Topic
    after_create :emit_segment_topic_created

    def emit_segment_topic_created
      return unless SiteSetting.segment_CDP_enabled?
      author = user
      return unless author

      identifiers = ::DiscourseSegmentIdStrategy.get_segment_identifiers(author)
      return if identifiers.empty?

      payload = identifiers.merge(
        event: 'Topic Created',
        properties: {
          category_id: category_id,
          created_at: created_at.iso8601,
          internal: author.internal_user?,
          slug: slug,
          title: title,
          topic_id: id,
          url: url
        }.compact,
        context: ::DiscourseSegmentIdStrategy.build_context(
          page_path: relative_url,
          page_title: title,
          page_url: url
        )
      )
      
      # Add email to context.traits if available
      payload = ::DiscourseSegmentIdStrategy.add_email_to_context(payload, author)

      ::Analytics.track(payload)
    end
  end

  class ::TopicTag
    after_create :emit_segment_topic_tagged

    def emit_segment_topic_tagged
      return unless SiteSetting.segment_CDP_enabled?
      # Uses fallback guest_id since no user context
      identifiers = ::DiscourseSegmentIdStrategy.get_segment_identifiers(nil)
      return if identifiers.empty?

      payload = identifiers.merge(
        event: 'Topic Tag Created',
        properties: {
          tag_name: tag&.name,
          topic_id: topic_id,
          url: topic.url
        }.compact,
        context: ::DiscourseSegmentIdStrategy.build_context(
          page_path: topic.relative_url,
          page_title: topic.title,
          page_url: topic.url
        )
      )
      
      # Add email to context.traits if available (no user in this case)
      payload = ::DiscourseSegmentIdStrategy.add_email_to_context(payload, nil)

      ::Analytics.track(payload)
    end
  end

  class ::UserAction
    after_create :emit_segment_post_liked, if: -> { action_type == UserAction::LIKE }

    def emit_segment_post_liked
      return unless SiteSetting.segment_CDP_enabled?
      actor = user
      return unless actor

      identifiers = ::DiscourseSegmentIdStrategy.get_segment_identifiers(actor)
      return if identifiers.empty?

      payload = identifiers.merge(
        event: 'Post Liked',
        properties: {
          internal: actor.internal_user?,
          like_count_on_topic: target_topic&.like_count,
          post_id: target_post_id,
          topic_id: target_topic_id
        }.compact,
        context: ::DiscourseSegmentIdStrategy.build_context(
          page_path: target_topic&.relative_url,
          page_title: target_topic&.title,
          page_url: target_topic&.url
        )
      )
      
      # Add email to context.traits if available
      payload = ::DiscourseSegmentIdStrategy.add_email_to_context(payload, actor)

      ::Analytics.track(payload)
    end
  end
end
