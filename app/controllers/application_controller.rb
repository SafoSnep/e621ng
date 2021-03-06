class ApplicationController < ActionController::Base
  class APIThrottled < Exception; end

  skip_forgery_protection if: -> { SessionLoader.new(request).has_api_authentication? }
  before_action :reset_current_user
  before_action :set_current_user
  before_action :set_title
  before_action :normalize_search
  before_action :api_check
  before_action :set_variant
  before_action :enable_cors
  after_action :reset_current_user
  layout "default"

  include DeferredPosts
  helper_method :deferred_post_ids, :deferred_posts

  rescue_from Exception, :with => :rescue_exception
  rescue_from User::PrivilegeError, :with => :access_denied
  rescue_from ActionController::UnpermittedParameters, :with => :access_denied

  # This is raised on requests to `/blah.js`. Rails has already rendered StaticController#not_found
  # here, so calling `rescue_exception` would cause a double render error.
  rescue_from ActionController::InvalidCrossOriginRequest, with: -> {}

  protected

  def self.rescue_with(*klasses, status: 500)
    rescue_from *klasses do |exception|
      render_error_page(status, exception)
    end
  end

  def enable_cors
    response.headers["Access-Control-Allow-Origin"] = "*"
  end

  def api_check
    if !CurrentUser.is_anonymous? && !request.get? && !request.head?
      throttled = CurrentUser.user.token_bucket.throttled?
      headers["X-Api-Limit"] = CurrentUser.user.token_bucket.cached_count.to_s

      if throttled
        raise APIThrottled.new
        return false
      end
    end

    true
  end

  def rescue_exception(exception)
    @exception = exception

    if Rails.env.test? && ENV["DEBUG"]
      puts "---"
      STDERR.puts("#{exception.class} exception thrown: #{exception.message}")
      exception.backtrace.each {|x| STDERR.puts(x)}
      puts "---"
    end

    ExceptionLog.add(exception, CurrentUser.ip_addr, {
        host: Socket.gethostname,
        params: params,
        user_id: CurrentUser.id,
        referrer: request.referrer,
        user_agent: request.user_agent
    })

    case exception
    when APIThrottled
      render_error_page(429, exception, message: "Too many requests")
    when ActiveRecord::QueryCanceled
      render_error_page(500, exception, message: "The database timed out running your query.")
    when ActionController::BadRequest
      render_error_page(400, exception)
    when SessionLoader::AuthenticationFailure
      render_error_page(401, exception)
    when ActionController::InvalidAuthenticityToken
      render_error_page(403, exception)
    when ActiveRecord::RecordNotFound
      render_error_page(404, exception, message: "That record was not found.")
    when ActionController::RoutingError
      render_error_page(405, exception)
    when ActionController::UnknownFormat, ActionView::MissingTemplate
      render_error_page(406, exception, message: "#{request.format.to_s} is not a supported format for this page", format: :html)
    when Danbooru::Paginator::PaginationError
      render_error_page(410, exception)
    when Post::SearchError
      render_error_page(422, exception)
    when NotImplementedError
      render_error_page(501, exception, message: "This feature isn't available: #{exception.message}")
    when PG::ConnectionBad
      render_error_page(503, exception, message: "The database is unavailable. Try again later.")
    else
      render_error_page(500, exception)
    end
  end

  def render_error_page(status, exception, message: exception.message, format: request.format.symbol)
    @exception = exception
    @expected = status < 500
    @message = message.encode("utf-8", { invalid: :replace, undef: :replace })
    @backtrace = Rails.backtrace_cleaner.clean(@exception.backtrace)
    format = :html unless format.in?(%i[html json js atom])

    # if InvalidAuthenticityToken was raised, CurrentUser isn't set so we have to use the blank layout.
    layout = CurrentUser.user.present? ? "default" : "blank"

    DanbooruLogger.log(@exception, expected: @expected)
    render "static/error", layout: layout, status: status, formats: format
  end

  def access_denied(exception = nil)
    previous_url = params[:url] || request.fullpath
    @message = "Access Denied: #{exception}" if exception.is_a?(String)
    @message ||= exception&.message || "Access Denied"

    respond_to do |fmt|
      fmt.html do
        if CurrentUser.is_anonymous?
          if request.get?
            redirect_to new_session_path(:url => previous_url), notice: @message
          else
            redirect_to new_session_path, notice: @message
          end
        else
          render :template => "static/access_denied", :status => 403
        end
      end
      fmt.json do
        render :json => {:success => false, reason: @message}.to_json, :status => 403
      end
      fmt.js do
        render js: "", :status => 403
      end
    end
  end

  def set_current_user
    SessionLoader.new(request).load
  end

  def reset_current_user
    CurrentUser.user = nil
    CurrentUser.ip_addr = nil
    CurrentUser.safe_mode = false
    CurrentUser.root_url = root_url.chomp("/")
  end

  def set_variant
    request.variant = params[:variant].try(:to_sym)
  end

  User::Roles.each do |role|
    define_method("#{role}_only") do
      if !CurrentUser.user.send("is_#{role}?") || CurrentUser.user.is_banned? || IpBan.is_banned?(CurrentUser.ip_addr)
        access_denied
      end
    end
  end

  def set_title
    @page_title = Danbooru.config.app_name + "/#{params[:controller]}"
  end

  # Remove blank `search` params from the url.
  #
  # /tags?search[name]=touhou&search[category]=&search[order]=
  # => /tags?search[name]=touhou
  def normalize_search
    return unless request.get?
    params[:search] ||= ActionController::Parameters.new

    deep_reject_blank = lambda do |hash|
      hash.reject { |k, v| v.blank? || (v.is_a?(Hash) && deep_reject_blank.call(v).blank?) }
    end
    nonblank_search_params = deep_reject_blank.call(params[:search])

    if nonblank_search_params != params[:search]
      params[:search] = nonblank_search_params
      redirect_to url_for(params: params.except(:controller, :action, :index).permit!)
    end
  end

  def search_params
    params.fetch(:search, {}).permit!
  end
end
