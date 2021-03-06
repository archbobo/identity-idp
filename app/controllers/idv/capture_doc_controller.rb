module Idv
  class CaptureDocController < ApplicationController
    before_action :ensure_user_id_in_session
    before_action :add_unsafe_eval_to_capture_steps

    include Flow::FlowStateMachine

    FSM_SETTINGS = {
      step_url: :idv_capture_doc_step_url,
      final_url: :root_url,
      flow: Idv::Flows::CaptureDocFlow,
      analytics_id: Analytics::CAPTURE_DOC,
    }.freeze

    def index
      ##
      # This allows us to switch between the old doc auth step by step flow and
      # the new document capture flow. When the old step by step flow is retired
      # we should remove this logic and redirect the user directly to the show
      # action.
      #
      if FeatureManagement.document_capture_step_enabled?
        flow.mark_step_complete(:mobile_front_image)
        flow.mark_step_complete(:capture_mobile_back_image)
        flow.mark_step_complete(:selfie)
      else
        flow.mark_step_complete(:document_capture)
      end
      redirect_to_step(next_step)
    end

    private

    def ensure_user_id_in_session
      return if session[:doc_capture_user_id] &&
                token.blank? &&
                document_capture_session_uuid.blank?

      result = if FeatureManagement.document_capture_step_enabled?
                 CaptureDoc::ValidateDocumentCaptureSession.new(document_capture_session_uuid).call
               else
                 CaptureDoc::ValidateRequestToken.new(token).call
               end

      analytics.track_event(FSM_SETTINGS[:analytics_id], result.to_h)
      process_result(result)
    end

    def add_unsafe_eval_to_capture_steps
      return unless %w[
        front_image
        back_image
        mobile_front_image
        mobile_back_image
        capture_mobile_back_image
        selfie
        document_capture
      ].include?(current_step)

      # required to run wasm until wasm-eval is available
      SecureHeaders.append_content_security_policy_directives(
        request,
        script_src: ['\'unsafe-eval\''],
      )
    end

    def process_result(result)
      if result.success?
        reset_session
        session[:doc_capture_user_id] = result.extra[:for_user_id]
        session[:document_capture_session_uuid] = document_capture_session_uuid
        update_sp_session_with_result(result)
      else
        flash[:error] = t('errors.capture_doc.invalid_link')
        redirect_to root_url
      end
    end

    def update_sp_session_with_result(result)
      session[:sp] ||= {}
      session[:sp][:ial2_strict] = result.extra[:ial2_strict]
      session[:sp][:issuer] = result.extra[:sp_issuer]
    end

    def token
      params[:token]
    end

    def document_capture_session_uuid
      params['document-capture-session']
    end
  end
end
