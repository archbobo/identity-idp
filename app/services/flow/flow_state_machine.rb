module Flow
  module FlowStateMachine
    extend ActiveSupport::Concern

    included do
      before_action :fsm_initialize
      before_action :ensure_correct_step, only: :show
    end

    attr_accessor :flow

    def index
      redirect_to_step(next_step)
    end

    def show
      step = current_step
      analytics.track_event(analytics_visited, step: step) if @analytics_id
      Funnel::DocAuth::RegisterStep.new(user_id, issuer).call(step, :view, true)
      register_campaign
      render_step(step, flow.flow_session)
    end

    def update
      step = current_step
      result = flow.handle(step)
      analytics.track_event(analytics_submitted, result.to_h.merge(step: step)) if @analytics_id
      register_update_step(step, result)
      flow_finish and return unless next_step
      render_update(step, result)
    end

    def poll_with_meta_refresh(seconds)
      @meta_refresh = seconds
    end

    private

    def current_step
      params[:step]&.underscore
    end

    def register_campaign
      Funnel::DocAuth::RegisterCampaign.call(user_id, session[:ial2_with_no_sp_campaign])
    end

    def user_id
      current_user ? current_user.id : user_id_from_token
    end

    def user_id_from_token
      current_session[:doc_capture_user_id]
    end

    def register_update_step(step, result)
      Funnel::DocAuth::RegisterStep.new(user_id, issuer).call(step, :update, result.success?)
    end

    def issuer
      sp_session[:issuer]
    end

    def fsm_initialize
      klass = self.class
      flow = klass::FSM_SETTINGS[:flow]
      @name = klass.name.underscore.gsub('_controller', '')
      @step_url = klass::FSM_SETTINGS[:step_url]
      @final_url = klass::FSM_SETTINGS[:final_url]
      @analytics_id = klass::FSM_SETTINGS[:analytics_id]
      @view = klass::FSM_SETTINGS[:view]

      current_session[@name] ||= {}
      @flow = flow.new(self, current_session, @name)
    end

    def render_update(step, result)
      redirect_to next_step and return if next_step_is_url
      move_to_next_step and return if result.success?
      ensure_correct_step and return
      set_error_and_render(step, result)
    end

    def set_error_and_render(step, result)
      flow_session = flow.flow_session
      flow_session[:error_message] = result.first_error_message
      render_step(step, flow_session)
    end

    def move_to_next_step
      current_session[@name] = flow.flow_session
      redirect_to_step(next_step)
    end

    def render_step(step, flow_session)
      @params = params
      @request = request
      return if call_optional_show_step(step)
      step_params = flow.extra_view_variables(step)
      local_params = step_params.merge(flow_session: flow_session)
      render template: "#{@view || @name}/#{step}", locals: local_params
    end

    def call_optional_show_step(step)
      return unless @flow.class.const_defined?('OPTIONAL_SHOW_STEPS')
      optional_show_step = @flow.class::OPTIONAL_SHOW_STEPS.with_indifferent_access[step]
      return unless optional_show_step
      optional_show_step.new(@flow).base_call
      if next_step.to_s != step
        if next_step_is_url
          redirect_to next_step
        else
          redirect_to_step(next_step)
        end
        return true
      end
      false
    end

    def ensure_correct_step
      redirect_to_step(next_step) if next_step.to_s != current_step
    end

    def flow_finish
      redirect_to send(@final_url)
    end

    def redirect_to_step(step)
      flow_finish and return unless next_step
      redirect_to send(@step_url, step: step)
    end

    def analytics_submitted
      @analytics_id + ' submitted'
    end

    def analytics_visited
      @analytics_id + ' visited'
    end

    def next_step
      flow.next_step
    end

    def next_step_is_url
      next_step.to_s.index(':')
    end

    def current_session
      user_session || session
    end
  end
end

# sample usage:
#
# class FooController
#   include Flow::FlowStateMachine
#
#   FSM_SETTINGS = {
#     step_url: :foo_step_url,
#     final_url: :after_foo_url,
#     flow: FooFlow,
#     analytics_id: Analytics::FOO,
#   }.freeze
# end
