require 'rails_helper'
require 'shared_examples_for_failures'

RSpec.describe Api::UsersController, type: :request do

  before do
    Timecop.freeze Date.new(2017)
  end

  after do
    Timecop.return
  end

  describe 'POST #create' do
    before do
      Flipper.enable :feature_registration
    end

    let(:payload) { {
      user: {
        email: 'john@doe.com',
      },
    } }

    subject { post api_users_path, params: payload, as: :json }

    context 'with valid attributes' do
      let!(:tos) { create :terms_of_service, :in_the_past }

      before { subject }

      it 'succeeds' do
        expect(response).to have_http_status(:created)
      end

      it 'matches the users/create schema' do
        expect(response).to match_response_schema('users/create')
      end

      it 'saves the new user' do
        expect(User.find_by(email: 'john@doe.com')).to be_present
      end

      it 'returns the new user' do
        contact = JSON.parse(response.body)['data']
        expect(contact['id']).not_to be_nil
        expect(contact['attributes']['email']).to eq('john@doe.com')
      end

      it 'accepts terms of service for the user' do
        user = User.find_by(email: 'john@doe.com')
        expect(user.accepted_tos?).to be true
      end

      it 'returns a token valid for 1 day' do
        token = JSON.parse(response.body)['meta']['token']
        decoded_token = JsonWebToken.decode(token)
        expect(decoded_token[:exp]).to eq(1.day.from_now.to_i)
      end
    end

    context 'with missing paramenters' do
      let(:payload) { { } }

      before { subject }

      it_behaves_like 'API errors', :unprocessable_entity, {
        errors: [{
          status: '422 Unprocessable Entity',
          code: 'parameter_missing',
          title: 'Parameter is missing',
          detail: 'A parameter is missing or empty but it is required.',
          source: { pointer: '/user' },
        }],
      }
    end

    context 'with existing email' do
      before do
        create :user, email: payload[:user][:email]
        subject
      end

      it_behaves_like 'API errors', :unprocessable_entity, {
        errors: [{
          status: '422 Unprocessable Entity',
          code: 'taken',
          title: 'Resource validation failed',
          detail: 'Resource cannot be saved because of validation constraints.',
          source: { pointer: '/user/email' },
        }],
      }
    end

    context 'with feature_registration flag disabled' do
      before do
        Flipper.disable :feature_registration
        subject
      end

      it_behaves_like 'API errors', :forbidden, errors: [
        {
          status: '403 Forbidden',
          code: 'registration_disabled',
          title: 'Registration disabled',
          detail: 'Registration has been disabled by the administrator.',
        },
      ]
    end
  end

  describe 'GET #show' do
    let(:user) { create :user }
    let(:token) { user.token }

    subject { get me_api_users_path, headers: { 'Authorization': token } }

    context 'with valid token' do
      before { subject }

      it 'succeeds' do
        expect(response).to have_http_status(:ok)
      end

      it 'matches the users/user schema' do
        expect(response).to match_response_schema('users/me')
      end

      it 'returns the corresponding user' do
        json_user = JSON.parse(response.body)['data']
        expect(json_user['id']).to eq(user.id)
      end
    end

    context 'with not accepted terms of service' do
      let!(:tos) { create :terms_of_service, :in_the_past }
      let(:user) { create :user, :not_accepted_tos }

      before { subject }

      it 'succeeds' do
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with token of a deleted user' do
      before do
        user.destroy
        subject
      end

      it_behaves_like 'API errors', :unauthorized, errors: [{
        status: '401 Unauthorized',
        code: 'unauthorized',
        title: 'Authorization is required',
        detail: 'Resource you try to reach requires a valid Authorization token.',
      }]
    end

    context 'with expired token' do
      let(:token) { user.token(expiration: 1.day.ago) }

      before { subject }

      it_behaves_like 'API errors', :unauthorized, {
        errors: [{
          status: '401 Unauthorized',
          code: 'unauthorized',
          title: 'Authorization is required',
          detail: 'Resource you try to reach requires a valid Authorization token.',
        }],
      }
    end

    context 'with no Authorization header' do
      let(:token) { nil }

      before { subject }

      it_behaves_like 'API errors', :unauthorized, {
        errors: [{
          status: '401 Unauthorized',
          code: 'unauthorized',
          title: 'Authorization is required',
          detail: 'Resource you try to reach requires a valid Authorization token.',
        }],
      }
    end
  end

  describe 'PATCH #update' do
    let(:user) { create :user, :activated }
    let(:token) { user.token }
    let(:time_zone) { nil }
    let(:payload) do
      {
        user: {
          username: username,
          email: email,
          time_zone: time_zone,
        },
      }
    end

    subject { patch me_api_users_path, params: payload,
                                       headers: { 'Authorization': token },
                                       as: :json }

    context 'with valid parameters' do
      let(:username) { 'douglasjones' }
      let(:email) { 'douglas.jones@lessy.io' }
      let(:time_zone) { 'Europe/Paris' }

      before { subject }

      it 'succeeds' do
        expect(response).to have_http_status(:ok)
      end

      it 'matches the users/update schema' do
        expect(response).to match_response_schema('users/update')
      end

      it 'saves the new user' do
        user.reload
        expect(user.username).to eq username
        expect(user.email).to eq email
        expect(user.time_zone).to eq time_zone
      end

      it 'returns the new user' do
        contact = JSON.parse(response.body)['data']
        expect(contact['id']).to eq(user.id)
        expect(contact['attributes']['username']).to eq username
        expect(contact['attributes']['email']).to eq email
        expect(contact['attributes']['timeZone']).to eq time_zone
      end
    end

    context 'with partial parameters' do
      let(:username) { 'douglasjones' }
      let(:email) { nil }
      let(:time_zone) { nil }

      before { subject }

      it 'succeeds' do
        expect(response).to have_http_status(:ok)
      end

      it 'does not save nil email or time_zone' do
        expect(user.reload.email).not_to be nil
        expect(user.reload.time_zone).not_to be nil
      end
    end

    context 'with existing email' do
      let(:username) { 'douglasjones' }
      let(:email) { 'douglas.jones@lessy.io' }

      before do
        create :user, email: email
        subject
      end

      it_behaves_like 'API errors', :unprocessable_entity, {
        errors: [{
          status: '422 Unprocessable Entity',
          code: 'taken',
          title: 'Resource validation failed',
          detail: 'Resource cannot be saved because of validation constraints.',
          source: { pointer: '/user/email' },
        }],
      }
    end

    context 'with invalid username' do
      let(:username) { 'Douglas Jones' }
      let(:email) { nil }

      before { subject }

      it_behaves_like 'API errors', :unprocessable_entity, {
        errors: [{
          status: '422 Unprocessable Entity',
          code: 'invalid',
          title: 'Resource validation failed',
          detail: 'Resource cannot be saved because of validation constraints.',
          source: { pointer: '/user/username' },
        }],
      }
    end

    context 'with too long username' do
      let(:username) { 'douglasdouglasdouglasdouglasdouglasdouglas' }
      let(:email) { nil }

      before { subject }

      it_behaves_like 'API errors', :unprocessable_entity, {
        errors: [{
          status: '422 Unprocessable Entity',
          code: 'too_long',
          title: 'Resource validation failed',
          detail: 'Resource cannot be saved because of validation constraints.',
          source: { pointer: '/user/username' },
        }],
      }
    end

    context 'with existing username' do
      let(:username) { 'douglasjones' }
      let(:email) { nil }

      before do
        create :user, username: username
        subject
      end

      it_behaves_like 'API errors', :unprocessable_entity, {
        errors: [{
          status: '422 Unprocessable Entity',
          code: 'taken',
          title: 'Resource validation failed',
          detail: 'Resource cannot be saved because of validation constraints.',
          source: { pointer: '/user/username' },
        }],
      }
    end

    context 'with blacklisted username' do
      let(:username) { 'dashboard' }
      let(:email) { nil }

      before { subject }

      it_behaves_like 'API errors', :unprocessable_entity, {
        errors: [{
          status: '422 Unprocessable Entity',
          code: 'exclusion',
          title: 'Resource validation failed',
          detail: 'Resource cannot be saved because of validation constraints.',
          source: { pointer: '/user/username' },
        }],
      }
    end

    context 'with invalid token' do
      let(:token) { 'not-a-token' }
      let(:username) { 'douglasjones' }
      let(:email) { nil }

      before { subject }

      it_behaves_like 'API errors', :unauthorized, errors: [{
        status: '401 Unauthorized',
        code: 'unauthorized',
        title: 'Authorization is required',
        detail: 'Resource you try to reach requires a valid Authorization token.',
      }]
    end

    context 'with not accepted terms of service' do
      let!(:tos) { create :terms_of_service, :in_the_past }
      let(:user) { create :user, :activated, :not_accepted_tos }
      let(:username) { 'douglasjones' }
      let(:email) { nil }

      before { subject }

      it_behaves_like 'API errors', :forbidden, errors: [{
        status: '403 Forbidden',
        code: 'tos_not_accepted',
        title: 'Terms of service not accepted',
        detail: 'Resource you try to reach requires that you accept the terms of service.',
      }]
    end

    context 'with inactive user' do
      let(:user) { create :user, :inactive }
      let(:username) { 'douglasjones' }
      let(:email) { nil }

      before { subject }

      it_behaves_like 'API errors', :forbidden, errors: [{
        status: '403 Forbidden',
        code: 'user_inactive',
        title: 'User is inactive',
        detail: 'The user did not activate its account.',
        source: { pointer: '/user' },
      }]
    end
  end

  describe 'DELETE #destroy' do
    let(:user) { create :user, :activated }
    let(:token) { user.token(sudo: true) }

    subject { delete me_api_users_path, headers: { 'Authorization': token } }

    context 'when authorized with sudo token' do
      before { subject }

      it 'succeeds with no content' do
        expect(response).to have_http_status(:no_content)
      end

      it 'destroys the corresponding user' do
        expect(User.find_by(id: user.id)).not_to be_present
      end
    end

    context 'with inactive user and not sudo token' do
      let(:user) { create :user, :inactive }
      let(:token) { user.token(sudo: false) }

      before { subject }

      it 'succeeds with no content' do
        expect(response).to have_http_status(:no_content)
      end

      it 'destroys the corresponding user' do
        expect(User.find_by(id: user.id)).not_to be_present
      end
    end

    context 'when authorized with not sudo token' do
      let(:token) { user.token(sudo: false) }

      before { subject }

      it_behaves_like 'API errors', :forbidden, errors: [{
        status: '403 Forbidden',
        code: 'sudo_required',
        title: 'Sudo authorization token is required',
        detail: 'Resource you try to reach requires higher permissions.',
      }]
    end

    context 'when not authorized' do
      let(:token) { 'not-a-token' }

      before { subject }

      it_behaves_like 'API errors', :unauthorized, errors: [{
        status: '401 Unauthorized',
        code: 'unauthorized',
        title: 'Authorization is required',
        detail: 'Resource you try to reach requires a valid Authorization token.',
      }]
    end
  end

  describe 'POST #accept_tos' do
    let!(:tos) { create :terms_of_service, :in_the_past }
    let(:user) { create :user, :not_accepted_tos }

    subject { post me_terms_of_services_api_users_path, headers: { 'Authorization': token } }

    context 'with valid authorization' do
      let(:token) { user.token }

      before { subject }

      it 'succeeds' do
        expect(response).to have_http_status(:ok)
      end

      it 'matches the users/accept_tos schema' do
        expect(response).to match_response_schema('users/accept_tos')
      end

      it 'accepts terms of service for the user' do
        expect(user.reload.accepted_tos?).to be true
      end
    end

    context 'with invalid authorization' do
      let(:token) { 'not a token' }

      before { subject }

      it_behaves_like 'API errors', :unauthorized, errors: [{
        status: '401 Unauthorized',
        code: 'unauthorized',
        title: 'Authorization is required',
        detail: 'Resource you try to reach requires a valid Authorization token.',
      }]
    end
  end
end
