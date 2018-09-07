require 'rails_helper'

describe Users::WebauthnSetupController do
  include WebauthnHelper

  describe 'before_actions' do
    it 'includes appropriate before_actions' do
      expect(subject).to have_actions(
        :before,
        :authenticate_user!,
        [:confirm_two_factor_authenticated, if: :two_factor_enabled?]
      )
    end
  end

  describe 'when not signed in' do
    describe 'GET new' do
      it 'redirects to root url' do
        get :new

        expect(response).to redirect_to(root_url)
      end
    end

    describe 'patch confirm' do
      it 'redirects to root url' do
        patch :confirm

        expect(response).to redirect_to(root_url)
      end
    end
  end

  describe 'when signed in' do
    before do
      stub_analytics
      stub_sign_in
    end

    describe 'GET new' do
      it 'saves challenge in session' do
        get :new

        expect(subject.user_session[:webauthn_challenge].length).to eq(16)
      end

      it 'tracks page visit' do
        stub_sign_in
        stub_analytics

        expect(@analytics).to receive(:track_event).with(Analytics::WEBAUTHN_SETUP_VISIT)

        get :new
      end
    end

    describe 'patch confirm' do
      let(:params) do
        {
          attestation_object: attestation_object,
          client_data_json: client_data_json,
          name: 'mykey',
        }
      end
      before do
        allow(Figaro.env).to receive(:domain_name).and_return('localhost:3000')
        controller.user_session[:webauthn_challenge] = challenge
      end

      it 'processes a valid webauthn' do
        patch :confirm, params: params

        expect(response).to redirect_to(account_url)
        expect(flash.now[:success]).to eq t('notices.webauthn_added')
      end

      it 'tracks the submission' do
        result = { success: true, errors: {} }
        expect(@analytics).to receive(:track_event).
          with(Analytics::WEBAUTHN_SETUP_SUBMITTED, result)

        patch :confirm, params: params
      end
    end

    describe 'delete' do
      it 'deletes a webauthn configuration' do
        cfg = create_webauthn_configuration(controller.current_user, 'key1', 'id1', 'foo1')
        delete :delete, params: { id: cfg.id }

        expect(response).to redirect_to(account_url)
        expect(flash.now[:success]).to eq t('notices.webauthn_deleted')
        expect(WebauthnConfiguration.count).to eq(0)
      end

      it 'tracks the delete' do
        cfg = create_webauthn_configuration(controller.current_user, 'key1', 'id1', 'foo1')

        result = { success: true, mfa_options: 0 }
        expect(@analytics).to receive(:track_event).with(Analytics::WEBAUTHN_DELETED, result)

        delete :delete, params: { id: cfg.id }
      end
    end
  end

  def create_webauthn_configuration(user, name, id, key)
    WebauthnConfiguration.create(user_id: user.id,
                                 credential_public_key: key,
                                 credential_id: id,
                                 name: name)
  end
end
