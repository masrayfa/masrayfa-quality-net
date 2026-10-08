# frozen_string_literal: true

module Api
  module V1
    class AuthenticationController < ApiController
      skip_before_action :require_tenant!

      # POST /api/v1/auth/login
      def authenticate
        user = User.find_by(email: params[:email].to_s.downcase)

        return json_error('Invalid email or password', :unauthorized) unless user&.authenticate(params[:password])

        return json_error('Invalid email or password', :unauthorized) unless user.role == 'admin'

        scheme = resolve_scheme
        return json_error('Unknown tenant scheme', :bad_request) if scheme.nil?

        token  = JsonWebToken.encode({ user_id: user.id, role: user.role, scheme: })

        json_response({ token:, user: { id: user.id, email: user.email, role: user.role } })
      end

      private

      def resolve_scheme
        requested = request.headers['X-Tenant-Scheme'].presence
        return fallback_scheme if requested.nil?

        # C3b guard: only a real, non-reserved org scheme may be requested.
        # (No user<->org membership model exists in this schema, so an
        # authenticated admin can still target any existing org — risk
        # accepted and recorded in assessment/risk-register.json.)
        Organization.where.not(id: 0).where(scheme: requested).pick(:scheme)
      end

      def fallback_scheme
        ActiveRecord::Base.connection.select_value(
          # Deterministic fallback; id=0 is the reserved default org (db/seeds.rb) and must never bind.
          # ponytail: no discarded_at column exists on organizations; add a soft-delete guard if one lands.
          'SELECT scheme FROM organizations WHERE id != 0 ORDER BY id LIMIT 1'
        ) || 'test-corp'
      end
    end
  end
end
