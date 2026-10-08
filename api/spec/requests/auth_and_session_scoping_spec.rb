# frozen_string_literal: true

require 'rails_helper'

# Request specs for auth, tenant scoping, the no-JWT candidate routes, and
# session end.
#
# EXPECTED RED on current code (do NOT "fix" here — todos 24 and 27 do):
#   B1 — POST /api/v1/sessions/:token/audio_complete hardcodes
#        end_reason='all_covered' with no coverage check
#        (api/app/controllers/api/v1/sessions_controller.rb:118-129).
#   B4 — login tenant fallback runs `SELECT scheme FROM organizations LIMIT 1`
#        (api/app/controllers/api/v1/authentication_controller.rb:24-29) —
#        no ORDER BY, no id != 0 guard, so the reserved id=0 org can be bound.
RSpec.describe 'Auth, tenant scoping, candidate routes and session end', type: :request do
  before(:all) do
    # The suite issues several login calls; keep the Redis-backed Rack::Attack
    # throttle from turning repeated local runs into 429s (throttling itself is
    # not what these specs assert).
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  # ── Fixtures ────────────────────────────────────────────────────────────────

  def make_org(scheme)
    Organization.create!(
      name:       scheme.titleize,
      scheme:     scheme,
      identifier: scheme,
      host:       "#{scheme}.example.com"
    )
  end

  def make_reserved_org!
    # id=0 is the reserved default org (db/seeds.rb: do not use). Raw insert
    # pins both the id and the physical insertion order that the unordered
    # `LIMIT 1` fallback scans.
    Organization.connection.execute(
      "INSERT INTO organizations (id, name, scheme, identifier, host, alias_hosts, config, created_at, updated_at) " \
      "VALUES (0, 'Reserved Default', 'default-reserved', 'default-reserved', 'default.example.com', '{}', '{}', NOW(), NOW())"
    )
  end

  def make_admin(email: 'admin@example.com', password: 'password123')
    User.create!(email: email, password: password, role: 'admin')
  end

  def make_assessment(tenant_id:, name: 'Backend Engineer', time_limit_min: 30)
    Assessment.create!(
      tenant_id: tenant_id,
      created_by: 1,
      name: name,
      time_limit_min: time_limit_min
    )
  end

  def make_session(tenant_id:, assessment:)
    Session.create!(tenant_id: tenant_id, assessment_id: assessment.id)
  end

  def token_for(role:, scheme:)
    JsonWebToken.encode(user_id: 1, role: role, scheme: scheme)
  end

  def auth_headers(token)
    { 'Authorization' => "Bearer #{token}" }
  end

  def json_body
    JSON.parse(response.body)
  end

  def login_scheme(headers = {})
    post '/api/v1/auth/login',
         params:  { email: 'admin@example.com', password: 'password123' },
         headers: headers

    expect(response).to have_http_status(:ok)
    JsonWebToken.decode(json_body.fetch('token'))[:scheme]
  end

  # ── (a) B1 — session end must not trust the client's all_covered claim ─────

  describe 'B1: POST /api/v1/sessions/:token/audio_complete (expected RED)' do
    it 'does not record all_covered for a session with zero coverage maps' do
      org        = make_org('tenant-a')
      assessment = make_assessment(tenant_id: org.id)
      session    = make_session(tenant_id: org.id, assessment: assessment)
      expect(session.coverage_maps.count).to eq(0)

      post "/api/v1/sessions/#{session.invite_token}/audio_complete"

      expect(response).to have_http_status(:ok)
      expect(session.reload.end_reason).not_to eq('all_covered'),
        'audio_complete trusted the client claim and ended with all_covered despite zero coverage'
    end

    it 'does not record all_covered for a session with incomplete (partial) coverage' do
      org        = make_org('tenant-a')
      assessment = make_assessment(tenant_id: org.id)
      session    = make_session(tenant_id: org.id, assessment: assessment)
      session.coverage_maps.create!(skill_id: 'ruby', skill_label: 'Ruby', state: 'partial', probe_count: 2)

      post "/api/v1/sessions/#{session.invite_token}/audio_complete"

      expect(response).to have_http_status(:ok)
      expect(session.reload.end_reason).not_to eq('all_covered'),
        'audio_complete recorded all_covered while coverage was still partial'
    end
  end

  # ── (b) B4 — deterministic tenant fallback that never binds id=0 ───────────

  describe 'B4: POST /api/v1/auth/login tenant fallback (expected RED)' do
    it 'never binds the reserved id=0 org and is deterministic with >= 2 orgs present' do
      make_reserved_org! # inserted first: physical head of the unordered LIMIT 1
      make_org('tenant-real')
      make_admin

      first  = login_scheme
      second = login_scheme

      expect(second).to eq(first), 'fallback must be deterministic across logins'
      expect(first).not_to eq('default-reserved'), 'fallback bound the reserved id=0 org'
      expect(first).to eq('tenant-real')
    end

    it 'lets an explicit X-Tenant-Scheme header win over the fallback' do
      make_org('tenant-a')
      make_org('tenant-b')
      make_admin

      expect(login_scheme('X-Tenant-Scheme' => 'tenant-b')).to eq('tenant-b')
    end
  end

  # ── (c) assessor-only routes reject non-assessor roles ─────────────────────

  describe '(c) assessor-only routes' do
    it 'rejects a non-assessor role token with 403' do
      get '/api/v1/assessments', headers: auth_headers(token_for(role: 'user', scheme: 'tenant-a'))

      expect(response).to have_http_status(:forbidden)
      expect(json_body.dig('errors', 0, 'status')).to eq(403)
    end
  end

  # ── (d) candidate routes: no JWT, invite token only ────────────────────────

  describe '(d) no-JWT candidate routes (invite token only)' do
    it 'serves candidate_info without an Authorization header' do
      org        = make_org('tenant-a')
      assessment = make_assessment(tenant_id: org.id, name: 'Backend Engineer')
      session    = make_session(tenant_id: org.id, assessment: assessment)

      get "/api/v1/sessions/#{session.invite_token}/candidate"

      expect(response).to have_http_status(:ok)
      expect(json_body['session_id']).to eq(session.id)
      expect(json_body['role_title']).to eq('Backend Engineer')
      expect(json_body['session_status']).to eq('pending')
    end

    it 'rejects an invalid invite token on candidate_info with 404' do
      get '/api/v1/sessions/not-a-real-token/candidate'

      expect(response).to have_http_status(:not_found)
      expect(json_body.dig('errors', 0, 'message')).to match(/invalid or expired/i)
    end

    it 'rejects an invalid invite token on audio_complete with 404' do
      post '/api/v1/sessions/not-a-real-token/audio_complete'

      expect(response).to have_http_status(:not_found)
      expect(json_body.dig('errors', 0, 'message')).to match(/invalid or expired/i)
    end
  end

  # ── (e) cross-tenant reads do not leak ─────────────────────────────────────

  describe '(e) cross-tenant isolation' do
    it '404s a session read from another tenant and 200s for the owning tenant' do
      org_a      = make_org('tenant-a')
      org_b      = make_org('tenant-b')
      assessment = make_assessment(tenant_id: org_a.id)
      session    = make_session(tenant_id: org_a.id, assessment: assessment)

      get "/api/v1/sessions/#{session.id}", headers: auth_headers(token_for(role: 'admin', scheme: 'tenant-b'))
      expect(response).to have_http_status(:not_found)

      # Positive control: the owning tenant can read the same session.
      get "/api/v1/sessions/#{session.id}", headers: auth_headers(token_for(role: 'admin', scheme: 'tenant-a'))
      expect(response).to have_http_status(:ok)
      expect(json_body.dig('session', 'id')).to eq(session.id)
    end
  end
end
