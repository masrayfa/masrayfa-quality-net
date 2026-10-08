# frozen_string_literal: true

require 'rails_helper'

# B2 regression lock: Portfolios::Generator#save_skills must be transactional
# and must reject invalid level/confidence instead of persisting partially.
#
# Red-first history: the malformed skill is deliberately SECOND so the
# pre-fix code commits the first row before raising (orphan row on a failed
# portfolio). See .omo/evidence/25-fix-b2.txt.
RSpec.describe Portfolios::Generator do
  # The injected seam from Generator#initialize(session:, gemini_client:).
  def fake_gemini(response)
    Class.new do
      define_method(:initialize) { |payload| @payload = payload }
      define_method(:generate_content) { |_prompt, temperature: nil| @payload }
    end.new(response)
  end

  def make_session
    org = Organization.create!(
      name: 'Tenant A', scheme: 'tenant-a', identifier: 'tenant-a', host: 'tenant-a.example.com'
    )
    assessment = Assessment.create!(
      tenant_id: org.id, created_by: 1, name: 'Backend Engineer', time_limit_min: 30
    )
    Session.create!(tenant_id: org.id, assessment_id: assessment.id)
  end

  def valid_skill(label: 'React / Frontend Development')
    {
      'skill_id'           => 'sk-eng-001',
      'skill_label'        => label,
      'level'              => 3,
      'confidence'         => 'high',
      'evidence'           => ['quote 1', 'quote 2'],
      'competency_summary' => 'Consistent L3 behavior.'
    }
  end

  # Returns the raised error, or nil when the generator does not raise.
  def run_generator(session, response)
    described_class.new(session: session, gemini_client: fake_gemini(response)).call
    nil
  rescue StandardError => e
    e
  end

  describe '#call with malformed skill data (B2)' do
    it 'rolls back and leaves the portfolio failed when the 2nd skill confidence is invalid' do
      session  = make_session
      response = {
        'configured_skills' => [
          valid_skill,
          valid_skill(label: 'PostgreSQL').merge('confidence' => 'certain')
        ]
      }

      error = run_generator(session, response)

      expect(error).not_to be_nil, 'generator must raise on an invalid confidence'
      portfolio = session.reload.portfolio
      expect(portfolio.generation_status).to eq('failed')
      expect(portfolio.portfolio_skills.reload.count).to eq(0),
        'expected rollback to leave ZERO skill rows, ' \
        "found #{portfolio.portfolio_skills.count} (partial persistence)"
    end

    it 'rolls back and leaves the portfolio failed when the 2nd skill level is out of range' do
      session  = make_session
      response = {
        'configured_skills' => [
          valid_skill,
          valid_skill(label: 'PostgreSQL').merge('level' => 9)
        ]
      }

      error = run_generator(session, response)

      expect(error).not_to be_nil, 'generator must raise on an out-of-range level'
      portfolio = session.reload.portfolio
      expect(portfolio.generation_status).to eq('failed')
      expect(portfolio.portfolio_skills.reload.count).to eq(0),
        'expected rollback to leave ZERO skill rows, ' \
        "found #{portfolio.portfolio_skills.count} (out-of-range level persisted)"
    end

    it 'still persists every skill and completes for a valid response (positive control)' do
      session  = make_session
      response = {
        'configured_skills' => [valid_skill, valid_skill(label: 'PostgreSQL').merge('level' => 4)],
        'discovered_skills' => [valid_skill(label: 'Micro-frontend Architecture').merge('skill_id' => nil)]
      }

      error = run_generator(session, response)

      expect(error).to be_nil
      portfolio = session.reload.portfolio
      expect(portfolio.generation_status).to eq('complete')
      expect(portfolio.portfolio_skills.count).to eq(3)
      expect(portfolio.portfolio_skills.pluck(:ai_level)).to contain_exactly(3, 4, 3)
    end
  end
end
